import crypto from 'node:crypto';
import { config } from '../config.js';
import { adminSupabase } from '../lib/supabase.js';

export interface PhoneVerificationSession {
  id: string;
  phoneE164: string;
  challengeHash: string;
  status: 'CREATED' | 'WAITING_FOR_WHATSAPP' | 'PHONE_VERIFIED' | 'EXPIRED' | 'CONSUMED' | 'BLOCKED';
  expiresAt: Date;
  attemptCount: number;
  verifiedAt?: Date | undefined;
  consumedAt?: Date | undefined;
  createdAt: Date;
}

export function normalizePhoneNumber(raw: string, defaultCountryCode: string = '+91'): string {
  let cleaned = raw.trim().replace(/[\s\-\(\)\.]/g, '');
  if (!cleaned.startsWith('+')) {
    if (cleaned.startsWith('00')) {
      cleaned = '+' + cleaned.substring(2);
    } else if (cleaned.startsWith('91') && cleaned.length === 12) {
      cleaned = '+' + cleaned;
    } else if (cleaned.startsWith('0')) {
      cleaned = defaultCountryCode + cleaned.substring(1);
    } else if (defaultCountryCode.startsWith('+')) {
      cleaned = defaultCountryCode + cleaned;
    } else {
      cleaned = '+' + defaultCountryCode + cleaned;
    }
  }

  if (cleaned.startsWith('+91')) {
    if (!/^\+91[6-9]\d{9}$/.test(cleaned)) {
      throw new Error(`Invalid Indian mobile phone number format: ${raw}. Must be 10 digits starting with 6-9.`);
    }
  } else {
    // Validate E.164 pattern: + followed by 7 to 15 digits
    const e164Regex = /^\+[1-9]\d{6,14}$/;
    if (!e164Regex.test(cleaned)) {
      throw new Error(`Invalid E.164 phone number format: ${raw}`);
    }
  }

  return cleaned;
}

export function hashChallenge(challenge: string): string {
  return crypto.createHash('sha256').update(challenge.trim().toUpperCase()).digest('hex');
}

export interface IPhoneVerificationProvider {
  startVerification(phoneE164: string): Promise<{
    sessionId: string;
    challenge: string;
    whatsappUrl: string;
    expiresAt: string;
  }>;
  processInboundMessage(senderPhoneE164: string, messageText: string): Promise<{
    success: boolean;
    sessionId?: string;
    error?: string;
  }>;
  getSessionStatus(sessionId: string): Promise<{
    id: string;
    status: PhoneVerificationSession['status'];
    phoneE164?: string | undefined;
    verifiedAt?: string | undefined;
    expiresAt: string;
  }>;
  consumeSession(sessionId: string): Promise<{
    phoneE164: string;
  }>;
}

export class WhatsAppInboundChallengeProvider implements IPhoneVerificationProvider {
  private sessionStore = new Map<string, PhoneVerificationSession>();

  async startVerification(phoneE164: string): Promise<{
    sessionId: string;
    challenge: string;
    whatsappUrl: string;
    expiresAt: string;
  }> {
    const normalizedPhone = normalizePhoneNumber(phoneE164);
    const now = new Date();

    // 1. Rate-Limiting & Abuse Prevention Checks (Database-Authoritative & In-Memory Fallback)
    try {
      // Cooldown check: Prevent new challenge within 30 seconds for the same phone if an active challenge is pending
      const cooldownThreshold = new Date(now.getTime() - 30 * 1000).toISOString();
      const { data: recentSessions } = await adminSupabase
        .from('phone_verification_sessions')
        .select('id, created_at, status, expires_at')
        .eq('phone_e164', normalizedPhone)
        .eq('status', 'WAITING_FOR_WHATSAPP')
        .gte('created_at', cooldownThreshold)
        .order('created_at', { ascending: false })
        .limit(1);

      if (recentSessions && recentSessions.length > 0) {
        throw new Error('Please wait 30 seconds before requesting another verification challenge.');
      }

      // Active sessions cap: Maximum 3 active unexpired challenges simultaneously
      const { data: activeSessions } = await adminSupabase
        .from('phone_verification_sessions')
        .select('id')
        .eq('phone_e164', normalizedPhone)
        .eq('status', 'WAITING_FOR_WHATSAPP')
        .gt('expires_at', now.toISOString());

      if (activeSessions && activeSessions.length >= 3) {
        throw new Error('Too many active verification challenges. Please complete or wait for existing challenges to expire.');
      }
    } catch (dbErr: any) {
      if (dbErr?.message && (dbErr.message.includes('Please wait 30 seconds') || dbErr.message.includes('Too many active verification'))) {
        throw dbErr;
      }
      // Fallback in-memory rate check if DB query failed
      let activeCount = 0;
      for (const sess of this.sessionStore.values()) {
        if (sess.phoneE164 === normalizedPhone && sess.status === 'WAITING_FOR_WHATSAPP') {
          if (now.getTime() - sess.createdAt.getTime() < 30 * 1000) {
            throw new Error('Please wait 30 seconds before requesting another verification challenge.');
          }
          if (sess.expiresAt > now) {
            activeCount++;
          }
        }
      }
      if (activeCount >= 3) {
        throw new Error('Too many active verification challenges. Please complete or wait for existing challenges to expire.');
      }
    }

    const sessionId = crypto.randomUUID();
    // High-entropy 6-character alphanumeric challenge
    const challengeCode = crypto.randomBytes(3).toString('hex').toUpperCase();
    const challengeMessage = `VERIFY SHIPDEHOP ${challengeCode}`;
    const challengeHash = hashChallenge(challengeMessage);
    const expiresAt = new Date(Date.now() + 5 * 60 * 1000); // 5 minutes TTL

    const session: PhoneVerificationSession = {
      id: sessionId,
      phoneE164: normalizedPhone,
      challengeHash,
      status: 'WAITING_FOR_WHATSAPP',
      expiresAt,
      attemptCount: 0,
      createdAt: now,
    };

    this.sessionStore.set(sessionId, session);

    // Also persist to Supabase if available
    try {
      await adminSupabase.from('phone_verification_sessions').insert({
        id: sessionId,
        phone_e164: normalizedPhone,
        challenge_hash: challengeHash,
        status: 'WAITING_FOR_WHATSAPP',
        expires_at: expiresAt.toISOString(),
      });
    } catch {
      // In-memory session store provides resilient fallback
    }

    const botNumberClean = (config.WHATSAPP_BOT_NUMBER || '+15550009427').replace(/\+/g, '');
    const whatsappUrl = `https://wa.me/${botNumberClean}?text=${encodeURIComponent(challengeMessage)}`;

    return {
      sessionId,
      challenge: challengeMessage,
      whatsappUrl,
      expiresAt: expiresAt.toISOString(),
    };
  }

  async processInboundMessage(senderPhoneE164: string, messageText: string): Promise<{
    success: boolean;
    sessionId?: string;
    error?: string;
  }> {
    const normalizedSender = normalizePhoneNumber(senderPhoneE164);
    const trimmedMessage = messageText.trim();
    const cleanCode = trimmedMessage.toUpperCase().replace(/^VERIFY\s+SHIPDEHOP\s+/i, '');
    const canonicalMessage = `VERIFY SHIPDEHOP ${cleanCode}`;
    const incomingHash = hashChallenge(canonicalMessage);
    const now = new Date();

    // 1. Authoritative Supabase lookup & race-safe atomic transition
    try {
      const { data: dbSessions, error: selectError } = await adminSupabase
        .from('phone_verification_sessions')
        .select('*')
        .eq('phone_e164', normalizedSender)
        .eq('challenge_hash', incomingHash)
        .order('created_at', { ascending: false })
        .limit(1);

      if (!selectError && dbSessions && dbSessions.length > 0) {
        const dbSession = dbSessions[0];
        const expiresAt = new Date(dbSession.expires_at);

        if (dbSession.status === 'CONSUMED' || dbSession.consumed_at) {
          return { success: false, error: 'Challenge has already been consumed.' };
        }
        if (dbSession.status === 'PHONE_VERIFIED' || dbSession.verified_at) {
          return { success: true, sessionId: dbSession.id };
        }
        if (dbSession.status === 'BLOCKED' || (dbSession.attempt_count || 0) >= 3) {
          return { success: false, error: 'Max attempts exceeded.' };
        }
        if (expiresAt < now || dbSession.status === 'EXPIRED') {
          return { success: false, error: 'Challenge has expired.' };
        }

        if (dbSession.status === 'WAITING_FOR_WHATSAPP') {
          // Full atomic conditional transition strictly constraining all eligibility invariants
          const { data: updatedRows, error: updateErr } = await adminSupabase
            .from('phone_verification_sessions')
            .update({
              status: 'PHONE_VERIFIED',
              verified_at: now.toISOString(),
              attempt_count: (dbSession.attempt_count || 0) + 1,
            })
            .eq('id', dbSession.id)
            .eq('phone_e164', normalizedSender)
            .eq('challenge_hash', incomingHash)
            .eq('status', 'WAITING_FOR_WHATSAPP')
            .gt('expires_at', now.toISOString())
            .is('consumed_at', null)
            .is('verified_at', null)
            .lt('attempt_count', 3)
            .select();

          if (updateErr || !updatedRows || updatedRows.length !== 1) {
            return { success: false, error: 'Failed to verify session or session was concurrently updated.' };
          }

          // Invalidate/populate in-memory cache to keep local process state consistent
          const verifiedSession: PhoneVerificationSession = {
            id: dbSession.id,
            phoneE164: dbSession.phone_e164,
            challengeHash: dbSession.challenge_hash,
            status: 'PHONE_VERIFIED',
            expiresAt: new Date(dbSession.expires_at),
            attemptCount: (dbSession.attempt_count || 0) + 1,
            verifiedAt: now,
            createdAt: new Date(dbSession.created_at),
          };
          this.sessionStore.set(dbSession.id, verifiedSession);

          return { success: true, sessionId: dbSession.id };
        }
      }
    } catch {
      // Fall through to in-memory store
    }

    // 2. In-memory store fallback (for offline unit tests / mock mode)
    for (const [id, session] of this.sessionStore.entries()) {
      if (session.phoneE164 === normalizedSender && session.challengeHash === incomingHash) {
        if (session.expiresAt < now) {
          session.status = 'EXPIRED';
          return { success: false, error: 'Challenge has expired.' };
        }
        if (session.status === 'CONSUMED') {
          return { success: false, error: 'Challenge has already been consumed.' };
        }
        if (session.status === 'PHONE_VERIFIED') {
          return { success: true, sessionId: id };
        }
        if (session.attemptCount >= 3) {
          session.status = 'BLOCKED';
          return { success: false, error: 'Max attempts exceeded.' };
        }

        // Successfully verified in memory
        session.status = 'PHONE_VERIFIED';
        session.verifiedAt = now;
        session.attemptCount += 1;

        try {
          await adminSupabase.from('phone_verification_sessions').update({
            status: 'PHONE_VERIFIED',
            verified_at: now.toISOString(),
            attempt_count: session.attemptCount,
          }).eq('id', id);
        } catch {
          // Keep in-memory verified
        }

        return { success: true, sessionId: id };
      }
    }

    return { success: false, error: 'No matching active challenge found for sender phone and message.' };
  }

  async getSessionStatus(sessionId: string): Promise<{
    id: string;
    status: PhoneVerificationSession['status'];
    phoneE164?: string | undefined;
    verifiedAt?: string | undefined;
    expiresAt: string;
  }> {
    let session = this.sessionStore.get(sessionId);

    // If session is absent from memory, OR still in WAITING_FOR_WHATSAPP state,
    // query authoritative Supabase to check if another process verified/expired/consumed it.
    if (!session || session.status === 'WAITING_FOR_WHATSAPP') {
      try {
        const { data } = await adminSupabase
          .from('phone_verification_sessions')
          .select('*')
          .eq('id', sessionId)
          .maybeSingle();

        if (data) {
          session = {
            id: data.id,
            phoneE164: data.phone_e164,
            challengeHash: data.challenge_hash,
            status: data.status,
            expiresAt: new Date(data.expires_at),
            attemptCount: data.attempt_count,
            verifiedAt: data.verified_at ? new Date(data.verified_at) : undefined,
            consumedAt: data.consumed_at ? new Date(data.consumed_at) : undefined,
            createdAt: new Date(data.created_at),
          };
          this.sessionStore.set(sessionId, session);
        }
      } catch {
        // Fall through to memory
      }
    }

    if (!session) {
      throw new Error(`Verification session ${sessionId} not found.`);
    }

    if (session.status === 'WAITING_FOR_WHATSAPP' && session.expiresAt < new Date()) {
      session.status = 'EXPIRED';
    }

    return {
      id: session.id,
      status: session.status,
      phoneE164: session.status === 'PHONE_VERIFIED' ? session.phoneE164 : undefined,
      verifiedAt: session.verifiedAt ? session.verifiedAt.toISOString() : undefined,
      expiresAt: session.expiresAt.toISOString(),
    };
  }

  async consumeSession(sessionId: string): Promise<{ phoneE164: string }> {
    const now = new Date();
    let session = this.sessionStore.get(sessionId);

    // Always fetch authoritative database state if absent or not yet CONSUMED
    if (!session || session.status !== 'CONSUMED') {
      try {
        const { data } = await adminSupabase
          .from('phone_verification_sessions')
          .select('*')
          .eq('id', sessionId)
          .maybeSingle();

        if (data) {
          session = {
            id: data.id,
            phoneE164: data.phone_e164,
            challengeHash: data.challenge_hash,
            status: data.status,
            expiresAt: new Date(data.expires_at),
            attemptCount: data.attempt_count,
            verifiedAt: data.verified_at ? new Date(data.verified_at) : undefined,
            consumedAt: data.consumed_at ? new Date(data.consumed_at) : undefined,
            createdAt: new Date(data.created_at),
          };
          this.sessionStore.set(sessionId, session);
        }
      } catch {
        // Fall through to memory
      }
    }

    if (!session) {
      throw new Error(`Verification session ${sessionId} not found.`);
    }

    if (session.status === 'CONSUMED' || session.consumedAt) {
      throw new Error('Verification session has already been consumed.');
    }

    if (session.status !== 'PHONE_VERIFIED' || !session.verifiedAt) {
      throw new Error(`Cannot exchange unverified session. Current status: ${session.status}`);
    }

    if (session.expiresAt < now) {
      session.status = 'EXPIRED';
      throw new Error('Verification session has expired.');
    }

    // Atomic race-safe conditional transition in Supabase
    try {
      const { data: updatedRows, error: updateErr } = await adminSupabase
        .from('phone_verification_sessions')
        .update({
          status: 'CONSUMED',
          consumed_at: now.toISOString(),
        })
        .eq('id', sessionId)
        .eq('status', 'PHONE_VERIFIED')
        .is('consumed_at', null)
        .gt('expires_at', now.toISOString())
        .select();

      if (updateErr || !updatedRows || updatedRows.length !== 1) {
        throw new Error('Verification session cannot be consumed or was concurrently consumed.');
      }
    } catch (dbErr: any) {
      if (dbErr?.message?.includes('cannot be consumed')) {
        throw dbErr;
      }
    }

    session.status = 'CONSUMED';
    session.consumedAt = now;
    this.sessionStore.set(sessionId, session);

    return { phoneE164: session.phoneE164 };
  }
}

export class DevelopmentPhoneVerificationProvider implements IPhoneVerificationProvider {
  private baseProvider = new WhatsAppInboundChallengeProvider();

  constructor() {
    if (config.NODE_ENV === 'production') {
      throw new Error('DevelopmentPhoneVerificationProvider is strictly forbidden in production.');
    }
  }

  async startVerification(phoneE164: string) {
    return this.baseProvider.startVerification(phoneE164);
  }

  async processInboundMessage(senderPhoneE164: string, messageText: string) {
    return this.baseProvider.processInboundMessage(senderPhoneE164, messageText);
  }

  async getSessionStatus(sessionId: string) {
    return this.baseProvider.getSessionStatus(sessionId);
  }

  async consumeSession(sessionId: string) {
    return this.baseProvider.consumeSession(sessionId);
  }
}

let providerInstance: IPhoneVerificationProvider | null = null;

export function getPhoneVerificationProvider(): IPhoneVerificationProvider {
  if (!providerInstance) {
    if (config.PHONE_VERIFICATION_PROVIDER === 'WHATSAPP_INBOUND' || config.PHONE_VERIFICATION_PROVIDER === 'MANUAL_BETA') {
      providerInstance = new WhatsAppInboundChallengeProvider();
    } else {
      providerInstance = new DevelopmentPhoneVerificationProvider();
    }
  }
  return providerInstance;
}

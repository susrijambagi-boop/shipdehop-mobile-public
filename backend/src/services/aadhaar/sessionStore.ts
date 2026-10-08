import crypto from 'node:crypto';
import { AadhaarSession, AadhaarSessionStore } from './types.js';

/**
 * InMemoryAadhaarSessionStore
 *
 * NOTE FOR PRODUCTION ARCHITECTURE:
 * For local sandbox/development testing, process-memory storage is used.
 * Production MUST use a durable encrypted shared store (such as Supabase DB or Redis)
 * to prevent process-restart session loss and multi-instance session decoupling.
 */
export class InMemoryAadhaarSessionStore implements AadhaarSessionStore {
  private sessions = new Map<string, AadhaarSession>();

  async createSession(params: { userId: string; maskedAadhaar: string; otpTxnId?: string; transientUidEncrypted?: string }): Promise<AadhaarSession> {
    const sessionId = `uidai_sess_${Date.now()}_${crypto.randomBytes(8).toString('hex')}`;
    const now = new Date();
    const expiresAt = new Date(now.getTime() + 10 * 60 * 1000); // 10 minute TTL

    const session: AadhaarSession = {
      sessionId,
      userId: params.userId,
      maskedAadhaar: params.maskedAadhaar,
      otpTxnId: params.otpTxnId,
      transientUidEncrypted: params.transientUidEncrypted,
      createdAt: now,
      expiresAt,
      lastOtpSentAt: now,
      resendAttempts: 0,
      verifyAttempts: 0,
      status: 'PENDING_OTP',
    };

    this.sessions.set(sessionId, session);
    return session;
  }

  async getSession(sessionId: string): Promise<AadhaarSession | null> {
    const session = this.sessions.get(sessionId);
    if (!session) return null;

    // Check expiration
    if (Date.now() > session.expiresAt.getTime() && session.status === 'PENDING_OTP') {
      session.status = 'EXPIRED';
    }

    return session;
  }

  async updateSession(session: AadhaarSession): Promise<void> {
    this.sessions.set(session.sessionId, session);
  }

  /**
   * Atomic session consumption:
   * Enforces single-use verification to prevent session reuse/replay attacks.
   */
  async consumeSession(sessionId: string): Promise<{ success: boolean; session?: AadhaarSession; error?: string }> {
    const session = this.sessions.get(sessionId);
    if (!session) {
      return { success: false, error: 'SESSION_NOT_FOUND' };
    }

    if (session.status === 'CONSUMED') {
      return { success: false, error: 'SESSION_ALREADY_CONSUMED' };
    }

    if (session.status === 'EXPIRED' || Date.now() > session.expiresAt.getTime()) {
      session.status = 'EXPIRED';
      return { success: false, error: 'SESSION_EXPIRED' };
    }

    if (session.status === 'MAX_ATTEMPTS_EXCEEDED') {
      return { success: false, error: 'MAX_ATTEMPTS_EXCEEDED' };
    }

    // Atomic state update to CONSUMED
    session.status = 'CONSUMED';
    session.consumedAt = new Date();
    this.sessions.set(sessionId, session);

    return { success: true, session };
  }

  async expireSession(sessionId: string): Promise<void> {
    const session = this.sessions.get(sessionId);
    if (session) {
      session.status = 'EXPIRED';
      this.sessions.set(sessionId, session);
    }
  }
}

// Global default session store instance for local development
export const defaultAadhaarSessionStore = new InMemoryAadhaarSessionStore();

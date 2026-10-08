import crypto from 'node:crypto';

import { config } from '../config.js';
import { adminSupabase } from '../lib/supabase.js';
import { whatsappOtpBridge } from './whatsapp_otp_bridge.js';
import { normalizePhoneNumber } from './phone_verification.js';

const OTP_TTL_MS = 5 * 60 * 1000;
const START_COOLDOWN_MS = 30 * 1000;
const MAX_VERIFY_ATTEMPTS = 5;

function otpKey(): string {
  return config.SHIPDEHOP_JWT_PRIVATE_JWK ||
    config.SHIPDEHOP_JWT_PRIVATE_KEY_PEM ||
    config.SUPABASE_SECRET_KEY;
}

function hashOtp(sessionId: string, otp: string): string {
  return crypto
    .createHmac('sha256', otpKey())
    .update(`${sessionId}:${otp}`)
    .digest('hex');
}

function generateOtp(): string {
  return crypto.randomInt(0, 1_000_000).toString().padStart(6, '0');
}

export async function startWhatsAppOtp(rawPhone: string, countryCode = '+91') {
  const phoneE164 = normalizePhoneNumber(rawPhone, countryCode);
  const now = new Date();

  const cooldownThreshold = new Date(now.getTime() - START_COOLDOWN_MS).toISOString();
  const { data: recent, error: recentError } = await adminSupabase
    .from('phone_verification_sessions')
    .select('id,created_at,status')
    .eq('phone_e164', phoneE164)
    .gte('created_at', cooldownThreshold)
    .in('status', ['WAITING_FOR_WHATSAPP', 'PHONE_VERIFIED'])
    .order('created_at', { ascending: false })
    .limit(1);

  if (recentError) throw recentError;
  if (recent && recent.length > 0) {
    throw Object.assign(new Error('Please wait 30 seconds before requesting another OTP.'), { statusCode: 429 });
  }

  const sessionId = crypto.randomUUID();
  const otp = generateOtp();
  const expiresAt = new Date(now.getTime() + OTP_TTL_MS);

  const { error: insertError } = await adminSupabase
    .from('phone_verification_sessions')
    .insert({
      id: sessionId,
      phone_e164: phoneE164,
      challenge_hash: hashOtp(sessionId, otp),
      status: 'WAITING_FOR_WHATSAPP',
      expires_at: expiresAt.toISOString(),
      attempt_count: 0,
      otp_send_attempts: 0,
      delivery_provider: 'BAILEYS_SELF_HOSTED',
    });

  if (insertError) throw insertError;

  try {
    const sent = await whatsappOtpBridge.sendOtp(phoneE164, otp);

    await adminSupabase
      .from('phone_verification_sessions')
      .update({
        otp_send_attempts: sent.attempts,
        otp_sent_at: new Date().toISOString(),
        otp_message_id: sent.messageId,
        otp_last_error: null,
      })
      .eq('id', sessionId);

    return {
      sessionId,
      phoneE164,
      expiresAt: expiresAt.toISOString(),
      deliveryStatus: 'SENT',
    };
  } catch (error: any) {
    await adminSupabase
      .from('phone_verification_sessions')
      .update({
        otp_send_attempts: 3,
        otp_last_error: error?.message || 'WhatsApp OTP send failed',
        status: 'EXPIRED',
      })
      .eq('id', sessionId);

    throw Object.assign(
      new Error('WhatsApp is temporarily unavailable. Please retry in a moment.'),
      { statusCode: 503 },
    );
  }
}

export async function verifyWhatsAppOtp(sessionId: string, otp: string) {
  if (!/^\d{6}$/.test(otp)) {
    throw Object.assign(new Error('Enter the 6-digit WhatsApp OTP.'), { statusCode: 400 });
  }

  const { data, error } = await adminSupabase
    .from('phone_verification_sessions')
    .select('*')
    .eq('id', sessionId)
    .maybeSingle();

  if (error) throw error;
  if (!data) throw Object.assign(new Error('OTP session not found.'), { statusCode: 404 });

  if (data.status === 'CONSUMED') {
    throw Object.assign(new Error('OTP session has already been used.'), { statusCode: 400 });
  }
  if (data.status === 'PHONE_VERIFIED') {
    return { success: true, status: 'PHONE_VERIFIED', phoneE164: data.phone_e164 };
  }
  if (data.status === 'BLOCKED') {
    throw Object.assign(new Error('Too many incorrect OTP attempts. Request a new code.'), { statusCode: 429 });
  }
  if (new Date(data.expires_at).getTime() <= Date.now()) {
    await adminSupabase
      .from('phone_verification_sessions')
      .update({ status: 'EXPIRED' })
      .eq('id', sessionId)
      .eq('status', 'WAITING_FOR_WHATSAPP');
    throw Object.assign(new Error('OTP expired. Request a new code.'), { statusCode: 410 });
  }

  const nextAttempts = Number(data.attempt_count || 0) + 1;
  const expected = String(data.challenge_hash || '');
  const actual = hashOtp(sessionId, otp);
  const expectedBuf = Buffer.from(expected, 'hex');
  const actualBuf = Buffer.from(actual, 'hex');
  const matches =
    expectedBuf.length === actualBuf.length &&
    expectedBuf.length > 0 &&
    crypto.timingSafeEqual(expectedBuf, actualBuf);

  if (!matches) {
    const blocked = nextAttempts >= MAX_VERIFY_ATTEMPTS;
    await adminSupabase
      .from('phone_verification_sessions')
      .update({
        attempt_count: nextAttempts,
        status: blocked ? 'BLOCKED' : 'WAITING_FOR_WHATSAPP',
      })
      .eq('id', sessionId)
      .eq('status', 'WAITING_FOR_WHATSAPP');

    throw Object.assign(
      new Error(blocked ? 'Too many incorrect OTP attempts. Request a new code.' : 'Incorrect OTP. Please try again.'),
      { statusCode: blocked ? 429 : 400 },
    );
  }

  const verifiedAt = new Date().toISOString();
  const { data: updated, error: updateError } = await adminSupabase
    .from('phone_verification_sessions')
    .update({
      status: 'PHONE_VERIFIED',
      verified_at: verifiedAt,
      attempt_count: nextAttempts,
    })
    .eq('id', sessionId)
    .eq('status', 'WAITING_FOR_WHATSAPP')
    .gt('expires_at', verifiedAt)
    .select('id,phone_e164,status,verified_at')
    .maybeSingle();

  if (updateError) throw updateError;
  if (!updated) {
    throw Object.assign(new Error('OTP session changed or expired. Request a new code.'), { statusCode: 409 });
  }

  return {
    success: true,
    status: 'PHONE_VERIFIED',
    phoneE164: updated.phone_e164,
    verifiedAt: updated.verified_at,
  };
}

export async function getWhatsAppOtpStatus(sessionId: string) {
  const { data, error } = await adminSupabase
    .from('phone_verification_sessions')
    .select('id,phone_e164,status,expires_at,verified_at,otp_sent_at')
    .eq('id', sessionId)
    .maybeSingle();

  if (error) throw error;
  if (!data) throw Object.assign(new Error('OTP session not found.'), { statusCode: 404 });

  let status = data.status;
  if (status === 'WAITING_FOR_WHATSAPP' && new Date(data.expires_at).getTime() <= Date.now()) {
    status = 'EXPIRED';
    await adminSupabase
      .from('phone_verification_sessions')
      .update({ status: 'EXPIRED' })
      .eq('id', sessionId)
      .eq('status', 'WAITING_FOR_WHATSAPP');
  }

  return {
    id: data.id,
    status,
    phoneE164: data.phone_e164,
    expiresAt: data.expires_at,
    verifiedAt: data.verified_at,
    otpSentAt: data.otp_sent_at,
  };
}

export async function consumeWhatsAppOtpSession(sessionId: string): Promise<{ phoneE164: string }> {
  const now = new Date().toISOString();
  const { data, error } = await adminSupabase
    .from('phone_verification_sessions')
    .update({
      status: 'CONSUMED',
      consumed_at: now,
    })
    .eq('id', sessionId)
    .eq('status', 'PHONE_VERIFIED')
    .is('consumed_at', null)
    .gt('expires_at', now)
    .select('phone_e164')
    .maybeSingle();

  if (error) throw error;
  if (!data) {
    throw Object.assign(new Error('OTP session is not verified, expired, or already used.'), { statusCode: 400 });
  }

  return { phoneE164: data.phone_e164 };
}

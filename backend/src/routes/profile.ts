import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { adminSupabase } from '../lib/supabase.js';
import { IdentityVerificationManager } from '../services/identity_verification.js';
import { JwtSessionManager } from '../services/jwt_session.js';

export async function profileRoutes(app: FastifyInstance): Promise<void> {
  // 1. Get Own Profile (Authenticated User)
  app.get('/profile/me', async (request) => {
    const userId = request.authUser.id;

    const [{ data: user, error: userErr }, { data: completedOrders }, { data: payAccounts }, identity] = await Promise.all([
      adminSupabase.from('users').select('*').eq('id', userId).single(),
      adminSupabase.from('escrow_orders').select('id', { count: 'exact' }).or(`buyer_id.eq.${userId},provider_id.eq.${userId}`).eq('escrow_status', 'RELEASED'),
      adminSupabase.from('payment_accounts').select('provider, verified').eq('user_id', userId),
      IdentityVerificationManager.getIdentity(userId),
    ]);

    const identityVerificationStatus = identity?.verificationStatus || 'NOT_STARTED';

    if (userErr || !user) {
      // Fallback default user structure if row not initialized
      return {
        id: userId,
        email: request.authUser.email,
        phone: null,
        fullName: userId.startsWith('ed9517fc') ? 'Shipster Headquarter' : 'Susri Carrier',
        avatarUrl: null,
        ekycTier: 'TIER_2',
        trustScore: 70.0,
        xpPoints: 120,
        identityVerificationStatus,
        isIdentityVerified: identityVerificationStatus === 'VERIFIED',
        completedTransactionsCount: completedOrders?.length || 0,
        hasVerifiedPaymentAccount: (payAccounts || []).some((a) => a.verified),
        paymentAccounts: (payAccounts || []).map((a) => ({ provider: a.provider, verified: a.verified })),
        createdAt: new Date().toISOString(),
      };
    }

    return {
      id: user.id,
      email: user.email,
      phone: user.phone,
      fullName: user.full_name ?? (user.id.startsWith('ed9517fc') ? 'Shipster Headquarter' : 'Susri Carrier'),
      avatarUrl: user.avatar_url,
      ekycTier: user.ekyc_tier,
      trustScore: Number(user.trust_score),
      xpPoints: Number(user.xp_points || 0),
      identityVerificationStatus,
      isIdentityVerified: identityVerificationStatus === 'VERIFIED',
      completedTransactionsCount: completedOrders?.length || 0,
      hasVerifiedPaymentAccount: (payAccounts || []).some((a) => a.verified),
      paymentAccounts: (payAccounts || []).map((a) => ({ provider: a.provider, verified: a.verified })),
      createdAt: user.created_at,
    };
  });

  // 2. Get Safe Public Counterparty Profile
  app.get('/profile/public/:userId', async (request) => {
    const { userId } = z.object({ userId: z.string().uuid() }).parse(request.params);

    const [{ data: user }, { data: completedOrders }] = await Promise.all([
      adminSupabase.from('users').select('id, full_name, avatar_url, ekyc_tier, trust_score, created_at').eq('id', userId).single(),
      adminSupabase.from('escrow_orders').select('id', { count: 'exact' }).or(`buyer_id.eq.${userId},provider_id.eq.${userId}`).eq('escrow_status', 'RELEASED'),
    ]);

    if (!user) {
      return {
        id: userId,
        fullName: userId.startsWith('ed9517fc') ? 'Shipster Headquarter' : 'Hopster Carrier',
        avatarUrl: null,
        ekycTier: 'TIER_2',
        trustScore: 70.0,
        completedTransactionsCount: completedOrders?.length || 0,
        createdAt: new Date().toISOString(),
      };
    }

    // STRICT PRIVACY PROTECTION: Only return non-sensitive public fields
    return {
      id: user.id,
      fullName: user.full_name ?? (user.id.startsWith('ed9517fc') ? 'Shipster Headquarter' : 'Hopster Carrier'),
      avatarUrl: user.avatar_url,
      ekycTier: user.ekyc_tier,
      trustScore: Number(user.trust_score),
      completedTransactionsCount: completedOrders?.length || 0,
      createdAt: user.created_at,
    };
  });

  // 3. Update Own Safe Profile Fields
  app.patch('/profile/me', async (request) => {
    const userId = request.authUser.id;

    const body = z.object({
      fullName: z.string().min(2).max(100).optional(),
      avatarUrl: z.string().url().optional(),
      isFemale: z.boolean().optional(),
      phone: z.string().optional(),
    }).parse(request.body);

    // SECURITY CHECK: Client CANNOT mutate trust_score or xp_points directly!
    const updatePayload: Record<string, unknown> = {};
    if (body.fullName !== undefined) updatePayload.full_name = body.fullName;
    if (body.avatarUrl !== undefined) updatePayload.avatar_url = body.avatarUrl;
    if (body.isFemale !== undefined) updatePayload.is_female = body.isFemale;
    if (body.phone !== undefined) updatePayload.phone = body.phone;

    if (Object.keys(updatePayload).length === 0) {
      throw app.httpErrors.badRequest('No valid profile fields provided to update');
    }

    const { data, error } = await adminSupabase
      .from('users')
      .update(updatePayload)
      .eq('id', userId)
      .select('id, email, phone, full_name, avatar_url, ekyc_tier, trust_score, xp_points')
      .single();

    if (error) {
      throw app.httpErrors.internalServerError(error.message);
    }

    return data;
  });

  // 4. Authenticated Account Deletion Request
  app.post('/profile/delete-account', async (request, reply) => {
    const userId = request.authUser?.id || (request as any).user?.id;
    if (!userId) {
      return reply.code(401).send({ error: 'Authentication required' });
    }

    // 0. Revoke all active custom refresh sessions
    await JwtSessionManager.revokeAllUserSessions(userId);

    // 1. Purge/anonymize user PII in public.users and associated tables
    const { error: usersErr } = await adminSupabase.from('users').update({
      full_name: 'Deleted User',
      avatar_url: null,
      phone: null,
      email: null,
      is_female: null,
      ekyc_tier: 'TIER_1',
      trust_score: 0,
      xp_points: 0,
    }).eq('id', userId);

    if (usersErr) {
      return reply.code(500).send({ error: 'Failed to purge user profile record' });
    }

    // Anonymize user_identities PII if present
    const { error: identitiesErr } = await adminSupabase.from('user_identities').update({
      verified_name: 'Anonymized User',
      phone_e164: null,
      document_last4: null,
      verified_birth_year: null,
      gender: null,
    }).eq('user_id', userId);

    if (identitiesErr) {
      return reply.code(500).send({ error: 'Failed to purge user identity record' });
    }

    // 2. Prevent Supabase Auth account from signing in again
    let authDeleted = false;

    const { error: deleteErr } = await adminSupabase.auth.admin.deleteUser(userId);
    if (!deleteErr) {
      authDeleted = true;
    } else {
      // Fallback: Permanent deactivation via Auth Admin ban and PII anonymization
      const fallbackEmail = `deleted-${userId}@deleted.shipdehop.invalid`;

      let { error: banErr } = await adminSupabase.auth.admin.updateUserById(userId, {
        email: fallbackEmail,
        phone: '',
        ban_duration: '876000h',
        user_metadata: { deleted: true, status: 'DELETED' },
      });

      if (banErr) {
        // Retry without phone property if GoTrue phone format validation rejected empty string
        const { error: retryErr } = await adminSupabase.auth.admin.updateUserById(userId, {
          email: fallbackEmail,
          ban_duration: '876000h',
          user_metadata: { deleted: true, status: 'DELETED' },
        });
        banErr = retryErr;
      }

      if (banErr) {
        return reply.code(500).send({ error: 'Failed to deactivate authentication account' });
      }
    }

    return reply.send({
      success: true,
      authDeleted,
      message: authDeleted
        ? 'Account deleted from authentication system and personal data purged.'
        : 'User data purged and authentication identity permanently deactivated.',
      retentionNotice: 'Audit logs and legal transaction records retained in anonymized form as required by regulatory compliance.',
    });
  });
}

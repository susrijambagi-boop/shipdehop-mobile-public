import assert from 'node:assert/strict';
import Fastify from 'fastify';
import sensible from '@fastify/sensible';
import { adminSupabase } from './lib/supabase.js';
import { registerAuth } from './lib/auth.js';
import { profileRoutes } from './routes/profile.js';
import { phoneVerificationRoutes } from './routes/phone_verification.js';
import { JwtSessionManager } from './services/jwt_session.js';

async function createTestApp() {
  const app = Fastify({ logger: false });
  await app.register(sensible);
  await app.register(registerAuth);
  await app.register(profileRoutes);
  await app.register(phoneVerificationRoutes);
  await app.ready();
  return app;
}

async function cleanupTemporaryUsers() {
  const { data: page } = await adminSupabase.auth.admin.listUsers();
  if (page?.users) {
    for (const u of page.users) {
      if (u.email && u.email.includes('test_delete_')) {
        await adminSupabase.auth.admin.deleteUser(u.id);
        await adminSupabase.from('users').delete().eq('id', u.id);
        try {
          await adminSupabase.from('user_identities').delete().eq('user_id', u.id);
        } catch (_e) {}
      }
    }
  }
}

async function runAccountDeletionTest() {
  console.log('--- Account Deletion & Security Real Harness Test Suite ---');
  if (process.env.SUPABASE_URL?.includes('placeholder.supabase.co') || !process.env.SUPABASE_URL) {
    console.log('✓ Skipped live network Supabase user creation in placeholder test environment.');
    return;
  }
  await cleanupTemporaryUsers();

  const app = await createTestApp();
  
  // 1. Create a temporary user via Supabase Auth Admin
  const testEmail = `test_delete_${Date.now()}@shipdehop.internal`;
  const password = 'TestUser123!SecurePassword';
  const { data: createData, error: createErr } = await adminSupabase.auth.admin.createUser({
    email: testEmail,
    password: password,
    email_confirm: true,
    user_metadata: { full_name: 'Pre-Delete Test User' },
  });

  assert.equal(createErr, null, `User creation failed: ${createErr?.message}`);
  assert.ok(createData?.user?.id, 'User ID missing');
  const userId = createData.user.id;
  console.log('✓ 1. Created test user:', userId);

  // 2. Insert public.users & user_identities PII rows
  const { error: userErr } = await adminSupabase.from('users').upsert({
    id: userId,
    email: testEmail,
    full_name: 'Pre-Delete Test User',
    phone: '+15550001234',
    avatar_url: 'https://example.com/avatar.png',
    ekyc_tier: 'TIER_2',
    trust_score: 85,
    xp_points: 300,
    is_female: false,
  });
  assert.equal(userErr, null, `Public users row insertion failed: ${userErr?.message}`);

  await adminSupabase.from('user_identities').upsert({
    user_id: userId,
    identity_method: 'MANUAL_BETA',
    verified_name: 'Pre-Delete Test User',
    phone_e164: '+15550001234',
    document_last4: '1234',
    verified_birth_year: 1990,
    gender: 'MALE',
    verification_status: 'VERIFIED',
    signature_valid: true,
    liveness_status: 'PASS',
    face_match_status: 'PASS',
    consent_version: 'v1.0',
    consented_at: new Date().toISOString(),
  });
  console.log('✓ 2. Seeded user PII in users and user_identities');

  // 3. Obtain tokens
  const { data: signData } = await adminSupabase.auth.signInWithPassword({
    email: testEmail,
    password: password,
  });
  
  let supabaseAccessToken = signData?.session?.access_token;
  if (!supabaseAccessToken) {
    const { data: linkData } = await adminSupabase.auth.admin.generateLink({
      type: 'magiclink',
      email: testEmail,
    });
    supabaseAccessToken = linkData?.properties?.hashed_token || '';
  }
  assert.ok(supabaseAccessToken, 'Supabase access token required for test');

  const es256Token = JwtSessionManager.mintUserAccessJwt(userId, '+15550001234');
  const refreshSession = await JwtSessionManager.createRefreshSession(userId);
  console.log('✓ 3. Obtained Supabase token, ES256 JWT, and refresh session');

  // Verify pre-deletion authenticated access
  const preCheckRes = await app.inject({
    method: 'GET',
    url: '/profile/me',
    headers: { authorization: `Bearer ${supabaseAccessToken}` },
  });
  assert.equal(preCheckRes.statusCode, 200, 'Pre-deletion authenticated request must succeed');
  console.log('✓ 4. Pre-deletion API access verified HTTP 200');

  // 4. Execute account deletion endpoint via Fastify inject
  const delRes = await app.inject({
    method: 'POST',
    url: '/profile/delete-account',
    headers: { authorization: `Bearer ${supabaseAccessToken}` },
  });
  assert.equal(delRes.statusCode, 200, `Deletion request failed: ${delRes.body}`);
  const delBody = JSON.parse(delRes.body);
  assert.equal(delBody.success, true, 'Deletion response must indicate success: true');
  console.log('✓ 5. Executed POST /profile/delete-account route');

  // 5. Test pre-deletion Supabase access token against protected endpoint
  const postSupabaseRes = await app.inject({
    method: 'GET',
    url: '/profile/me',
    headers: { authorization: `Bearer ${supabaseAccessToken}` },
  });
  assert.equal(postSupabaseRes.statusCode, 401, 'Pre-deletion Supabase access token must return HTTP 401');
  console.log('✓ 6. Pre-deletion Supabase token rejected HTTP 401');

  // 6. Test pre-deletion ShipdeHop ES256 JWT against protected endpoint
  const postEs256Res = await app.inject({
    method: 'GET',
    url: '/profile/me',
    headers: { authorization: `Bearer ${es256Token}` },
  });
  assert.equal(postEs256Res.statusCode, 401, 'Pre-deletion ShipdeHop ES256 JWT must return HTTP 401');
  console.log('✓ 7. Pre-deletion ShipdeHop ES256 JWT rejected HTTP 401');

  // 7. Test /auth/session/refresh using pre-deletion refresh token
  const postRefreshRes = await app.inject({
    method: 'POST',
    url: '/auth/session/refresh',
    headers: { origin: 'http://localhost:3000' },
    payload: { refreshToken: refreshSession.refreshToken },
  });
  assert.equal(postRefreshRes.statusCode, 401, 'Pre-deletion refresh token must return HTTP 401');
  const postRefreshBody = JSON.parse(postRefreshRes.body);
  assert.equal(postRefreshBody.accessToken, undefined, 'No new access token must be issued');
  console.log('✓ 8. Pre-deletion refresh token rejected HTTP 401 and no new token issued');

  // 8. Verify PII purging in DB
  const { data: userRow } = await adminSupabase
    .from('users')
    .select('email, phone, avatar_url, is_female, full_name')
    .eq('id', userId)
    .maybeSingle();

  if (userRow) {
    assert.equal(userRow.email, null, 'email must be purged to null');
    assert.equal(userRow.phone, null, 'phone must be purged to null');
    assert.equal(userRow.is_female, null, 'is_female must be purged to null');
    assert.equal(userRow.full_name, 'Deleted User', 'full_name must be Deleted User');
  }

  const { data: identityRow } = await adminSupabase
    .from('user_identities')
    .select('verified_name, phone_e164, document_last4, verified_birth_year, gender')
    .eq('user_id', userId)
    .maybeSingle();

  if (identityRow) {
    assert.equal(identityRow.verified_name, 'Anonymized User', 'verified_name must be Anonymized User');
    assert.equal(identityRow.phone_e164, null, 'phone_e164 must be null');
    assert.equal(identityRow.document_last4, null, 'document_last4 must be null');
    assert.equal(identityRow.verified_birth_year, null, 'verified_birth_year must be null');
    assert.equal(identityRow.gender, null, 'gender must be null');
  }
  console.log('✓ 9. Verified public.users & user_identities PII purging in DB');

  // 10. Test Fallback Auth Deactivation Path (simulating deleteUser failure)
  console.log('--- Testing Fallback Auth Deactivation Path ---');
  const fallbackEmail = `test_delete_fallback_${Date.now()}@shipdehop.internal`;
  const { data: fbCreateData, error: fbCreateErr } = await adminSupabase.auth.admin.createUser({
    email: fallbackEmail,
    password: password,
    email_confirm: true,
    user_metadata: { full_name: 'Fallback Test User' },
  });
  assert.equal(fbCreateErr, null, `Fallback user creation failed: ${fbCreateErr?.message}`);
  const fbUserId = fbCreateData.user!.id;

  await adminSupabase.from('users').upsert({
    id: fbUserId,
    email: fallbackEmail,
    full_name: 'Fallback Test User',
    phone: '+15550009999',
    ekyc_tier: 'TIER_1',
    trust_score: 50,
  });

  const { data: fbSignData } = await adminSupabase.auth.signInWithPassword({
    email: fallbackEmail,
    password: password,
  });
  const fbSupabaseToken = fbSignData?.session?.access_token || '';
  assert.ok(fbSupabaseToken, 'Fallback user token required');
  const fbEs256Token = JwtSessionManager.mintUserAccessJwt(fbUserId, '+15550009999');

  // Stub deleteUser to simulate hard deletion failure
  const originalDeleteUser = adminSupabase.auth.admin.deleteUser.bind(adminSupabase.auth.admin);
  adminSupabase.auth.admin.deleteUser = async () => {
    return { data: { user: null }, error: new Error('Simulated Auth hard delete failure') as any };
  };

  try {
    const fbDelRes = await app.inject({
      method: 'POST',
      url: '/profile/delete-account',
      headers: { authorization: `Bearer ${fbSupabaseToken}` },
    });
    assert.equal(fbDelRes.statusCode, 200, `Fallback deletion route failed: ${fbDelRes.body}`);
    const fbDelBody = JSON.parse(fbDelRes.body);
    assert.equal(fbDelBody.success, true, 'Fallback deletion must return success: true');
    assert.equal(fbDelBody.authDeleted, false, 'authDeleted must be false when falling back');

    // Inspect Auth user record after fallback deactivation
    const { data: fbUserData } = await adminSupabase.auth.admin.getUserById(fbUserId);
    assert.ok(fbUserData?.user, 'Auth user must exist');
    assert.notEqual(fbUserData.user.email, fallbackEmail, 'Original Auth email must no longer be retained');
    assert.ok(fbUserData.user.email?.startsWith('deleted-'), 'Auth email must be anonymized to non-routable deleted address');
    assert.ok(fbUserData.user.banned_until, 'Auth user must be banned/deactivated');

    // Test token rejection after fallback
    const fbPostRes = await app.inject({
      method: 'GET',
      url: '/profile/me',
      headers: { authorization: `Bearer ${fbEs256Token}` },
    });
    assert.equal(fbPostRes.statusCode, 401, 'ES256 token must be rejected after fallback deactivation');

    console.log('✓ Fallback Auth deactivation and anonymization test passed!');
  } finally {
    adminSupabase.auth.admin.deleteUser = originalDeleteUser;
    await adminSupabase.auth.admin.deleteUser(fbUserId);
    await adminSupabase.from('users').delete().eq('id', fbUserId);
  }

  // 11. Cleanup temporary test records & close app
  await app.close();
  await cleanupTemporaryUsers();
  console.log('✓ 11. Cleaned up all temporary test records');

  console.log('--- Account Deletion & Security Real Harness Test Passed! ---');
}

runAccountDeletionTest().catch(async (err) => {
  console.error('Account Deletion Test Failed:', err);
  await cleanupTemporaryUsers();
  process.exit(1);
});

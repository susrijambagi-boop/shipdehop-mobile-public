#!/usr/bin/env node
/**
 * ShipdeHop Beta Admin CLI: Manual Identity Approval
 *
 * Usage:
 *   npx tsx src/scripts/admin_verify_identity.ts <userId> [reviewerNotes]
 *
 * Example:
 *   npx tsx src/scripts/admin_verify_identity.ts 00000000-0000-4000-a000-000000000001 "Documents and video KYC verified by operator"
 *
 * Runs exclusively on a trusted server/machine. Does not expose credentials to browsers.
 */
import { IdentityVerificationManager } from '../services/identity_verification.js';

async function main() {
  const args = process.argv.slice(2);
  if (args.length < 1) {
    console.error('Usage: npx tsx src/scripts/admin_verify_identity.ts <userId> [reviewerNotes]');
    process.exit(1);
  }

  const userId = args[0];
  const reviewerNotes = args[1] || 'Manual verification approved via trusted terminal CLI';

  if (!userId) {
    console.error('Error: userId argument is required.');
    process.exit(1);
  }

  const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
  if (!uuidRegex.test(userId)) {
    console.error(`Error: "${userId}" is not a valid canonical UUID.`);
    process.exit(1);
  }

  try {
    const maskedId = `${userId.slice(0, 8)}...`;
    console.log(`[Admin Identity CLI] Fetching identity record for user: ${maskedId}`);
    const identity = await IdentityVerificationManager.getIdentity(userId);

    if (!identity) {
      console.error(`[Admin Identity CLI] ERROR: No identity record found for user ${maskedId}.`);
      console.error('User must first initiate consent and identity submission.');
      process.exit(1);
    }

    console.log('\n--- Current Identity Verification Record ---');
    console.log(`  User:                ${userId.slice(0, 8)}...`);
    console.log(`  Current Status:      ${identity.verificationStatus}`);
    console.log(`  Identity Method:     ${identity.identityMethod}`);
    console.log(`  Consent Date:        ${identity.consentedAt.toISOString()}`);
    console.log('--------------------------------------------\n');

    if (identity.verificationStatus === 'VERIFIED') {
      console.log('[Admin Identity CLI] User is ALREADY VERIFIED.');
      process.exit(0);
    }

    if (identity.verificationStatus !== 'PENDING_REVIEW') {
      console.error(`[Admin Identity CLI] REJECTED: User status is "${identity.verificationStatus}".`);
      console.error('Only identities in "PENDING_REVIEW" state may be transitioned to "VERIFIED".');
      process.exit(1);
    }

    console.log('[Admin Identity CLI] Approving identity for user...');
    const approved = await IdentityVerificationManager.approveIdentityManually(
      userId,
      'admin-cli',
      reviewerNotes
    );

    console.log('\n[Admin Identity CLI] SUCCESS: Identity status transitioned to VERIFIED.');
    console.log(`  Verified At:         ${approved.verifiedAt?.toISOString()}`);
    console.log('  Audit log entry written to identity_verification_audit.');
    process.exit(0);
  } catch (err: any) {
    console.error(`[Admin Identity CLI] ERROR: ${err?.message || err}`);
    process.exit(1);
  }
}

if (process.argv[1]?.endsWith('admin_verify_identity.ts') || process.argv[1]?.endsWith('admin_verify_identity.js')) {
  main();
}

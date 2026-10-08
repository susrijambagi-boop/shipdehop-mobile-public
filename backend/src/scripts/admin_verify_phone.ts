#!/usr/bin/env node
/**
 * ShipdeHop Beta Admin CLI: Manual WhatsApp Verification
 *
 * Usage:
 *   npx tsx src/scripts/admin_verify_phone.ts <senderPhoneE164> <challengeCode>
 *
 * Example:
 *   npx tsx src/scripts/admin_verify_phone.ts +919876543210 A1B2C3
 *
 * Runs exclusively on a trusted server/machine. Does not expose credentials to browsers.
 */
import { getPhoneVerificationProvider, normalizePhoneNumber } from '../services/phone_verification.js';

async function main() {
  const args = process.argv.slice(2);
  if (args.length < 2) {
    console.error('Usage: npx tsx src/scripts/admin_verify_phone.ts <phoneE164> <challengeCode>');
    process.exit(1);
  }

  const rawPhone = args[0];
  const rawCode = args[1];

  if (!rawPhone || !rawCode) {
    console.error('Usage: npx tsx src/scripts/admin_verify_phone.ts <phoneE164> <challengeCode>');
    process.exit(1);
  }

  try {
    const normalizedPhone = normalizePhoneNumber(rawPhone);
    const cleanCode = rawCode.trim().toUpperCase().replace(/^VERIFY\s+SHIPDEHOP\s+/i, '');
    const challengeMessage = `VERIFY SHIPDEHOP ${cleanCode}`;

    console.log('[Admin CLI] Processing manual phone verification...');

    const provider = getPhoneVerificationProvider();
    const result = await provider.processInboundMessage(normalizedPhone, challengeMessage);

    if (result.success) {
      console.log('[Admin CLI] SUCCESS: Phone verification approved.');
      console.log('[Admin CLI] User may now proceed to exchange session in the app.');
      process.exit(0);
    } else {
      console.error(`[Admin CLI] FAILED: ${result.error || 'Verification failed.'}`);
      process.exit(1);
    }
  } catch (err: any) {
    console.error(`[Admin CLI] ERROR: ${err?.message || err}`);
    process.exit(1);
  }
}

if (process.argv[1]?.endsWith('admin_verify_phone.ts') || process.argv[1]?.endsWith('admin_verify_phone.js')) {
  main();
}

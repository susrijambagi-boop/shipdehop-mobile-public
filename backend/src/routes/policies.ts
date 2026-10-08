import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import { z } from 'zod';
import { adminSupabase } from '../lib/supabase.js';

export async function policyRoutes(app: FastifyInstance): Promise<void> {
  app.get('/policies/:jurisdictionCode', async (request: FastifyRequest, reply: FastifyReply) => {
    const { jurisdictionCode } = z.object({
      jurisdictionCode: z.string().min(2).max(20),
    }).parse(request.params);

    const codeUpper = jurisdictionCode.trim().toUpperCase();

    const { data: policy, error } = await adminSupabase
      .from('cost_sharing_policies')
      .select('jurisdiction_code, max_recovery_ratio, hard_cap_per_seat, currency, enabled, marketplace_platform_fee_bps')
      .eq('jurisdiction_code', codeUpper)
      .eq('enabled', true)
      .maybeSingle();

    if (error || !policy) {
      throw app.httpErrors.notFound(`No enabled cost-sharing policy found for jurisdiction ${codeUpper}`);
    }

    return {
      jurisdictionCode: policy.jurisdiction_code,
      maxRecoveryRatio: Number(policy.max_recovery_ratio),
      hardCapPerSeat: policy.hard_cap_per_seat ? Number(policy.hard_cap_per_seat) : null,
      currency: policy.currency,
      enabled: policy.enabled,
      marketplacePlatformFeeBps: policy.marketplace_platform_fee_bps ? Number(policy.marketplace_platform_fee_bps) : null,
    };
  });
}

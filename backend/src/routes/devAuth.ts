import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { config } from '../config.js';
import { adminSupabase } from '../lib/supabase.js';

export const DEV_ALLOWLISTED_EMAILS = new Set([
  'shipsterheadquarter@gmail.com',
  'susrijambagi@gmail.com',
]);

const devAuthSchema = z.object({
  email: z.string().email(),
});

export async function devAuthRoutes(app: FastifyInstance) {
  app.post('/dev/auth/login-as-test-user', async (request, reply) => {
    if (!config.DEV_TEST_AUTH) {
      return reply.code(403).send({
        error: 'Forbidden',
        message: 'Dev test auth disabled in production',
      });
    }

    const parsed = devAuthSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({
        error: 'Bad Request',
        message: 'Valid email required',
      });
    }

    const normalizedEmail = parsed.data.email.trim().toLowerCase();

    if (!DEV_ALLOWLISTED_EMAILS.has(normalizedEmail)) {
      return reply.code(400).send({
        error: 'Bad Request',
        message: 'Only allowlisted test accounts permit dev login',
      });
    }

    const { data: linkData, error: linkError } = await adminSupabase.auth.admin.generateLink({
      type: 'magiclink',
      email: normalizedEmail,
    });

    if (linkError || !linkData?.properties?.email_otp) {
      return reply.code(500).send({
        error: 'Internal Server Error',
        message: 'Failed to generate dev authentication link',
      });
    }

    const { data: verifyData, error: verifyError } = await adminSupabase.auth.verifyOtp({
      email: normalizedEmail,
      token: linkData.properties.email_otp,
      type: 'magiclink',
    });

    if (verifyError || !verifyData?.session) {
      return reply.code(500).send({
        error: 'Internal Server Error',
        message: 'Failed to establish dev authentication session',
      });
    }

    return reply.send({
      session: {
        access_token: verifyData.session.access_token,
        refresh_token: verifyData.session.refresh_token,
      },
      user: {
        id: verifyData.session.user.id,
        email: verifyData.session.user.email,
        role: verifyData.session.user.role,
      },
    });
  });
}

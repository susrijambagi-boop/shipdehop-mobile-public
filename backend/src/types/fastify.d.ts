import type { SupabaseClient, User } from '@supabase/supabase-js';

declare module 'fastify' {
  interface FastifyRequest {
    authUser: User;
    userSupabase: SupabaseClient;
  }
}

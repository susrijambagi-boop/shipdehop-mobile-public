import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { config } from '../config.js';

export const adminSupabase = createClient(config.SUPABASE_URL, config.SUPABASE_SECRET_KEY, {
  global: {
    headers: {
      Authorization: `Bearer ${config.SUPABASE_SECRET_KEY}`,
    },
  },
  auth: { persistSession: false, autoRefreshToken: false },
});

export function createUserSupabase(accessToken: string): SupabaseClient {
  return createClient(config.SUPABASE_URL, config.SUPABASE_PUBLISHABLE_KEY, {
    global: { headers: { Authorization: `Bearer ${accessToken}` } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

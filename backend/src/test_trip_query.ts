import 'dotenv/config';
import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL = process.env.SUPABASE_URL || 'https://vemzufbdamdzxqktzbha.supabase.co';
const SUPABASE_SECRET_KEY = process.env.SUPABASE_SECRET_KEY || '';

const adminSupabase = createClient(SUPABASE_URL, SUPABASE_SECRET_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});

async function main() {
  const notifId = '90c0e3ea-3efa-4086-812b-c05637189dd0';
  const tripId = '1b7a6df7-5f89-46de-a9ed-751ab3d48eb4';

  console.log('Querying notification:', notifId);
  const { data: notif, error: notifErr } = await adminSupabase
    .from('notifications')
    .select('*')
    .eq('id', notifId)
    .single();

  console.log('Notification Data:', notif, 'Error:', notifErr);

  console.log('Querying trip:', tripId);
  const { data: trip, error: tripErr } = await adminSupabase
    .from('trip_routes')
    .select('*')
    .eq('id', tripId)
    .single();

  console.log('Trip Data:', trip, 'Error:', tripErr);
}

main();

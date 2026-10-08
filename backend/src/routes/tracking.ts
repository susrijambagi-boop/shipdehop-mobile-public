import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { adminSupabase } from '../lib/supabase.js';

export async function trackingRoutes(app: FastifyInstance): Promise<void> {
  app.post('/trips/:tripId/tracking/snapshot', async (request) => {
    const { tripId } = z.object({ tripId: z.string().uuid() }).parse(request.params);
    const body = z.object({
      lat: z.number().min(-90).max(90),
      lon: z.number().min(-180).max(180),
      heading: z.number().min(0).max(360).nullable().optional(),
      speedMps: z.number().min(0).max(100).nullable().optional(),
      recordedAt: z.string().datetime(),
    }).parse(request.body);

    const { data: trip, error: tripError } = await request.userSupabase.from('trip_routes').select('id,driver_id,status').eq('id', tripId).single();
    if (tripError || !trip || trip.driver_id !== request.authUser.id || trip.status !== 'IN_PROGRESS') {
      throw app.httpErrors.forbidden('Only the active driver can persist tracking snapshots');
    }

    const { error } = await adminSupabase.rpc('service_upsert_trip_snapshot', {
      p_trip_id: tripId,
      p_driver_id: request.authUser.id,
      p_lon: body.lon,
      p_lat: body.lat,
      p_heading: body.heading ?? null,
      p_speed_mps: body.speedMps ?? null,
      p_recorded_at: body.recordedAt,
    });
    if (error) throw app.httpErrors.badRequest(error.message);
    return { ok: true };
  });
}

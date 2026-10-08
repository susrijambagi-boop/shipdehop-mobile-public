import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import { z } from 'zod';
import {
  createRideRequest,
  matchRideRequestsAlongRoute,
  acceptRideRequest,
} from '../services/rideRequests.js';
import { assertIndiaRoute, INDIA_ONLY_MESSAGE } from '../lib/launchMarket.js';
import { requireVerifiedIdentity } from './identity.js';
import { verifyIndiaLocation, normalizeCountryCode } from '../lib/locationValidation.js';

const point = z.object({
  lat: z.number().min(-90).max(90),
  lon: z.number().min(-180).max(180),
});

export async function rideRequestRoutes(app: FastifyInstance): Promise<void> {
  app.post('/ride-requests', async (request: FastifyRequest, reply: FastifyReply) => {
    if (!(await requireVerifiedIdentity(request, reply))) return;
    const body = z.object({
      pickupName: z.string().min(2).max(160),
      pickup: point,
      dropName: z.string().min(2).max(160),
      drop: point,
      earliestDeparture: z.string().datetime(),
      latestDeparture: z.string().datetime(),
      seatsNeeded: z.number().int().min(1).max(8),
      currency: z.string().length(3),
      jurisdictionCode: z.string().min(2).max(20),
    }).parse(request.body);

    const pickupCheck = await verifyIndiaLocation({ lat: body.pickup.lat, lon: body.pickup.lon });
    if (!pickupCheck.isValid) {
      if (pickupCheck.status === 'SERVICE_UNAVAILABLE') {
        throw app.httpErrors.serviceUnavailable(pickupCheck.errorMessage || "We couldn't verify this location. Please try again.");
      }
      throw app.httpErrors.badRequest(`Pickup location error: ${pickupCheck.errorMessage || 'Currently available in India.'}`);
    }

    const dropCheck = await verifyIndiaLocation({ lat: body.drop.lat, lon: body.drop.lon });
    if (!dropCheck.isValid) {
      if (dropCheck.status === 'SERVICE_UNAVAILABLE') {
        throw app.httpErrors.serviceUnavailable(dropCheck.errorMessage || "We couldn't verify this location. Please try again.");
      }
      throw app.httpErrors.badRequest(`Drop location error: ${dropCheck.errorMessage || 'Currently available in India.'}`);
    }

    if (body.currency.toUpperCase().trim() !== 'INR') {
      throw app.httpErrors.badRequest('Currency must be INR for India transactions');
    }

    if (normalizeCountryCode(body.jurisdictionCode) !== 'IN') {
      throw app.httpErrors.badRequest('Jurisdiction must be IN for India transactions');
    }

    const earliest = new Date(body.earliestDeparture);
    const latest = new Date(body.latestDeparture);
    if (latest < earliest) {
      throw app.httpErrors.badRequest(
        'Latest departure time must be after earliest departure time',
      );
    }

    const item = await createRideRequest({
      requesterId: request.authUser.id,
      pickupName: body.pickupName,
      pickupLat: body.pickup.lat,
      pickupLon: body.pickup.lon,
      dropName: body.dropName,
      dropLat: body.drop.lat,
      dropLon: body.drop.lon,
      earliestDeparture: body.earliestDeparture,
      latestDeparture: body.latestDeparture,
      seatsNeeded: body.seatsNeeded,
      currency: 'INR',
      jurisdictionCode: 'IN',
    }, request.userSupabase);

    return item;
  });

  app.get('/trips/:tripId/ride-request-matches', async (request: FastifyRequest, reply: FastifyReply) => {
    if (!(await requireVerifiedIdentity(request, reply))) return;
    const { tripId } = z.object({ tripId: z.string().uuid() }).parse(request.params);
    const { maxDetourMeters } = z.object({
      maxDetourMeters: z.coerce.number().int().min(100).max(50_000).default(5000),
    }).parse(request.query);

    const { data: trip, error: tripErr } = await request.userSupabase
      .from('trip_routes')
      .select('id, driver_id, status, accepts_passengers, available_seats')
      .eq('id', tripId)
      .maybeSingle();

    if (tripErr || !trip) throw app.httpErrors.notFound('Trip route not found');
    if (trip.driver_id !== request.authUser.id) {
      throw app.httpErrors.forbidden(
        'Only the driver can view matched ride requests for this route',
      );
    }

    const matches = await matchRideRequestsAlongRoute(
      tripId,
      maxDetourMeters,
      request.userSupabase,
    );

    const sanitized = (matches || [])
      .filter((m: any) => m.requester_id !== request.authUser.id)
      .map((m: any) => ({
        id: m.request_id,
        requestId: m.request_id,
        type: 'RIDE',
        requesterId: m.requester_id,
        requesterName: m.requester_name || 'Verified Passenger',
        pickupName: m.pickup_name,
        pickupLat: Number(m.pickup_lat),
        pickupLon: Number(m.pickup_lon),
        dropName: m.drop_name,
        dropLat: Number(m.drop_lat),
        dropLon: Number(m.drop_lon),
        earliestDeparture: m.earliest_departure,
        latestDeparture: m.latest_departure,
        seatsNeeded: Number(m.seats_needed),
        contributionAmount: Number(m.offered_contribution_per_seat ?? 0),
        currency: m.currency,
        jurisdictionCode: m.jurisdiction_code,
        status: m.status,
        pickupDistanceMeters: Math.round(m.pickup_distance_m || 0),
        dropDistanceMeters: Math.round(m.drop_distance_m || 0),
        matchReason: `Route corridor match (${Math.round(m.pickup_distance_m || 0)}m pickup, ${Math.round(m.drop_distance_m || 0)}m drop detour)`,
      }));

    return sanitized;
  });

  app.post(
    '/ride-requests/:id/accept',
    async (request: FastifyRequest, reply: FastifyReply) => {
      if (!(await requireVerifiedIdentity(request, reply))) return;
      const { id: requestId } = z.object({ id: z.string() }).parse(request.params);
      const { tripId } = z.object({ tripId: z.string().uuid() }).parse(request.body);

      try {
        const order = await acceptRideRequest(
          requestId,
          tripId,
          request.authUser.id,
          1000,
          request.userSupabase,
        );
        return { ok: true, order };
      } catch (e: any) {
        throw app.httpErrors.badRequest(e.message || 'Failed to accept ride request');
      }
    },
  );
}


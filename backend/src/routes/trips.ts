import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import { z } from 'zod';
import { formatTripToJourneyJson } from '../lib/tripSerialization.js';
import { computeRoadRoute } from '../services/googleRoutes.js';
import { adminSupabase } from '../lib/supabase.js';
import { assertIndiaRoute, INDIA_ONLY_MESSAGE } from '../lib/launchMarket.js';
import { requireVerifiedIdentity } from './identity.js';
import { verifyIndiaLocation, verifyRoadRouteInIndia, normalizeCountryCode } from '../lib/locationValidation.js';

const point = z.object({
  lat: z.number().min(-90).max(90),
  lon: z.number().min(-180).max(180),
});

function enforceIndiaRoute(
  app: FastifyInstance,
  origin: { lat: number; lon: number },
  destination: { lat: number; lon: number },
  currency?: string,
  jurisdictionCode?: string,
): void {
  try {
    assertIndiaRoute(origin, destination, currency, jurisdictionCode);
  } catch (_) {
    throw app.httpErrors.badRequest(INDIA_ONLY_MESSAGE);
  }
}


export async function tripRoutes(app: FastifyInstance): Promise<void> {
  app.post('/trips', async (request: FastifyRequest, reply: FastifyReply) => {
    if (!(await requireVerifiedIdentity(request, reply))) return;
    const body = z.object({
      originName: z.string().min(2).max(160),
      origin: point,
      destinationName: z.string().min(2).max(160),
      destination: point,
      departureTime: z.string().datetime(),
      seats: z.number().int().min(0).max(8),
      parcelCapacityTier: z.enum(['NONE', 'ENVELOPE', 'MEDIUM', 'LUGGAGE']),
      pricePerSeat: z.number().nonnegative(),
      estimatedTripCost: z.number().positive(),
      currency: z.string().length(3),
      jurisdictionCode: z.string().min(2).max(20),
      ladiesOnly: z.boolean().default(false),
      acceptsPassengers: z.boolean().optional(),
      acceptsParcels: z.boolean().optional(),
      acceptsShoppingRequests: z.boolean().default(false),
    }).parse(request.body);

    // Authoritative Server-side Geographic Validation (Never trust client-supplied codes)
    const originCheck = await verifyIndiaLocation({ lat: body.origin.lat, lon: body.origin.lon });
    if (!originCheck.isValid) {
      if (originCheck.status === 'SERVICE_UNAVAILABLE') {
        throw app.httpErrors.serviceUnavailable(originCheck.errorMessage || "We couldn't verify this location. Please try again.");
      }
      throw app.httpErrors.badRequest(`Origin location error: ${originCheck.errorMessage || 'Currently available in India.'}`);
    }

    const destCheck = await verifyIndiaLocation({ lat: body.destination.lat, lon: body.destination.lon });
    if (!destCheck.isValid) {
      if (destCheck.status === 'SERVICE_UNAVAILABLE') {
        throw app.httpErrors.serviceUnavailable(destCheck.errorMessage || "We couldn't verify this location. Please try again.");
      }
      throw app.httpErrors.badRequest(`Destination location error: ${destCheck.errorMessage || 'Currently available in India.'}`);
    }

    const normalizedCurrency = body.currency.toUpperCase().trim();
    if (normalizedCurrency !== 'INR') {
      throw app.httpErrors.badRequest('Currency must be INR for India transactions');
    }

    const normalizedJurisdiction = normalizeCountryCode(body.jurisdictionCode);
    if (normalizedJurisdiction !== 'IN') {
      throw app.httpErrors.badRequest('Jurisdiction must be IN for India transactions');
    }

    const roadRoute = await computeRoadRoute(body.origin, body.destination);

    // Validate road route polyline does not cross outside India
    const routeCheck = await verifyRoadRouteInIndia(roadRoute.geoJson.coordinates);
    if (!routeCheck.isValid) {
      if (routeCheck.httpStatusCode === 503) {
        throw app.httpErrors.serviceUnavailable(routeCheck.errorMessage || "We couldn't verify this route location. Please try again.");
      }
      throw app.httpErrors.badRequest(routeCheck.errorMessage || 'Road route crosses outside India coverage.');
    }
    
    let data: any = null;
    let error: any = null;

    const acceptsPass = body.acceptsPassengers ?? (body.seats > 0);
    const acceptsParcels = body.acceptsParcels ?? (body.parcelCapacityTier !== 'NONE');
    const res = await request.userSupabase.rpc('create_trip_route', {
      p_origin_name: body.originName,
      p_origin_lon: body.origin.lon,
      p_origin_lat: body.origin.lat,
      p_dest_name: body.destinationName,
      p_dest_lon: body.destination.lon,
      p_dest_lat: body.destination.lat,
      p_route_geojson: JSON.stringify(roadRoute.geoJson),
      p_departure_time: body.departureTime,
      p_seat_capacity: acceptsPass ? body.seats : 0,
      p_parcel_capacity_tier: body.parcelCapacityTier,
      p_price_per_seat: body.pricePerSeat,
      p_estimated_trip_cost: body.estimatedTripCost,
      p_currency: 'INR',
      p_jurisdiction_code: 'IN',
      p_ladies_only: body.ladiesOnly,
      p_accepts_passengers: acceptsPass,
      p_accepts_parcels: acceptsParcels,
      p_accepts_shopping_requests: body.acceptsShoppingRequests,
    });

    if (res.error) {
      throw app.httpErrors.badRequest(res.error.message || 'Failed to create trip');
    }

    return {
      trip: formatTripToJourneyJson(res.data),
      routeDistanceMeters: roadRoute.distanceMeters,
      routeDurationSeconds: roadRoute.durationSeconds,
    };
  });

  app.get('/trips/user', async (request: FastifyRequest, reply: FastifyReply) => {
    if (!(await requireVerifiedIdentity(request, reply))) return;
    const { data, error } = await request.userSupabase
      .from('trip_routes')
      .select('*')
      .eq('driver_id', request.authUser!.id)
      .order('departure_time', { ascending: true });
    if (error) throw app.httpErrors.badRequest(error.message);
    return (data || []).map(formatTripToJourneyJson);
  });

  app.get('/trips/:id', async (request: FastifyRequest, reply: FastifyReply) => {
    if (!(await requireVerifiedIdentity(request, reply))) return;
    const { id } = z.object({ id: z.string().uuid() }).parse(request.params);
    const { data, error } = await request.userSupabase
      .from('trip_routes')
      .select('*')
      .eq('id', id)
      .maybeSingle();
    if (error || !data) throw app.httpErrors.notFound('Trip route not found');
    // Custom application sessions can use a service client. Enforce the same read
    // rules explicitly as well as relying on RLS for Supabase sessions.
    const actor = request.authUser;
    let allowed = data.driver_id === actor.id || actor.app_metadata?.role === 'admin';
    if (!allowed && data.status === 'SCHEDULED') {
      if (!data.ladies_only) allowed = true;
      else {
        const profile = await adminSupabase.from('users').select('is_female,ekyc_tier').eq('id', actor.id).maybeSingle();
        allowed = !profile.error && profile.data?.is_female === true && ['TIER_2', 'TIER_3'].includes(profile.data.ekyc_tier);
      }
    }
    if (!allowed) {
      const participation = await adminSupabase.from('escrow_orders').select('id').eq('trip_id', id)
        .in('escrow_status', ['LOCKED', 'RELEASED', 'DISPUTED'])
        .or(`buyer_id.eq.${actor.id},provider_id.eq.${actor.id}`).limit(1);
      allowed = !participation.error && !!participation.data?.length;
    }
    if (!allowed) throw app.httpErrors.notFound('Trip route not found');
    return formatTripToJourneyJson(data);
  });

  app.get('/trips/search', async (request) => {
    const q = z.object({
      originLat: z.coerce.number(),
      originLon: z.coerce.number(),
      destLat: z.coerce.number(),
      destLon: z.coerce.number(),
      departAfter: z.string().datetime(),
      departBefore: z.string().datetime(),
      seats: z.coerce.number().default(1),
      maxDetourMeters: z.coerce.number().default(5000),
    }).parse(request.query);

    const originCheck = await verifyIndiaLocation({ lat: q.originLat, lon: q.originLon });
    if (!originCheck.isValid) {
      if (originCheck.status === 'SERVICE_UNAVAILABLE') {
        throw app.httpErrors.serviceUnavailable(originCheck.errorMessage || "We couldn't verify this location. Please try again.");
      }
      throw app.httpErrors.badRequest(`Search origin location error: ${originCheck.errorMessage || 'Currently available in India.'}`);
    }

    const destCheck = await verifyIndiaLocation({ lat: q.destLat, lon: q.destLon });
    if (!destCheck.isValid) {
      if (destCheck.status === 'SERVICE_UNAVAILABLE') {
        throw app.httpErrors.serviceUnavailable(destCheck.errorMessage || "We couldn't verify this location. Please try again.");
      }
      throw app.httpErrors.badRequest(`Search destination location error: ${destCheck.errorMessage || 'Currently available in India.'}`);
    }

    const { data, error } = await request.userSupabase.rpc('match_passenger_trips', {
      p_origin_lon: q.originLon, p_origin_lat: q.originLat,
      p_dest_lon: q.destLon, p_dest_lat: q.destLat,
      p_depart_after: q.departAfter, p_depart_before: q.departBefore,
      p_seats: q.seats, p_max_detour_meters: q.maxDetourMeters,
    });
    if (error) throw app.httpErrors.badRequest(error.message);
    return data;
  });

  app.get(
    '/trips/:tripId/shipment-matches',
    async (request: FastifyRequest, reply: FastifyReply) => {
      if (!(await requireVerifiedIdentity(request, reply))) return;
      const { tripId } = z.object({ tripId: z.string().uuid() }).parse(request.params);

      const { data: trip, error: tripErr } = await adminSupabase
        .from('trip_routes')
        .select('id, driver_id, status, parcel_capacity_tier, parcel_capacity_units_available')
        .eq('id', tripId)
        .maybeSingle();

      if (tripErr || !trip) throw app.httpErrors.notFound('Trip route not found');
      if (trip.driver_id !== request.authUser.id) {
        throw app.httpErrors.forbidden(
          'Only the driver can view matched shipments for this route',
        );
      }

      const { data: rawMatches, error: matchErr } = await adminSupabase.rpc(
        'match_shipments_along_route',
        {
          p_trip_id: tripId,
          p_max_detour_meters: 5000,
        },
      );

      if (matchErr) throw app.httpErrors.badRequest(matchErr.message);

      const sanitizedMatches = (rawMatches || [])
        .filter((m: any) => m.sender_id !== request.authUser.id)
        .map((m: any) => ({
          id: m.shipment_task_id,
          shipmentTaskId: m.shipment_task_id,
          type: 'SHIPMENT',
          itemType: m.item_type,
          senderId: m.sender_id,
          senderName: m.sender_name || 'Verified Sender',
          pickupName: m.pickup_name,
          pickupLat: Number(m.pickup_lat),
          pickupLon: Number(m.pickup_lon),
          dropName: m.drop_name,
          dropLat: Number(m.drop_lat),
          dropLon: Number(m.drop_lon),
          weightKg: Number(m.weight_kg),
          rewardAmount: Number(m.reward_amount),
          declaredValue: Number(m.declared_value),
          currency: m.currency,
          requiredParcelUnits: Number(m.required_parcel_units),
          pickupDistanceMeters: Math.round(m.pickup_distance_meters || 0),
          dropDistanceMeters: Math.round(m.drop_distance_meters || 0),
          matchReason: `Route corridor match (${Math.round(m.pickup_distance_meters || 0)}m pickup, ${Math.round(m.drop_distance_meters || 0)}m drop detour)`,
        }));

      return sanitizedMatches;
    },
  );
}


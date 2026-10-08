import { conversationRoutes } from './conversation.js';
import type { FastifyInstance } from 'fastify';
import { z } from 'zod';

import { adminSupabase } from '../lib/supabase.js';
import {
  assistantFollowUp,
  interpretAssistantMessage,
  type AssistantContext,
} from '../services/smartAssistant.js';
import { searchGeocodingProvider } from '../services/productionGeocoder.js';

const contextSchema = z.object({
  intent: z.string().optional(),
  originQuery: z.string().optional(),
  destinationQuery: z.string().optional(),
  travelDate: z.string().optional(),
  dateFlexible: z.boolean().optional(),
  availableWeightKg: z.number().optional(),
  passengers: z.number().optional(),
  marketplaceQuery: z.string().optional(),
  confidence: z.number().optional(),
}).passthrough();

function dateWindow(dateText: string): { after: string; before: string } | null {
  if (!dateText) return null;
  const parsed = new Date(`${dateText}T00:00:00+05:30`);
  if (Number.isNaN(parsed.getTime())) return null;
  const after = parsed.toISOString();
  const before = new Date(parsed.getTime() + 24 * 60 * 60 * 1000).toISOString();
  return { after, before };
}

async function resolveIndiaPlace(query: string) {
  if (!query.trim()) return null;
  const matches = await searchGeocodingProvider(query);
  return matches[0] ?? null;
}

export async function assistantRoutes(app: FastifyInstance): Promise<void> {
  await conversationRoutes(app);
  app.post('/assistant/match', async (request, reply) => {
    const body = z.object({
      message: z.string().trim().min(1).max(1200),
      context: contextSchema.optional(),
    }).parse(request.body);

    let interpretation;
    try {
      interpretation = await interpretAssistantMessage(
        body.message,
        body.context as AssistantContext | undefined,
      );
    } catch {
      return reply.code(503).send({
        status: 'UNAVAILABLE',
        message: 'Smart matching is temporarily unavailable. You can still use Plan a trip or the regular ParcelPool and CarPool forms.',
        context: body.context ?? {},
      });
    }

    const followUp = assistantFollowUp(interpretation);
    // Keep unknown requests out of geocoding and action selection, and make
    // this boundary explicit to TypeScript rather than asserting a known intent.
    if (interpretation.intent === 'UNKNOWN' || followUp) {
      return {
        status: 'NEEDS_INFO',
        message: followUp ?? 'What would you like to do with ShipdeHop?',
        context: interpretation,
        matches: [],
      };
    }

    const needsRoute = [
      'TRAVEL_CARRY',
      'SEND_PARCEL',
      'BUY_FOR_ME',
      'FIND_RIDE',
      'OFFER_RIDE',
    ].includes(interpretation.intent);

    let origin = null;
    let destination = null;

    if (needsRoute) {
      [origin, destination] = await Promise.all([
        resolveIndiaPlace(interpretation.originQuery),
        resolveIndiaPlace(interpretation.destinationQuery),
      ]);

      if (!origin || !destination) {
        const unresolved = !origin
          ? interpretation.originQuery
          : interpretation.destinationQuery;
        return {
          status: 'OUTSIDE_SERVICE_AREA',
          message:
            `I could not resolve “${unresolved}” as an Indian location. ShipdeHop's current release matches routes within India only.`,
          context: interpretation,
          matches: [],
        };
      }
    }

    if (interpretation.intent === 'TRAVEL_CARRY') {
      const travelDate = interpretation.travelDate
        ? new Date(`${interpretation.travelDate}T00:00:00+05:30`).toISOString()
        : null;

      const { data, error } = await adminSupabase.rpc(
        'assistant_match_open_shipments',
        {
          p_origin_lon: origin!.longitude,
          p_origin_lat: origin!.latitude,
          p_dest_lon: destination!.longitude,
          p_dest_lat: destination!.latitude,
          p_max_weight_kg: interpretation.availableWeightKg,
          p_travel_date: travelDate,
          p_max_endpoint_detour_meters: 50000,
          p_limit: 25,
        },
      );

      if (error) {
        throw app.httpErrors.internalServerError('Could not search parcel requests');
      }

      return {
        status: 'RESULTS',
        message: data?.length
          ? `I found ${data.length} compatible parcel request${data.length === 1 ? '' : 's'} for this trip.`
          : 'No compatible parcel requests are live for this route yet.',
        context: interpretation,
        resolvedRoute: { origin, destination },
        matches: (data ?? []).map((item: any) => ({
          id: item.shipment_task_id,
          type: item.item_type,
          pickupName: item.pickup_name,
          dropName: item.drop_name,
          weightKg: Number(item.weight_kg),
          rewardAmount: Number(item.reward_amount),
          currency: 'INR',
          earliestPickup: item.earliest_pickup,
          latestDelivery: item.latest_delivery,
        })),
        action: {
          type: 'OPEN_PARCELPOOL_CARRY',
          origin: origin!.displayLabel,
          destination: destination!.displayLabel,
          date: interpretation.travelDate,
        },
      };
    }

    if (interpretation.intent === 'FIND_RIDE') {
      const window = dateWindow(interpretation.travelDate);
      if (!window && !interpretation.dateFlexible) {
        return {
          status: 'NEEDS_INFO',
          message: 'What date are you travelling? You can also say your dates are flexible.',
          context: interpretation,
          matches: [],
        };
      }

      const after = window?.after ?? new Date().toISOString();
      const before = window?.before ??
        new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString();

      const { data, error } = await adminSupabase.rpc('match_passenger_trips', {
        p_origin_lon: origin!.longitude,
        p_origin_lat: origin!.latitude,
        p_dest_lon: destination!.longitude,
        p_dest_lat: destination!.latitude,
        p_depart_after: after,
        p_depart_before: before,
        p_seats: interpretation.passengers || 1,
        p_max_detour_meters: 5000,
      });

      if (error) throw app.httpErrors.internalServerError('Could not search rides');

      return {
        status: 'RESULTS',
        message: data?.length
          ? `I found ${data.length} matching ride${data.length === 1 ? '' : 's'}.`
          : 'No matching rides are live for that route yet.',
        context: interpretation,
        resolvedRoute: { origin, destination },
        matches: data ?? [],
        action: {
          type: 'OPEN_CARPOOL_FIND',
          origin: origin!.displayLabel,
          destination: destination!.displayLabel,
          date: interpretation.travelDate,
        },
      };
    }

    if (interpretation.intent === 'MARKETPLACE_SEARCH') {
      const searchTerm = interpretation.marketplaceQuery.replace(/[%_]/g, '').trim();
      const { data, error } = await adminSupabase
        .from('marketplace_items')
        .select('id,title,description,price,currency,category,condition,location_name,ship_eligible,images')
        .eq('status', 'LISTED')
        .eq('currency', 'INR')
        .eq('jurisdiction_code', 'IN')
        .or(`title.ilike.%${searchTerm}%,description.ilike.%${searchTerm}%`)
        .limit(25);

      if (error) throw app.httpErrors.internalServerError('Could not search Marketplace');

      return {
        status: 'RESULTS',
        message: data?.length
          ? `I found ${data.length} Marketplace result${data.length === 1 ? '' : 's'}.`
          : 'No Marketplace listings matched that search.',
        context: interpretation,
        matches: data ?? [],
        action: { type: 'OPEN_MARKETPLACE' },
      };
    }

    const actionType = {
      SEND_PARCEL: 'OPEN_PARCELPOOL_SEND',
      BUY_FOR_ME: 'OPEN_PARCELPOOL_BRING',
      OFFER_RIDE: 'OPEN_CARPOOL_OFFER',
    }[interpretation.intent];

    return {
      status: 'READY',
      message:
        interpretation.intent === 'SEND_PARCEL'
          ? 'I have the route. I can open Send Parcel with it prefilled.'
          : interpretation.intent === 'BUY_FOR_ME'
            ? 'I have the route. I can open Buy-for-Me with it prefilled.'
            : 'I have the route. I can open Offer a Ride with it prefilled.',
      context: interpretation,
      resolvedRoute: { origin, destination },
      matches: [],
      action: {
        type: actionType,
        origin: origin!.displayLabel,
        destination: destination!.displayLabel,
        date: interpretation.travelDate,
      },
    };
  });
}

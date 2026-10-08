import { adminSupabase } from '../lib/supabase.js';

export interface CreateRideRequestInput {
  requesterId: string;
  pickupName: string;
  pickupLat: number;
  pickupLon: number;
  dropName: string;
  dropLat: number;
  dropLon: number;
  earliestDeparture: string;
  latestDeparture: string;
  seatsNeeded: number;
  currency: string;
  jurisdictionCode: string;
  isDevSimulation?: boolean;
}

export interface RideRequestItem {
  id: string;
  requester_id: string;
  pickup_name: string;
  pickup_lat: number;
  pickup_lon: number;
  drop_name: string;
  drop_lat: number;
  drop_lon: number;
  earliest_departure: string;
  latest_departure: string;
  seats_needed: number;
  currency: string;
  jurisdiction_code: string;
  status: 'OPEN' | 'MATCHED' | 'RESERVED' | 'CANCELLED' | 'COMPLETED' | 'EXPIRED';
  matched_trip_id?: string | null;
  matched_order_id?: string | null;
  created_at: string;
  updated_at: string;
}

const devSimulationStore = new Map<string, RideRequestItem>();

export async function createRideRequest(input: CreateRideRequestInput, clientSupabase?: any): Promise<RideRequestItem> {
  const nowStr = new Date().toISOString();

  if (!input.currency || !input.jurisdictionCode) {
    throw new Error('Explicit currency and jurisdictionCode are required. Client fallbacks strictly forbidden.');
  }

  const supabase = clientSupabase || adminSupabase;

  // 1. Attempt database insertion in live mode via create_ride_request RPC or direct table insert
  try {
    const { data: rpcData, error: rpcErr } = await supabase.rpc('create_ride_request', {
      p_pickup_name: input.pickupName,
      p_pickup_lat: input.pickupLat,
      p_pickup_lon: input.pickupLon,
      p_drop_name: input.dropName,
      p_drop_lat: input.dropLat,
      p_drop_lon: input.dropLon,
      p_earliest_departure: input.earliestDeparture,
      p_latest_departure: input.latestDeparture,
      p_seats_needed: input.seatsNeeded,
      p_currency: input.currency,
      p_jurisdiction_code: input.jurisdictionCode,
      p_requester_id: input.requesterId,
    });

    if (!rpcErr && rpcData) {
      return {
        id: rpcData.id,
        requester_id: rpcData.requester_id,
        pickup_name: rpcData.pickup_name,
        pickup_lat: input.pickupLat,
        pickup_lon: input.pickupLon,
        drop_name: rpcData.drop_name,
        drop_lat: input.dropLat,
        drop_lon: input.dropLon,
        earliest_departure: rpcData.earliest_departure,
        latest_departure: rpcData.latest_departure,
        seats_needed: rpcData.seats_needed,
        currency: rpcData.currency,
        jurisdiction_code: rpcData.jurisdiction_code,
        status: rpcData.status,
        matched_trip_id: rpcData.matched_trip_id,
        matched_order_id: rpcData.matched_order_id,
        created_at: rpcData.created_at,
        updated_at: rpcData.updated_at,
      };
    }

    throw new Error(rpcErr?.message ?? 'Database did not return a persisted ride request');
  } catch (error) {
    if (!input.isDevSimulation || process.env.NODE_ENV === 'production') throw error;
  }

  const simId = `sim-req-${Date.now()}-${Math.floor(Math.random() * 1000)}`;
  const simItem: RideRequestItem = {
    id: simId,
    requester_id: input.requesterId,
    pickup_name: input.pickupName,
    pickup_lat: input.pickupLat,
    pickup_lon: input.pickupLon,
    drop_name: input.dropName,
    drop_lat: input.dropLat,
    drop_lon: input.dropLon,
    earliest_departure: input.earliestDeparture,
    latest_departure: input.latestDeparture,
    seats_needed: input.seatsNeeded,
    currency: input.currency,
    jurisdiction_code: input.jurisdictionCode,
    status: 'OPEN',
    created_at: nowStr,
    updated_at: nowStr,
  };

  devSimulationStore.set(simId, simItem);
  return simItem;
}

export async function matchRideRequestsAlongRoute(tripId: string, maxDetourMeters = 5000, clientSupabase?: any): Promise<any[]> {
  const supabase = clientSupabase || adminSupabase;

  const { data, error } = await supabase.rpc('match_ride_requests_along_route', {
    p_trip_id: tripId,
    p_max_detour_meters: maxDetourMeters,
  });

  if (error) {
    throw new Error(`Failed to match ride requests along route: ${error.message}`);
  }

  return Array.isArray(data) ? data : [];
}

export async function acceptRideRequest(requestId: string, tripId: string, driverId: string, platformFeeBps = 1000, clientSupabase?: any): Promise<any> {
  const supabase = clientSupabase || adminSupabase;

  const { data, error } = await supabase.rpc('accept_ride_request_and_reserve_order', {
    p_request_id: requestId,
    p_trip_id: tripId,
    p_platform_fee_bps: platformFeeBps,
  });

  if (error) {
    throw new Error(`Failed to accept ride request and reserve order: ${error.message}`);
  }

  return data;
}


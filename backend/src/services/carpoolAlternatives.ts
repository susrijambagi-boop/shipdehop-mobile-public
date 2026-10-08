export interface CarpoolAlternativeInput {
  actorId: string;
  originLat: number;
  originLon: number;
  destLat: number;
  destLon: number;
  travelDate: string;
  maxDetourMeters: number;
  limit: number;
}

type SupabaseLike = {
  rpc(name: string, params: Record<string, unknown>): Promise<{ data: any; error: any }>;
  from(table: string): {
    select(columns: string): {
      in(column: string, values: string[]): Promise<{ data: any; error: any }>;
    };
  };
};

export async function findCarpoolParcelAlternatives(
  db: SupabaseLike,
  input: CarpoolAlternativeInput,
): Promise<Record<string, unknown>[]> {
  const detour = Math.min(50000, Math.max(1000, Math.trunc(input.maxDetourMeters)));
  const limit = Math.min(10, Math.max(1, Math.trunc(input.limit)));
  const { data, error } = await db.rpc('assistant_match_open_shipments', {
    p_origin_lon: input.originLon,
    p_origin_lat: input.originLat,
    p_dest_lon: input.destLon,
    p_dest_lat: input.destLat,
    p_max_weight_kg: null,
    p_travel_date: input.travelDate,
    p_max_endpoint_detour_meters: detour,
    p_limit: limit,
  });
  if (error) throw new Error('parcel-alternative-rpc-failed');

  const rows = Array.isArray(data)
      ? data.filter((row) => row && typeof row === 'object')
      : [];
  const ids = rows
      .map((row: any) => row.shipment_task_id?.toString())
      .filter((id: unknown): id is string => typeof id === 'string' && id.length > 0);
  if (ids.length === 0) return [];

  const ownership =
      await db.from('shipment_tasks').select('id,sender_id').in('id', ids);
  if (ownership.error) throw new Error('parcel-alternative-ownership-check-failed');
  const ownIds = new Set(
    (Array.isArray(ownership.data) ? ownership.data : [])
        .filter((row: any) => row?.sender_id === input.actorId)
        .map((row: any) => row.id?.toString()),
  );

  return rows
      .filter((row: any) => !ownIds.has(row.shipment_task_id?.toString()))
      .slice(0, limit)
      .map((row: any) => ({
        shipment_task_id: row.shipment_task_id,
        item_type: row.item_type,
        pickup_name: row.pickup_name,
        drop_name: row.drop_name,
        weight_kg: Number(row.weight_kg),
        reward_amount: Number(row.reward_amount),
        currency: row.currency?.toString().trim() || 'INR',
        earliest_pickup: row.earliest_pickup ?? null,
        latest_delivery: row.latest_delivery ?? null,
        pickup_distance_meters:
            Math.round(Number(row.pickup_distance_meters) || 0),
        drop_distance_meters:
            Math.round(Number(row.drop_distance_meters) || 0),
      }));
}

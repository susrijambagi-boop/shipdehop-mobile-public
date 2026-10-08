import assert from 'node:assert/strict';
import { findCarpoolParcelAlternatives } from './services/carpoolAlternatives.js';

const actor = '11111111-1111-4111-8111-111111111111';
let lastRpc: Record<string, unknown> = {};
const db = {
  async rpc(name: string, params: Record<string, unknown>) {
    assert.equal(name, 'assistant_match_open_shipments');
    lastRpc = params;
    return { error: null, data: [
      { shipment_task_id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', item_type: 'PARCEL', pickup_name: 'Bengaluru', drop_name: 'Hubballi', weight_kg: 5, reward_amount: 500, currency: 'INR', pickup_distance_meters: 1200.4, drop_distance_meters: 2200.8 },
      { shipment_task_id: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', item_type: 'PARCEL', pickup_name: 'Bengaluru', drop_name: 'Hubballi', weight_kg: 2, reward_amount: 250, currency: 'INR', pickup_distance_meters: 900, drop_distance_meters: 1200 },
    ]};
  },
  from(table: string) {
    assert.equal(table, 'shipment_tasks');
    return { select(columns: string) {
      assert.equal(columns, 'id,sender_id');
      return { async in(column: string, values: string[]) {
        assert.equal(column, 'id');
        assert.equal(values.length, 2);
        return { error: null, data: [
          { id: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', sender_id: actor },
          { id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', sender_id: 'other-user' },
        ]};
      }};
    }};
  },
};

const rows = await findCarpoolParcelAlternatives(db, {
  actorId: actor,
  originLat: 12.9716,
  originLon: 77.5946,
  destLat: 15.3647,
  destLon: 75.1240,
  travelDate: '2026-10-06T00:00:00.000Z',
  maxDetourMeters: 5000,
  limit: 5,
});
assert.equal(rows.length, 1);
assert.equal(rows[0]?.shipment_task_id, 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
assert.equal(rows[0]?.pickup_distance_meters, 1200);
assert.equal(rows[0]?.drop_distance_meters, 2201);
assert.equal(lastRpc.p_travel_date, '2026-10-06T00:00:00.000Z');
assert.equal(lastRpc.p_max_endpoint_detour_meters, 5000);
assert.equal(lastRpc.p_limit, 5);
assert.equal(lastRpc.p_max_weight_kg, null);
console.log('PASS carpool alternatives route/date contract and own-request exclusion');

const failed = { ...db, async rpc() {
  return { data: null, error: { message: 'database unavailable' } };
}};
await assert.rejects(() => findCarpoolParcelAlternatives(failed, {
  actorId: actor,
  originLat: 1, originLon: 1, destLat: 2, destLon: 2,
  travelDate: '2026-10-06T00:00:00.000Z',
  maxDetourMeters: 5000, limit: 5,
}));
console.log('PASS carpool alternatives failure stays failure');

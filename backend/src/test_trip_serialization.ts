import assert from 'node:assert/strict';
import { decodePoint, formatTripToJourneyJson } from './lib/tripSerialization.js';
function ewkb(lon: number, lat: number, little: boolean): string {
  const b = Buffer.alloc(25);
  b[0] = little ? 1 : 0;
  if (little) { b.writeUInt32LE(0x20000001, 1); b.writeUInt32LE(4326, 5); b.writeDoubleLE(lon, 9); b.writeDoubleLE(lat, 17); }
  else { b.writeUInt32BE(0x20000001, 1); b.writeUInt32BE(4326, 5); b.writeDoubleBE(lon, 9); b.writeDoubleBE(lat, 17); }
  return b.toString('hex');
}
for (const little of [true, false]) {
 const result = formatTripToJourneyJson({ id: 'trip', origin_geo: ewkb(72.8777,19.076,little), dest_geo: ewkb(73.8567,18.5204,little), departure_time: '2026-10-01T03:30:00Z', available_seats: 0, seat_capacity: 2, currency: 'INR', jurisdiction_code: 'IN' });
 assert.equal(result.origin.latitude,19.076);
 assert.equal(result.destination.longitude,73.8567);
 assert.equal(result.availableSeats,0);
 assert.equal(result.timing.earliestDateTime,'2026-10-01T03:30:00.000Z');
}
assert.deepEqual(decodePoint('SRID=4326;POINT(72.8777 19.076)'),[72.8777,19.076]);
assert.deepEqual(decodePoint({type:'Point',coordinates:[72.8777,19.076]}),[72.8777,19.076]);
for (const invalid of [null, '', '0101000020', 'POINT(NaN 10)', {type:'LineString',coordinates:[1,2]}]) assert.throws(()=>decodePoint(invalid));
const historical = formatTripToJourneyJson({origin_geo:'POINT(51.531 25.2854)',dest_geo:'POINT(51.5 25.3)',departure_time:'2026-01-01Z',currency:'QAR',jurisdiction_code:'QA'});
assert.equal(historical.currency,'QAR'); assert.equal(historical.origin.countryName,'');
console.log('Trip serialization regressions passed');

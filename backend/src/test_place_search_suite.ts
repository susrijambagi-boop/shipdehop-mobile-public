import assert from 'node:assert/strict';
import { LocationSearchUnavailable, normalizePlaceText, searchIndiaPlaceProvider,
  validIndiaPlace, type PlaceFetch } from './services/indiaPlaceSearch.js';

// All names/coordinates below are controlled fixtures, not proof of map coverage.
const key = 'unit-test-key-never-live';
const city = { name: 'Hubballi', address_line1: 'Hubballi', city: 'Hubballi',
  state: 'Karnataka', country_code: 'in', lat: 15.36, lon: 75.12, result_type: 'city' };
const bus = { ...city, name: 'Old Bus Stand', address_line1: 'Old Bus Stand',
  formatted: 'Old Bus Stand, Hubballi, Karnataka, India', lat: 15.357, lon: 75.14,
  result_type: 'amenity' };
const hospital = { ...city, name: 'Railway Hospital', address_line1: 'Railway Hospital',
  formatted: 'Railway Hospital, Hubballi, India', result_type: 'amenity' };
const airport = { ...city, name: 'Hubballi Airport', address_line1: 'Hubballi Airport',
  formatted: 'Hubballi Airport, Karnataka, India', result_type: 'amenity' };
const railway = { ...city, name: 'Hubballi Railway Station', address_line1: 'Hubballi Railway Station',
  result_type: 'amenity' };
const reply = (rows: unknown[]) => new Response(JSON.stringify({ results: rows }));
const places = (rows: unknown[]) => new Response(JSON.stringify({
  type: 'FeatureCollection', features: rows.map(properties => ({ type: 'Feature', properties })),
}));
let passed = 0;
async function check(label: string, test: () => Promise<void> | void) {
  await test(); ++passed; console.log(`PASS ${label}`);
}
function stub(handler: (url: URL, number: number) => Response | Promise<Response>) {
  const urls: URL[] = [];
  const fetcher: PlaceFetch = async (input, init) => {
    const url = new URL(String(input)); urls.push(url);
    assert.equal(url.origin, 'https://api.geoapify.com');
    assert.equal(url.searchParams.get('apiKey'), key);
    assert.ok(init?.signal, 'Every request needs a timeout');
    if (url.pathname.startsWith('/v1/geocode/')) {
      assert.equal(url.searchParams.get('filter'), 'countrycode:in');
      assert.equal(url.searchParams.get('limit'), '10');
    }
    assert.ok(urls.length <= 4, 'Do not fan out unlimited provider calls');
    return handler(url, urls.length);
  };
  return { fetcher, urls };
}
await check('blank text makes zero provider requests', async () => {
  const f = stub(() => { throw Error('must not fetch'); });
  assert.deepEqual(await searchIndiaPlaceProvider('  ', key, f.fetcher), []);
  assert.equal(f.urls.length, 0);
});
await check('ordinary city autocomplete uses one bounded request', async () => {
  const f = stub(() => reply([city]));
  assert.equal((await searchIndiaPlaceProvider('Hubli', key, f.fetcher))[0]?.lat, city.lat);
  assert.equal(f.urls.length, 1);
});
await check('Hubli and Bangalore aliases and bus-stand synonyms normalize consistently', () => {
  assert.equal(normalizePlaceText('Hubli Bus Stand'), normalizePlaceText('Hubballi bus station'));
  assert.equal(normalizePlaceText('Bangalore Airport'), normalizePlaceText('Bengaluru Airport'));
  assert.notEqual(normalizePlaceText('Old Bus Stand'), normalizePlaceText('New Bus Stand'));
});
await check('a city result cannot suppress the full bus-stand search', async () => {
  const f = stub(url => url.pathname.endsWith('autocomplete') ? reply([city]) : reply([bus]));
  const found = await searchIndiaPlaceProvider('Hubli bus stand', key, f.fetcher);
  assert.equal(found[0]?.name, 'Old Bus Stand'); assert.equal(found[0]?.lat, bus.lat);
  assert.equal(f.urls.length, 2);
  assert.equal(f.urls[1]?.searchParams.get('text'), 'Hubballi bus station');
});
await check('railway hospital remains hospital intent and does not become a train station', async () => {
  const f = stub(url => url.pathname.endsWith('autocomplete') ? reply([railway]) : reply([hospital]));
  const found = await searchIndiaPlaceProvider('Railway Hospital Hubli', key, f.fetcher);
  assert.equal(found.length, 1); assert.equal(found[0]?.name, 'Railway Hospital');
});
await check('airports retain provider names, address and exact coordinates', async () => {
  const f = stub(() => reply([airport]));
  const found = await searchIndiaPlaceProvider('Hubli airport', key, f.fetcher);
  assert.equal(found.length, 1); assert.deepEqual(found[0], airport);
});
await check('bounded Places lookup supplies a bus stand absent from address geocoding', async () => {
  const f = stub(url => {
    if (url.pathname === '/v2/places') {
      assert.equal(url.searchParams.get('categories'), 'public_transport.bus');
      assert.equal(url.searchParams.get('filter'), 'circle:75.12,15.36,35000');
      assert.equal(url.searchParams.get('limit'), '20'); return places([bus]);
    }
    return reply([city]);
  });
  const found = await searchIndiaPlaceProvider('Hubli bus stand', key, f.fetcher);
  assert.deepEqual(found, [bus]); assert.equal(f.urls.length, 4);
});
await check('named hospital fallback does not return other hospitals or hospital roads', async () => {
  const other = { ...hospital, name: 'General Hospital', address_line1: 'General Hospital',
    formatted: 'General Hospital, Hubballi, India' };
  const road = { ...hospital, result_type: 'street' };
  const f = stub(url => url.pathname === '/v2/places' ? places([other, road, hospital]) : reply([city]));
  assert.deepEqual(await searchIndiaPlaceProvider('Hubli Railway Hospital', key, f.fetcher), [hospital]);
  assert.equal(f.urls[3]?.searchParams.get('categories'), 'healthcare.hospital');
});
await check('failed autocomplete still permits a healthy full search', async () => {
  const f = stub(url => url.pathname.endsWith('autocomplete') ? new Response('', { status: 503 }) : reply([city]));
  assert.deepEqual(await searchIndiaPlaceProvider('Hubli', key, f.fetcher), [city]);
});
await check('healthy empty searches stay empty, without invented fixtures', async () => {
  const f = stub(() => reply([]));
  assert.deepEqual(await searchIndiaPlaceProvider('Unmapped local landmark', key, f.fetcher), []);
});
await check('upstream outage is a sanitized retryable 503, not no-results', async () => {
  const f = stub(() => { throw new Error(`https://secret.invalid/?apiKey=${key}`); });
  await assert.rejects(searchIndiaPlaceProvider('Hubli', key, f.fetcher), (error: unknown) => {
    assert.ok(error instanceof LocationSearchUnavailable); assert.equal(error.statusCode, 503);
    assert.ok(!error.message.includes(key)); assert.ok(!error.message.includes('secret.invalid')); return true;
  });
});
await check('malformed upstream success responses are not treated as genuine empty results', async () => {
  const f = stub(() => new Response('{"unexpected":"payload"}'));
  await assert.rejects(searchIndiaPlaceProvider('Hubli', key, f.fetcher), LocationSearchUnavailable);
});
await check('non-India and malformed coordinates are excluded', async () => {
  for (const bad of [null, {}, { ...city, country_code: 'qa' }, { ...city, lat: Infinity },
      { ...city, lat: '15oops' }, { ...city, lat: '' }, { ...city, lat: null },
      { ...city, lat: 95 }, { ...city, lon: 190 }]) assert.equal(validIndiaPlace(bad), false);
  const f = stub(() => reply([{ ...city, country_code: 'qa' }, { ...city, lat: 'NaN' }, city]));
  assert.deepEqual(await searchIndiaPlaceProvider('Hubli', key, f.fetcher), [city]);
});
await check('duplicate provider responses collapse without dropping distinct same-name places', async () => {
  const other = { ...bus, lat: 15.361 };
  const f = stub(() => reply([bus, bus, other]));
  assert.equal((await searchIndiaPlaceProvider('Hubli bus stand', key, f.fetcher)).length, 2);
});
await check('missing configuration is retryable rather than a fabricated empty success', async () => {
  const f = stub(() => reply([city]));
  await assert.rejects(searchIndiaPlaceProvider('Hubli', '', f.fetcher), LocationSearchUnavailable);
  assert.equal(f.urls.length, 0);
});
await check('overlong input is rejected without charging a provider request', async () => {
  const f = stub(() => reply([]));
  await assert.rejects(searchIndiaPlaceProvider('x'.repeat(201), key, f.fetcher), { statusCode: 400 });
  assert.equal(f.urls.length, 0);
});
await check('an ambiguous city is not silently selected for point-of-interest search', async () => {
  const f = stub(url => reply(url.searchParams.get('type') === 'city' ? [city, { ...city, lat: 17 }] : [city]));
  assert.deepEqual(await searchIndiaPlaceProvider('Hubli bus stand', key, f.fetcher), []);
  assert.equal(f.urls.length, 3);
});
await check('Places outside the bounded locality or outside India are not suggested', async () => {
  const f = stub(url => url.pathname === '/v2/places' ? places([
    { ...bus, lat: 28, lon: 77 }, { ...bus, country_code: 'qa' }, bus,
  ]) : reply([city]));
  assert.deepEqual(await searchIndiaPlaceProvider('Hubli bus stand', key, f.fetcher), [bus]);
});
await check('a failed Places fallback is retryable and never labelled no-results', async () => {
  const f = stub(url => url.pathname === '/v2/places' ? new Response('', { status: 429 }) : reply([city]));
  await assert.rejects(searchIndiaPlaceProvider('Hubli bus stand', key, f.fetcher), LocationSearchUnavailable);
});
await check('station geocoding preserves qualifier old rather than suggesting new', async () => {
  const newer = { ...bus, name: 'New Bus Stand', address_line1: 'New Bus Stand',
    formatted: 'New Bus Stand, Hubballi, India' };
  const f = stub(() => reply([bus, newer]));
  assert.deepEqual(await searchIndiaPlaceProvider('Hubli old bus stand', key, f.fetcher), [bus]);
});

// Full-repository checks run in CI. The local dependency-free helper check uses
// BATCH1_HELPER_ONLY=1; this switch is deliberately absent from the CI workflow.
if (process.env.BATCH1_HELPER_ONLY !== '1') {
  process.env.NODE_ENV = 'production';
  process.env.SUPABASE_URL = 'https://example.supabase.co';
  process.env.SUPABASE_PUBLISHABLE_KEY = 'local-test-placeholder';
  process.env.SUPABASE_SECRET_KEY = 'local-test-placeholder';
  process.env.GEOAPIFY_API_KEY = key;
  process.env.GEMINI_API_KEY = 'local-test-placeholder';
  process.env.PAYMENT_PROVIDER = 'DISABLED';
  const { default: Fastify } = await import('fastify');
  const { locationRoutes } = await import('./routes/location.js');
  const { registerAuth } = await import('./lib/auth.js');
  const originalFetch = globalThis.fetch;
  const app = Fastify(); await app.register(locationRoutes); await app.ready();
  const protectedApp = Fastify(); await protectedApp.register(registerAuth);
  await protectedApp.register(locationRoutes); await protectedApp.ready();
  try {
    await check('real location HTTP handler exposes retryable 503 on provider failure', async () => {
      globalThis.fetch = stub(() => new Response('', { status: 503 })).fetcher;
      const res = await app.inject({ method: 'GET', url: '/location/search?q=Hubli' });
      assert.equal(res.statusCode, 503); assert.equal(res.json().code, 'LOCATION_SEARCH_UNAVAILABLE');
      assert.ok(!res.body.includes(key));
    });
    await check('real HTTP handler returns provider-backed landmark data', async () => {
      globalThis.fetch = stub(url => url.pathname.endsWith('autocomplete') ? reply([city]) : reply([bus])).fetcher;
      const res = await app.inject({ method: 'GET', url: '/location/search?q=Hubli%20bus%20stand' });
      assert.equal(res.statusCode, 200); assert.equal(res.json().results[0].displayLabel, 'Old Bus Stand');
      assert.equal(res.json().results[0].latitude, bus.lat);
    });
    await check('real authentication middleware still rejects missing login before provider calls', async () => {
      let calls = 0;
      globalThis.fetch = async () => { calls++; throw Error('must not fetch'); };
      const res = await protectedApp.inject({ method: 'GET', url: '/location/search?q=Hubli' });
      assert.equal(res.statusCode, 401); assert.equal(calls, 0);
    });
  } finally {
    globalThis.fetch = originalFetch;
    await app.close(); await protectedApp.close();
  }
}
console.log(`BATCH1_PLACE_SEARCH: ${passed} passed; all provider/auth responses controlled; no live requests.`);

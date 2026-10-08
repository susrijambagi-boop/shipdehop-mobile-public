import assert from 'node:assert/strict';
import { verifyIndiaLocation, verifyRoadRouteInIndia } from './lib/locationValidation.js';
import { adminSupabase } from './lib/supabase.js';
import { searchGeocodingProvider, reverseGeocodeProvider } from './services/productionGeocoder.js';
import { computeRoadRoute } from './services/googleRoutes.js';

async function runGeoapifySupabaseSuite() {
  console.log('=== STARTING GEOAPIFY & SUPABASE GEOSPATIAL TEST SUITE ===');

  const originalEnv = process.env.NODE_ENV;
  const originalGeoapifyKey = process.env.GEOAPIFY_API_KEY;
  const originalRpc = adminSupabase.rpc;
  const originalFetch = globalThis.fetch;

  try {
    // -------------------------------------------------------------------------
    // 1. Production Point Validation calls Supabase RPC
    // -------------------------------------------------------------------------
    process.env.NODE_ENV = 'production';
    let rpcCalls: Array<{ fnName: string; params: any }> = [];

    (adminSupabase as any).rpc = async (fnName: string, params: any) => {
      rpcCalls.push({ fnName, params });
      if (fnName === 'is_coord_in_india_f64') {
        if (params.p_lat === 19.076 && params.p_lon === 72.877) {
          return { data: true, error: null };
        }
        if (params.p_lat === 25.2854 && params.p_lon === 51.531) {
          return { data: false, error: null };
        }
        if (params.p_lat === 0 && params.p_lon === 0) {
          return { data: null, error: new Error('Database connection failed') };
        }
      }
      return { data: false, error: null };
    };

    rpcCalls = [];
    const validPointRes = await verifyIndiaLocation({ lat: 19.076, lon: 72.877 });
    assert.equal(rpcCalls.length, 1, 'Production point validation MUST perform 1 RPC call');
    assert.equal(rpcCalls[0]!.fnName, 'is_coord_in_india_f64');
    assert.deepEqual(rpcCalls[0]!.params, { p_lat: 19.076, p_lon: 72.877 });
    assert.equal(validPointRes.status, 'VALID_IN');
    assert.equal(validPointRes.isValid, true);
    assert.equal(validPointRes.countryCode, 'IN');
    assert.equal(validPointRes.httpStatusCode, 200);

    rpcCalls = [];
    const invalidPointRes = await verifyIndiaLocation({ lat: 25.2854, lon: 51.531 });
    assert.equal(rpcCalls.length, 1, 'Production point validation MUST perform 1 RPC call for outside points');
    assert.equal(invalidPointRes.status, 'OUTSIDE_SERVICE_AREA');
    assert.equal(invalidPointRes.isValid, false);
    assert.equal(invalidPointRes.httpStatusCode, 400);

    rpcCalls = [];
    const rpcErrorRes = await verifyIndiaLocation({ lat: 0, lon: 0 });
    assert.equal(rpcCalls.length, 1);
    assert.equal(rpcErrorRes.status, 'SERVICE_UNAVAILABLE');
    assert.equal(rpcErrorRes.isValid, false);
    assert.equal(rpcErrorRes.httpStatusCode, 503);

    console.log('✅ 1. Production point validation correctly delegates to Supabase RPC (is_coord_in_india).');

    // -------------------------------------------------------------------------
    // 2. Production Route Validation calls Supabase Route RPC
    // -------------------------------------------------------------------------
    rpcCalls = [];
    (adminSupabase as any).rpc = async (fnName: string, params: any) => {
      rpcCalls.push({ fnName, params });
      if (fnName === 'is_route_geojson_in_india') {
        const coords = params.p_route_geojson?.coordinates;
        if (Array.isArray(coords) && coords[0][0] === 77.5946) {
          return { data: true, error: null };
        }
        if (Array.isArray(coords) && coords[0][0] === 51.531) {
          return { data: false, error: null };
        }
        if (Array.isArray(coords) && coords[0][0] === 0) {
          return { data: null, error: new Error('RPC timeout') };
        }
      }
      return { data: false, error: null };
    };

    const validRouteCoords: [number, number][] = [[77.5946, 12.9716], [76.6394, 12.2958]];
    const routeValidRes = await verifyRoadRouteInIndia(validRouteCoords);
    assert.equal(rpcCalls.length, 1, 'Production route validation MUST perform 1 RPC call');
    assert.equal(rpcCalls[0]!.fnName, 'is_route_geojson_in_india');
    assert.deepEqual(rpcCalls[0]!.params, {
      p_route_geojson: { type: 'LineString', coordinates: validRouteCoords },
    });
    assert.equal(routeValidRes.isValid, true);
    assert.equal(routeValidRes.httpStatusCode, 200);

    rpcCalls = [];
    const invalidRouteCoords: [number, number][] = [[51.531, 25.2854], [51.6034, 25.1717]];
    const routeInvalidRes = await verifyRoadRouteInIndia(invalidRouteCoords);
    assert.equal(rpcCalls.length, 1);
    assert.equal(routeInvalidRes.isValid, false);
    assert.equal(routeInvalidRes.httpStatusCode, 400);

    rpcCalls = [];
    const errorRouteCoords: [number, number][] = [[0, 0], [1, 1]];
    const routeErrorRes = await verifyRoadRouteInIndia(errorRouteCoords);
    assert.equal(rpcCalls.length, 1);
    assert.equal(routeErrorRes.isValid, false);
    assert.equal(routeErrorRes.httpStatusCode, 503);

    console.log('✅ 2. Production route validation correctly delegates to Supabase RPC (is_route_geojson_in_india).');

    // -------------------------------------------------------------------------
    // 3. Non-Production Local Validation Still Works
    // -------------------------------------------------------------------------
    process.env.NODE_ENV = 'development';

    const localMumbaiRes = await verifyIndiaLocation({ lat: 19.076, lon: 72.877 });
    assert.equal(localMumbaiRes.isValid, true);
    assert.equal(localMumbaiRes.countryCode, 'IN');

    const localDohaRes = await verifyIndiaLocation({ lat: 25.2854, lon: 51.531 });
    assert.equal(localDohaRes.isValid, false);

    const localRouteRes = await verifyRoadRouteInIndia(validRouteCoords);
    assert.equal(localRouteRes.isValid, true);

    console.log('✅ 3. Non-production local polygon validation works properly in development.');

    // -------------------------------------------------------------------------
    // 4. Geoapify Forward Geocoding Maps India Address Correctly
    // -------------------------------------------------------------------------
    process.env.NODE_ENV = 'production';
    process.env.GEOAPIFY_API_KEY = 'test-geoapify-key';

    globalThis.fetch = (async (url: string | URL) => {
      const urlStr = String(url);
      if (urlStr.includes('/v1/geocode/search')) {
        assert.ok(urlStr.includes('filter=countrycode%3Ain') || urlStr.includes('filter=countrycode:in'), 'Filter must be countrycode:in');
        assert.ok(urlStr.includes('format=json'), 'Format must be json');
        assert.ok(urlStr.includes('limit=10'), 'Limit must be 10');
        assert.ok(urlStr.includes('apiKey=test-geoapify-key'), 'Must pass Geoapify API key');

        return new Response(
          JSON.stringify({
            results: [
              {
                address_line1: 'Majestic Bus Station',
                formatted: 'Majestic Bus Station, Bengaluru, Karnataka 560009, India',
                lat: 12.9778,
                lon: 77.5723,
                country_code: 'in',
                country: 'India',
                state: 'Karnataka',
                city: 'Bengaluru',
                postcode: '560009',
              },
            ],
          }),
          { status: 200 }
        );
      }
      return new Response('Not found', { status: 404 });
    }) as any;

    const searchResults = await searchGeocodingProvider('Majestic');
    assert.equal(searchResults.length, 1);
    const searchItem = searchResults[0]!;
    assert.equal(searchItem.displayLabel, 'Majestic Bus Station');
    assert.equal(searchItem.formattedAddress, 'Majestic Bus Station, Bengaluru, Karnataka 560009, India');
    assert.equal(searchItem.latitude, 12.9778);
    assert.equal(searchItem.longitude, 77.5723);
    assert.equal(searchItem.countryCode, 'IN');
    assert.equal(searchItem.countryName, 'India');
    assert.equal(searchItem.state, 'Karnataka');
    assert.equal(searchItem.locality, 'Bengaluru');
    assert.equal(searchItem.postalCode, '560009');
    assert.equal(searchItem.provenance, 'geoapify');

    console.log('✅ 4. Geoapify forward geocoding maps India address correctly to GeocodingResult.');

    // -------------------------------------------------------------------------
    // 5. Non-IN Geocoding Results Are Rejected
    // -------------------------------------------------------------------------
    globalThis.fetch = (async (url: string | URL) => {
      const urlStr = String(url);
      if (urlStr.includes('/v1/geocode/search')) {
        return new Response(
          JSON.stringify({
            results: [
              {
                name: 'Doha Corniche',
                formatted: 'Corniche, Doha, Qatar',
                lat: 25.2854,
                lon: 51.531,
                country_code: 'qa',
                country: 'Qatar',
                state: 'Doha',
                city: 'Doha',
              },
            ],
          }),
          { status: 200 }
        );
      }
      return new Response('Not found', { status: 404 });
    }) as any;

    const nonInResults = await searchGeocodingProvider('Doha');
    assert.equal(nonInResults.length, 0, 'Non-IN geocoding results MUST be rejected');

    console.log('✅ 5. Non-IN geocoding results are rejected.');

    // -------------------------------------------------------------------------
    // 6. Reverse Geocoding Maps PIN/State/Locality Correctly
    // -------------------------------------------------------------------------
    globalThis.fetch = (async (url: string | URL) => {
      const urlStr = String(url);
      if (urlStr.includes('/v1/geocode/reverse')) {
        assert.ok(urlStr.includes('lat=12.9778'), 'Lat must be included');
        assert.ok(urlStr.includes('lon=77.5723'), 'Lon must be included');
        assert.ok(urlStr.includes('format=json'), 'Format must be json');
        assert.ok(urlStr.includes('limit=1'), 'Limit must be 1');

        return new Response(
          JSON.stringify({
            results: [
              {
                name: 'Kempegowda Bus Station',
                formatted: 'Subhash Nagar, Sevashrama, Bengaluru, Karnataka 560009, India',
                lat: 12.9778,
                lon: 77.5723,
                country_code: 'in',
                country: 'India',
                state: 'Karnataka',
                city: 'Bengaluru',
                postcode: '560009',
              },
            ],
          }),
          { status: 200 }
        );
      }
      return new Response('Not found', { status: 404 });
    }) as any;

    const reverseItem = await reverseGeocodeProvider(12.9778, 77.5723, { skipValidation: true });
    assert.ok(reverseItem);
    assert.equal(reverseItem.displayLabel, 'Kempegowda Bus Station');
    assert.equal(reverseItem.state, 'Karnataka');
    assert.equal(reverseItem.locality, 'Bengaluru');
    assert.equal(reverseItem.postalCode, '560009');
    assert.equal(reverseItem.countryCode, 'IN');
    assert.equal(reverseItem.provenance, 'geoapify');

    console.log('✅ 6. Reverse geocoding maps PIN, state, locality, and display label correctly.');

    // -------------------------------------------------------------------------
    // 7. Geoapify MultiLineString Route is Flattened Correctly
    // -------------------------------------------------------------------------
    globalThis.fetch = (async (url: string | URL) => {
      const urlStr = String(url);
      if (urlStr.includes('/v1/routing')) {
        assert.ok(urlStr.includes('waypoints=12.9716,77.5946|12.99,77.61'), 'Waypoints format correct');
        assert.ok(urlStr.includes('mode=drive'), 'Mode must be drive');
        assert.ok(urlStr.includes('format=geojson'), 'Format must be geojson');
        assert.ok(!urlStr.includes('details'), 'Must not request details or unnecessary extras');

        return new Response(
          JSON.stringify({
            type: 'FeatureCollection',
            features: [
              {
                type: 'Feature',
                properties: {
                  distance: 15200,
                  time: 1200,
                },
                geometry: {
                  type: 'MultiLineString',
                  coordinates: [
                    [
                      [77.5946, 12.9716],
                      [77.6000, 12.9800],
                    ],
                    [
                      [77.6000, 12.9800], // Duplicate shared endpoint with leg 1!
                      [77.6100, 12.9900],
                    ],
                  ],
                },
              },
            ],
          }),
          { status: 200 }
        );
      }
      return new Response('Not found', { status: 404 });
    }) as any;

    const roadRoute = await computeRoadRoute(
      { lat: 12.9716, lon: 77.5946 },
      { lat: 12.99, lon: 77.61 }
    );

    assert.equal(roadRoute.geoJson.type, 'LineString');
    assert.deepEqual(roadRoute.geoJson.coordinates, [
      [77.5946, 12.9716],
      [77.6000, 12.9800],
      [77.6100, 12.9900],
    ], 'Shared endpoint [77.6000, 12.9800] must be deduplicated across legs');

    // -------------------------------------------------------------------------
    // 8. Route Distance / Time Retain Existing Contract
    // -------------------------------------------------------------------------
    assert.equal(roadRoute.distanceMeters, 15200);
    assert.equal(roadRoute.durationSeconds, 1200);

    console.log('✅ 7 & 8. MultiLineString route flattening deduplicates shared endpoints and retains contract.');

    console.log('\n🎉 ALL GEOAPIFY & SUPABASE GEOSPATIAL TESTS PASSED CLEANLY!');
  } finally {
    process.env.NODE_ENV = originalEnv;
    process.env.GEOAPIFY_API_KEY = originalGeoapifyKey;
    adminSupabase.rpc = originalRpc;
    globalThis.fetch = originalFetch;
  }
}

runGeoapifySupabaseSuite().catch((err) => {
  console.error('❌ GEOAPIFY TEST SUITE FAILED:', err);
  process.exit(1);
});

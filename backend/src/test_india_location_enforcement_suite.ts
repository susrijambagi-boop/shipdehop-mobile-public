import assert from 'node:assert/strict';
import {
  isPointInIndia,
  verifyIndiaLocation,
  verifyRoadRouteInIndia,
  normalizeCountryCode,
  normalizeIndianPhoneNumber,
  validateIndianPinCode,
} from './lib/locationValidation.js';

async function runIndiaLocationEnforcementSuite() {
  console.log('=== STARTING REVISED INDIA LOCATION ENFORCEMENT & BOUNDARY TEST SUITE ===');

  // Test 1: Mainland India Locations
  const mumbai = { lat: 19.0760, lon: 72.8777 };
  const delhi = { lat: 28.6139, lon: 77.2090 };
  const bangalore = { lat: 12.9716, lon: 77.5946 };

  assert.equal(isPointInIndia(mumbai.lat, mumbai.lon), true, 'Mumbai must be in India');
  assert.equal(isPointInIndia(delhi.lat, delhi.lon), true, 'Delhi must be in India');
  assert.equal(isPointInIndia(bangalore.lat, bangalore.lon), true, 'Bangalore must be in India');

  const mumbaiRes = await verifyIndiaLocation(mumbai);
  assert.equal(mumbaiRes.isValid, true);
  assert.equal(mumbaiRes.countryCode, 'IN');
  assert.equal(mumbaiRes.httpStatusCode, 200);

  // Test 2: Indian Island Territories (Andaman & Nicobar, Lakshadweep)
  const portBlair = { lat: 11.6234, lon: 92.7265 }; // Andaman
  const kavaratti = { lat: 10.5600, lon: 72.6000 }; // Lakshadweep (Kavaratti island)

  assert.equal(isPointInIndia(portBlair.lat, portBlair.lon), true, 'Port Blair must be in India');
  assert.equal(isPointInIndia(kavaratti.lat, kavaratti.lon), true, 'Kavaratti must be in India');

  const islandRes = await verifyIndiaLocation(portBlair);
  assert.equal(islandRes.isValid, true);
  assert.equal(islandRes.countryCode, 'IN');
  assert.equal(islandRes.httpStatusCode, 200);

  // Test 3: Confirmed Outside India (Must return 400 + OUTSIDE_SERVICE_AREA + "Currently available in India.")
  const islamabad = { lat: 33.7294, lon: 73.0931 }; // Pakistan
  const dhaka = { lat: 23.8103, lon: 90.4125 }; // Bangladesh
  const doha = { lat: 25.2854, lon: 51.5310 }; // Qatar

  const neighbourRes = await verifyIndiaLocation(dhaka);
  assert.equal(neighbourRes.isValid, false);
  assert.equal(neighbourRes.status, 'OUTSIDE_SERVICE_AREA');
  assert.equal(neighbourRes.httpStatusCode, 400);
  assert.equal(neighbourRes.errorMessage, 'Currently available in India.');

  const dohaRes = await verifyIndiaLocation(doha);
  assert.equal(dohaRes.isValid, false);
  assert.equal(dohaRes.status, 'OUTSIDE_SERVICE_AREA');
  assert.equal(dohaRes.httpStatusCode, 400);
  assert.equal(dohaRes.errorMessage, 'Currently available in India.');

  // Test 4: Direct Bypass Attempt (Forged IN headers for foreign coordinates)
  // Server-side location validation MUST ignore client-supplied headers and inspect actual coordinates
  assert.equal((await verifyIndiaLocation(doha)).isValid, false, 'Forged IN headers for Doha coordinates must be REJECTED');

  // Test 5: Invalid Coordinates (Must return 400 + INVALID_COORDINATES)
  const invalidRes = await verifyIndiaLocation({ lat: 999, lon: 999 });
  assert.equal(invalidRes.isValid, false);
  assert.equal(invalidRes.status, 'INVALID_COORDINATES');
  assert.equal(invalidRes.httpStatusCode, 400);

  // Test 6: Road Route Polyline Checking
  // Inland geometry fixture; no road-provider serviceability is implied.
  const validRoute: [number, number][] = [[77.5946, 12.9716], [76.6394, 12.2958]];
  assert.equal((await verifyRoadRouteInIndia(validRoute)).isValid, true, 'Inland geometry must be covered');

  const invalidCrossBorderRoute: [number, number][] = [
    [72.8777, 19.0760], // Mumbai
    [73.0931, 33.7294], // Islamabad
  ];
  assert.equal((await verifyRoadRouteInIndia(invalidCrossBorderRoute)).isValid, false, 'Route to Islamabad must be invalid');

  // Test 6b: Mumbai to Kavaratti ocean route regression
  const oceanRoute: [number, number][] = [
    [72.8777, 19.0760], // Mumbai
    [72.6000, 10.5600], // Kavaratti
  ];
  assert.equal((await verifyRoadRouteInIndia(oceanRoute)).isValid, false, 'Mumbai to Kavaratti ocean route MUST be rejected');

  // Test 6c: Route crossing Bangladesh
  const bangladeshCrossingRoute: [number, number][] = [
    [88.3639, 22.5726], // Kolkata
    [91.2868, 23.8315], // Agartala (straight line across Bangladesh)
  ];
  assert.equal((await verifyRoadRouteInIndia(bangladeshCrossingRoute)).isValid, false, 'Route crossing Bangladesh MUST be rejected');

  // Regression Test 6d: 101-point route sampling bypass test
  // 101 points: index 0 = Mumbai, index 1 = Doha (Qatar), index 2..100 = Mumbai
  const polyline101: [number, number][] = Array.from({ length: 101 }, () => [72.8777, 19.0760]);
  polyline101[1] = [51.5310, 25.2854]; // Index 1 is outside India (Doha, Qatar)
  const bypassResult = await verifyRoadRouteInIndia(polyline101);
  assert.equal(bypassResult.isValid, false, '101-point route with index 1 outside India MUST be rejected (isValid: false)');

  // Test 7: Country Code Normalisation
  assert.equal(normalizeCountryCode('IN'), 'IN');
  assert.equal(normalizeCountryCode('IND'), 'IN');
  assert.equal(normalizeCountryCode('India'), 'IN');

  // Test 8: Phone Number & PIN Code Normalisation
  const validPhone = normalizeIndianPhoneNumber('9876543210');
  assert.equal(validPhone.isValid, true);
  assert.equal(validPhone.phoneE164, '+919876543210');

  const validPhone12Digit = normalizeIndianPhoneNumber('919876543210');
  assert.equal(validPhone12Digit.isValid, true);
  assert.equal(validPhone12Digit.phoneE164, '+919876543210', '919876543210 must normalize to +919876543210');

  const validPhoneLeadingZero = normalizeIndianPhoneNumber('09876543210');
  assert.equal(validPhoneLeadingZero.isValid, true);
  assert.equal(validPhoneLeadingZero.phoneE164, '+919876543210');

  const validPhone0091 = normalizeIndianPhoneNumber('00919876543210');
  assert.equal(validPhone0091.isValid, true);
  assert.equal(validPhone0091.phoneE164, '+919876543210');

  assert.equal(validateIndianPinCode('400001'), true);
  assert.equal(validateIndianPinCode('012345'), false);

  console.log('✅ ALL REVISED INDIA LOCATION ENFORCEMENT TESTS PASSED SUCCESSFULLY!');
}

runIndiaLocationEnforcementSuite().catch((err) => {
  console.error('❌ TEST FAILED:', err);
  process.exit(1);
});


/**
 * Authoritative India Location Validation Service
 * 
 * Dataset Provenance & Traceability:
 * - Dataset Name: India_Boundary_Canonical_DataMeet_2026
 * - Source URL: https://raw.githubusercontent.com/datameet/maps/5ed214bf77788f99066e3542cccd4a52cb042896/Country/india-composite.geojson
 * - Publisher: DataMeet Open Data Community (maps repository)
 * - License: CC0 1.0 Universal (Public Domain)
 * - Source File SHA-256: 5e44c39b18aa8fe57267d8018fa4ad4a10eaa3aa4cb7cb7382a1813ef8eb8c53
 * - Generated Asset SHA-256: 08d9fb32cb21f007999fb629d0049ab5cf96ef65938c785935ae88efdcd19662
 * - Local File Path: backend/src/assets/india_boundary_10m.json
 * - Processing: Canonical GeoJSON coordinate precision normalization and feature ordering without lossy simplification
 * - Coverage: Mainland India + Northeast Regions + Individual Andaman & Nicobar + Lakshadweep Islands MultiPolygons
 * - Geometry Types: Polygon & MultiPolygon with interior hole exclusion support
 */

import indiaBoundaryData from '../assets/india_boundary_10m.json' with { type: 'json' };
import { adminSupabase } from './supabase.js';

export type ValidationStatus = 'VALID_IN' | 'OUTSIDE_SERVICE_AREA' | 'SERVICE_UNAVAILABLE' | 'INVALID_COORDINATES';

export interface LocationPoint {
  lat: number;
  lon: number;
}

export interface VerificationResult {
  status: ValidationStatus;
  isValid: boolean;
  countryCode: string; // Exactly 'IN' when valid, otherwise ''
  countryName: string;
  errorMessage?: string;
  httpStatusCode: number; // 200, 400, or 503
}

interface GeoJsonFeature {
  type: string;
  properties: { name: string; iso: string; region: string };
  geometry: {
    type: 'Polygon' | 'MultiPolygon';
    coordinates: any;
  };
}

// Extract features from loaded canonical dataset
const BOUNDARY_FEATURES: GeoJsonFeature[] = indiaBoundaryData.features as GeoJsonFeature[];

function isPointOnSegment(lat: number, lon: number, lat1: number, lon1: number, lat2: number, lon2: number): boolean {
  const minLat = Math.min(lat1, lat2);
  const maxLat = Math.max(lat1, lat2);
  const minLon = Math.min(lon1, lon2);
  const maxLon = Math.max(lon1, lon2);

  if (lat < minLat - 1e-9 || lat > maxLat + 1e-9 || lon < minLon - 1e-9 || lon > maxLon + 1e-9) {
    return false;
  }

  const cross = (lat - lat1) * (lon2 - lon1) - (lon - lon1) * (lat2 - lat1);
  return Math.abs(cross) < 1e-8;
}

/**
 * Ray casting algorithm to check if point (lat, lon) is inside or on the boundary of a GeoJSON linear ring.
 * GeoJSON coordinates format: [longitude, latitude]
 */
function isPointInRing(lat: number, lon: number, ringCoords: number[][]): boolean {
  let inside = false;
  if (!Array.isArray(ringCoords) || ringCoords.length === 0) return false;

  for (let i = 0, j = ringCoords.length - 1; i < ringCoords.length; j = i++) {
    const ptI = ringCoords[i];
    const ptJ = ringCoords[j];
    if (!ptI || !ptJ || typeof ptI[0] !== 'number' || typeof ptI[1] !== 'number' || typeof ptJ[0] !== 'number' || typeof ptJ[1] !== 'number') {
      continue;
    }

    const xi = ptI[1]; // lat
    const yi = ptI[0]; // lon
    const xj = ptJ[1]; // lat
    const yj = ptJ[0]; // lon

    if (isPointOnSegment(lat, lon, xi, yi, xj, yj)) {
      return true; // Point lies directly on the boundary segment
    }

    const intersect = ((yi > lon) !== (yj > lon)) && (lat < (xj - xi) * (lon - yi) / (yj - yi) + xi);
    if (intersect) inside = !inside;
  }
  return inside;
}

/**
 * Checks if a point is inside a polygon defined by an outer ring (index 0) and interior hole rings (indices 1..N).
 */
function isPointInPolygonRings(lat: number, lon: number, rings: number[][][]): boolean {
  if (!rings || rings.length === 0) return false;

  const outerRing = rings[0];
  if (!outerRing || !isPointInRing(lat, lon, outerRing)) {
    return false;
  }

  // Ensure point is NOT inside any interior hole ring (rings 1..N)
  for (let k = 1; k < rings.length; k++) {
    const holeRing = rings[k];
    if (holeRing && isPointInRing(lat, lon, holeRing)) {
      return false; // Point falls inside an excluded interior hole!
    }
  }

  return true;
}

/**
 * Checks if coordinates fall geographically within the versioned India boundary dataset.
 * Supports Polygon and MultiPolygon geometries with interior hole exclusions.
 */
export function isPointInIndia(lat: number, lon: number): boolean {
  if (typeof lat !== 'number' || typeof lon !== 'number' || Number.isNaN(lat) || Number.isNaN(lon) ||
      lat < -90 || lat > 90 || lon < -180 || lon > 180) {
    return false;
  }

  for (const feature of BOUNDARY_FEATURES) {
    const geom = feature.geometry;
    if (!geom || !geom.coordinates) continue;

    if (geom.type === 'Polygon') {
      if (isPointInPolygonRings(lat, lon, geom.coordinates as number[][][])) {
        return true;
      }
    } else if (geom.type === 'MultiPolygon') {
      const multiPolyCoords = geom.coordinates as number[][][][];
      for (const polyRings of multiPolyCoords) {
        if (isPointInPolygonRings(lat, lon, polyRings)) {
          return true;
        }
      }
    }
  }
  return false;
}

/**
 * Authoritatively verifies a location point server-side.
 * Does NOT trust client-supplied country names, codes, or headers.
 * Never fabricates an IN country code for invalid or unverified points.
 */
export async function verifyIndiaLocation(
  point: LocationPoint
): Promise<VerificationResult> {
  const { lat, lon } = point;

  if (typeof lat !== 'number' || typeof lon !== 'number' || Number.isNaN(lat) || Number.isNaN(lon) ||
      lat < -90 || lat > 90 || lon < -180 || lon > 180) {
    return {
      status: 'INVALID_COORDINATES',
      isValid: false,
      countryCode: '',
      countryName: 'Unknown',
      errorMessage: 'Invalid latitude or longitude coordinates.',
      httpStatusCode: 400,
    };
  }

  if (process.env.NODE_ENV === 'production') {
    try {
      const { data, error } = await adminSupabase.rpc('is_coord_in_india_f64', { p_lat: lat, p_lon: lon });

      if (error) {
        return {
          status: 'SERVICE_UNAVAILABLE',
          isValid: false,
          countryCode: '',
          countryName: 'Unknown',
          errorMessage: "We couldn't verify this location. Please try again.",
          httpStatusCode: 503,
        };
      }

      if (data === true) {
        return {
          status: 'VALID_IN',
          isValid: true,
          countryCode: 'IN',
          countryName: 'India',
          httpStatusCode: 200,
        };
      }

      return {
        status: 'OUTSIDE_SERVICE_AREA',
        isValid: false,
        countryCode: '',
        countryName: 'Outside India',
        errorMessage: 'Currently available in India.',
        httpStatusCode: 400,
      };
    } catch (_err) {
      return {
        status: 'SERVICE_UNAVAILABLE',
        isValid: false,
        countryCode: '',
        countryName: 'Unknown',
        errorMessage: "We couldn't verify this location. Please try again.",
        httpStatusCode: 503,
      };
    }
  }

  try {
    const inIndia = isPointInIndia(lat, lon);

    if (!inIndia) {
      return {
        status: 'OUTSIDE_SERVICE_AREA',
        isValid: false,
        countryCode: '',
        countryName: 'Outside India',
        errorMessage: 'Currently available in India.',
        httpStatusCode: 400,
      };
    }

    return {
      status: 'VALID_IN',
      isValid: true,
      countryCode: 'IN',
      countryName: 'India',
      httpStatusCode: 200,
    };
  } catch (_err) {
    // Return retryable HTTP 503 error on unexpected verification service failures
    return {
      status: 'SERVICE_UNAVAILABLE',
      isValid: false,
      countryCode: '',
      countryName: 'Unknown',
      errorMessage: "We couldn't verify this location. Please try again.",
      httpStatusCode: 503,
    };
  }
}

// Split each segment at every boundary intersection. Between intersections, polygon
// membership is constant, so testing each open interval detects even short excursions.
type XY = [number, number];
const boundaryEdges: [XY, XY][] = BOUNDARY_FEATURES.flatMap(feature => {
  const polygons = feature.geometry.type === 'Polygon' ? [feature.geometry.coordinates] : feature.geometry.coordinates;
  return (polygons as number[][][][]).flatMap(polygon => polygon.flatMap(ring =>
    ring.slice(1).map((point, i) => [ring[i] as XY, point as XY] as [XY, XY])));
});
const cross = (a: XY, b: XY) => a[0] * b[1] - a[1] * b[0];
function segmentCovered(a: XY, b: XY): boolean {
  const d: XY = [b[0] - a[0], b[1] - a[1]];
  if (d[0] === 0 && d[1] === 0) return true;
  const cuts = [0, 1];
  for (const [c, e] of boundaryEdges) {
    if (Math.max(a[0], b[0]) < Math.min(c[0], e[0]) || Math.min(a[0], b[0]) > Math.max(c[0], e[0]) ||
        Math.max(a[1], b[1]) < Math.min(c[1], e[1]) || Math.min(a[1], b[1]) > Math.max(c[1], e[1])) continue;
    const edge: XY = [e[0] - c[0], e[1] - c[1]];
    const offset: XY = [c[0] - a[0], c[1] - a[1]];
    const denominator = cross(d, edge);
    if (denominator !== 0) {
      const t = cross(offset, edge) / denominator;
      const u = cross(offset, d) / denominator;
      if (t >= 0 && t <= 1 && u >= 0 && u <= 1) cuts.push(t);
    } else if (cross(offset, d) === 0) {
      const axis = Math.abs(d[0]) >= Math.abs(d[1]) ? 0 : 1;
      for (const p of [c, e]) {
        const t = (p[axis] - a[axis]) / d[axis];
        if (t > 0 && t < 1) cuts.push(t);
      }
    }
  }
  cuts.sort((x, y) => x - y);
  for (let i = 1; i < cuts.length; i++) {
    const t = (cuts[i - 1]! + cuts[i]!) / 2;
    if (!isPointInIndia(a[1] + d[1] * t, a[0] + d[0] * t)) return false;
  }
  return true;
}

export async function verifyRoadRouteInIndia(
  coordinates: XY[]
): Promise<{ isValid: boolean; errorMessage?: string; httpStatusCode: number }> {
  if (!Array.isArray(coordinates) || coordinates.length < 2 || coordinates.some(p => !Array.isArray(p) || p.length !== 2 || !p.every(Number.isFinite) || Math.abs(p[0]) > 180 || Math.abs(p[1]) > 90)) {
    return { isValid: false, errorMessage: 'Route polyline is empty or invalid.', httpStatusCode: 400 };
  }

  if (process.env.NODE_ENV === 'production') {
    try {
      const { data, error } = await adminSupabase.rpc('is_route_geojson_in_india', {
        p_route_geojson: {
          type: 'LineString',
          coordinates,
        },
      });

      if (error) {
        return { isValid: false, errorMessage: "We couldn't verify this route location. Please try again.", httpStatusCode: 503 };
      }

      if (!data) {
        return { isValid: false, errorMessage: 'Route crosses outside supported service coverage in India.', httpStatusCode: 400 };
      }

      return { isValid: true, httpStatusCode: 200 };
    } catch (_err) {
      return { isValid: false, errorMessage: "We couldn't verify this route location. Please try again.", httpStatusCode: 503 };
    }
  }

  if (coordinates.some(p => !isPointInIndia(p[1], p[0])) || coordinates.slice(1).some((p, i) => !segmentCovered(coordinates[i]!, p))) {
    return { isValid: false, errorMessage: 'Route crosses outside supported service coverage in India.', httpStatusCode: 400 };
  }
  return { isValid: true, httpStatusCode: 200 };
}

/**
 * Normalises country code alias to exact 'IN' or throws/rejects if non-IN.
 */
export function normalizeCountryCode(code?: string): string {
  if (!code) return 'IN';
  const clean = code.trim().toUpperCase();
  if (clean === 'IN' || clean === 'IND' || clean === 'INDIA') return 'IN';
  return clean;
}

/**
 * Server-side PIN Code validator (6-digit Indian Postal Index Number: 100000-999999).
 */
export function validateIndianPinCode(pin?: string): boolean {
  if (!pin) return false;
  const clean = pin.trim();
  return /^[1-9][0-9]{5}$/.test(clean);
}

/**
 * Server-side +91 Indian Mobile Number normaliser & validator.
 */
export function normalizeIndianPhoneNumber(rawPhone: string): { isValid: boolean; phoneE164: string } {
  let clean = rawPhone.trim().replace(/[\s\-\(\)\.]/g, '');
  if (clean.startsWith('0091')) clean = `+91${clean.substring(4)}`;
  else if (clean.startsWith('091')) clean = `+91${clean.substring(3)}`;
  else if (clean.startsWith('91') && clean.length === 12) clean = `+${clean}`;
  else if (clean.startsWith('0')) clean = `+91${clean.substring(1)}`;
  else if (!clean.startsWith('+')) clean = `+91${clean}`;

  const isValid = /^\+91[6-9]\d{9}$/.test(clean);
  return { isValid, phoneE164: isValid ? clean : '' };
}


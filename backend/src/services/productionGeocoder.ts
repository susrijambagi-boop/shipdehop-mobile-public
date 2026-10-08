import { verifyIndiaLocation, validateIndianPinCode } from '../lib/locationValidation.js';
import { config } from '../config.js';
import { getGeoapifyCache, setGeoapifyCache } from './geoapifyCache.js';
import { LocationSearchUnavailable, searchIndiaPlaceProvider } from './indiaPlaceSearch.js';

export interface GeocodingResult {
  displayLabel: string;
  formattedAddress: string;
  latitude: number;
  longitude: number;
  countryCode: string;
  countryName: string;
  state: string;
  locality: string;
  postalCode?: string;
  provenance: string;
}

const CURATED_INDIA_LANDMARKS: GeocodingResult[] = [
  { displayLabel: 'Bengaluru Majestic', formattedAddress: 'Majestic Bus Station, Bengaluru, Karnataka 560009, India', latitude: 12.9778, longitude: 77.5723, countryCode: 'IN', countryName: 'India', state: 'Karnataka', locality: 'Bengaluru', postalCode: '560009', provenance: 'curated_landmark' },
  { displayLabel: 'Bengaluru Airport (BLR)', formattedAddress: 'Kempegowda International Airport, Bengaluru, Karnataka 560300, India', latitude: 13.1986, longitude: 77.7066, countryCode: 'IN', countryName: 'India', state: 'Karnataka', locality: 'Bengaluru', postalCode: '560300', provenance: 'curated_landmark' },
  { displayLabel: 'Mysuru Junction', formattedAddress: 'Mysuru Junction Railway Station, Mysuru, Karnataka 570001, India', latitude: 12.3168, longitude: 76.6497, countryCode: 'IN', countryName: 'India', state: 'Karnataka', locality: 'Mysuru', postalCode: '570001', provenance: 'curated_landmark' },
  { displayLabel: 'Mumbai CSMT', formattedAddress: 'Chhatrapati Shivaji Maharaj Terminus, Mumbai, Maharashtra 400001, India', latitude: 18.9400, longitude: 72.8353, countryCode: 'IN', countryName: 'India', state: 'Maharashtra', locality: 'Mumbai', postalCode: '400001', provenance: 'curated_landmark' },
  { displayLabel: 'Pune Junction', formattedAddress: 'Pune Junction Railway Station, Pune, Maharashtra 411001, India', latitude: 18.5289, longitude: 73.8744, countryCode: 'IN', countryName: 'India', state: 'Maharashtra', locality: 'Pune', postalCode: '411001', provenance: 'curated_landmark' },
  { displayLabel: 'Delhi Connaught Place', formattedAddress: 'Connaught Place, New Delhi, Delhi 110001, India', latitude: 28.6315, longitude: 77.2167, countryCode: 'IN', countryName: 'India', state: 'Delhi', locality: 'New Delhi', postalCode: '110001', provenance: 'curated_landmark' },
  { displayLabel: 'Hyderabad Hitec City', formattedAddress: 'HITEC City, Hyderabad, Telangana 500081, India', latitude: 17.4435, longitude: 78.3772, countryCode: 'IN', countryName: 'India', state: 'Telangana', locality: 'Hyderabad', postalCode: '500081', provenance: 'curated_landmark' },
  { displayLabel: 'Chennai Central', formattedAddress: 'Chennai Central Railway Station, Chennai, Tamil Nadu 600003, India', latitude: 13.0827, longitude: 80.2707, countryCode: 'IN', countryName: 'India', state: 'Tamil Nadu', locality: 'Chennai', postalCode: '600003', provenance: 'curated_landmark' },
];

export function getGeoapifyApiKey(): string | undefined {
  return process.env.GEOAPIFY_API_KEY || config.GEOAPIFY_API_KEY;
}

export async function searchGeocodingProvider(query: string): Promise<GeocodingResult[]> {
  const queryTrimmed = query.trim();
  if (!queryTrimmed) return [];

  // Version the cache so earlier city-only answers do not hide landmark fixes.
  const cacheKey = `https://cache.shipdehop.internal/geoapify/autocomplete-v2?q=${encodeURIComponent(queryTrimmed.toLowerCase())}`;
  const cached = await getGeoapifyCache<GeocodingResult[]>(cacheKey);
  if (cached) return cached;

  const apiKey = getGeoapifyApiKey();
  const isProduction = process.env.NODE_ENV === 'production';

  if (apiKey && apiKey !== 'mock-key-for-tests') {
    const parsed = parseGeoapifyResults(await searchIndiaPlaceProvider(queryTrimmed, apiKey));
    if (parsed.length > 0) await setGeoapifyCache(cacheKey, parsed, 86400);
    return parsed;
  }

  if (isProduction) {
    const fallback = await searchNominatimIndia(queryTrimmed);
    if (fallback.length > 0) {
      await setGeoapifyCache(cacheKey, fallback, 86400);
      return fallback;
    }
    throw new LocationSearchUnavailable();
  }

  // Curated landmark matching for offline/dev/test execution only.
  const queryLower = queryTrimmed.toLowerCase();
  return CURATED_INDIA_LANDMARKS.filter(
    (l) =>
      l.displayLabel.toLowerCase().includes(queryLower) ||
      l.formattedAddress.toLowerCase().includes(queryLower) ||
      l.locality.toLowerCase().includes(queryLower)
  );
}

export async function reverseGeocodeProvider(
  lat: number,
  lon: number,
  options?: { skipValidation?: boolean }
): Promise<GeocodingResult | null> {
  if (!options?.skipValidation) {
    const check = await verifyIndiaLocation({ lat, lon });
    if (!check.isValid) return null;
  }

  const latRounded = lat.toFixed(4);
  const lonRounded = lon.toFixed(4);
  const cacheKey = `https://cache.shipdehop.internal/geoapify/reverse?lat=${latRounded}&lon=${lonRounded}`;
  const cached = await getGeoapifyCache<GeocodingResult>(cacheKey);
  if (cached) return cached;

  const apiKey = getGeoapifyApiKey();
  const isProduction = process.env.NODE_ENV === 'production';

  if (apiKey && apiKey !== 'mock-key-for-tests') {
    try {
      const url = `https://api.geoapify.com/v1/geocode/reverse?lat=${lat}&lon=${lon}&format=json&limit=1&apiKey=${apiKey}`;
      const res = await fetch(url);
      if (res.ok) {
        const data = (await res.json()) as any;
        if (Array.isArray(data.results) && data.results.length > 0) {
          const parsed = parseGeoapifyResults(data.results);
          if (parsed.length > 0 && parsed[0]) {
            await setGeoapifyCache(cacheKey, parsed[0], 604800); // Cache 7 days
            return parsed[0];
          }
        }
      }
    } catch (_) {
      if (isProduction) return null;
    }
  }

  if (isProduction) {
    const fallback = await reverseNominatimIndia(lat, lon);
    if (fallback) {
      await setGeoapifyCache(cacheKey, fallback, 604800);
      return fallback;
    }
    return null;
  }

  const match = CURATED_INDIA_LANDMARKS.find(
    (l) => Math.abs(l.latitude - lat) < 0.05 && Math.abs(l.longitude - lon) < 0.05
  );

  if (match) return match;

  return {
    displayLabel: `Location (${lat.toFixed(4)}, ${lon.toFixed(4)})`,
    formattedAddress: `Location at (${lat.toFixed(4)}, ${lon.toFixed(4)}), India`,
    latitude: lat,
    longitude: lon,
    countryCode: 'IN',
    countryName: 'India',
    state: 'India',
    locality: 'India',
    provenance: 'backend-production-geocoder',
  };
}

function parseGeoapifyResults(results: any[]): GeocodingResult[] {
  const parsed: GeocodingResult[] = [];

  for (const item of results) {
    const countryCodeRaw = item.country_code ? String(item.country_code).trim().toUpperCase() : '';
    if (countryCodeRaw !== 'IN') {
      continue; // Reject all non-India results
    }

    const latitude = typeof item.lat === 'number' ? item.lat : Number.parseFloat(item.lat);
    const longitude = typeof item.lon === 'number' ? item.lon : Number.parseFloat(item.lon);

    if (Number.isNaN(latitude) || Number.isNaN(longitude)) {
      continue;
    }

    const formattedAddress = item.formatted || `${latitude}, ${longitude}, India`;
    const displayLabel = item.address_line1 || item.name || formattedAddress.split(',')[0] || 'Location';
    const state = item.state || 'India';
    const locality = item.city || item.county || item.state || 'India';

    let postalCode: string | undefined;
    if (item.postcode && validateIndianPinCode(String(item.postcode))) {
      postalCode = String(item.postcode).trim();
    }

    const resultItem: GeocodingResult = {
      displayLabel,
      formattedAddress,
      latitude,
      longitude,
      countryCode: 'IN',
      countryName: item.country || 'India',
      state,
      locality,
      provenance: 'geoapify',
    };

    if (postalCode) {
      resultItem.postalCode = postalCode;
    }

    parsed.push(resultItem);
  }

  return parsed;
}


async function searchNominatimIndia(query: string): Promise<GeocodingResult[]> {
  try {
    const params = new URLSearchParams({
      q: query,
      format: 'jsonv2',
      addressdetails: '1',
      countrycodes: 'in',
      limit: '8',
    });
    const res = await fetch(`https://nominatim.openstreetmap.org/search?${params.toString()}`, {
      headers: {
        'User-Agent': 'ShipdeHop/1.0 (+https://shipdehop.com)',
        'Accept-Language': 'en-IN,en;q=0.9',
      },
    });
    if (!res.ok) return [];
    const data = await res.json() as any[];
    if (!Array.isArray(data)) return [];
    return data.map(parseNominatimResult).filter((v): v is GeocodingResult => v !== null);
  } catch (_) {
    return [];
  }
}

async function reverseNominatimIndia(lat: number, lon: number): Promise<GeocodingResult | null> {
  try {
    const params = new URLSearchParams({
      lat: String(lat),
      lon: String(lon),
      format: 'jsonv2',
      addressdetails: '1',
      zoom: '18',
    });
    const res = await fetch(`https://nominatim.openstreetmap.org/reverse?${params.toString()}`, {
      headers: {
        'User-Agent': 'ShipdeHop/1.0 (+https://shipdehop.com)',
        'Accept-Language': 'en-IN,en;q=0.9',
      },
    });
    if (!res.ok) return null;
    return parseNominatimResult(await res.json());
  } catch (_) {
    return null;
  }
}

function parseNominatimResult(item: any): GeocodingResult | null {
  const address = item?.address ?? {};
  const countryCode = String(address.country_code ?? '').toUpperCase();
  if (countryCode !== 'IN') return null;

  const latitude = Number.parseFloat(String(item?.lat ?? ''));
  const longitude = Number.parseFloat(String(item?.lon ?? ''));
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) return null;

  const formattedAddress = String(item?.display_name ?? '').trim() ||
    `${latitude}, ${longitude}, India`;
  const locality = String(
    address.city ?? address.town ?? address.village ?? address.municipality ??
    address.county ?? address.state ?? 'India'
  ).trim();
  const state = String(address.state ?? 'India').trim();
  const displayLabel = String(
    item?.name ?? address.road ?? address.suburb ?? address.neighbourhood ??
    address.city ?? address.town ?? address.village ?? formattedAddress.split(',')[0] ?? 'Location'
  ).trim();

  const result: GeocodingResult = {
    displayLabel,
    formattedAddress,
    latitude,
    longitude,
    countryCode: 'IN',
    countryName: String(address.country ?? 'India'),
    state,
    locality,
    provenance: 'nominatim',
  };

  if (address.postcode && validateIndianPinCode(String(address.postcode))) {
    result.postalCode = String(address.postcode).trim();
  }
  return result;
}

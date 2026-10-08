/** Provider-backed suggestions only. No invented landmarks or coordinates.
 * Geoapify references: /docs/geocoding/address-autocomplete/ and /docs/places/.
 * Ordinary searches use at most two requests. Landmark searches use at most
 * four, within one seven-second budget; only the Places fallback uses a city.
 */
export type ProviderPlace = Record<string, unknown>;
export type PlaceFetch = typeof globalThis.fetch;

export class LocationSearchUnavailable extends Error {
  readonly statusCode = 503;
  readonly code = 'LOCATION_SEARCH_UNAVAILABLE';
  constructor() {
    super('Place search is temporarily unavailable. Please retry.');
    this.name = 'LocationSearchUnavailable';
  }
}

const COARSE_TYPES = new Set(['country', 'state', 'county', 'city', 'district', 'postcode', 'suburb', 'street']);
const IGNORE = new Set(['in', 'at', 'near', 'the', 'of']);
const RULES = [
  // Hospital precedes transport: "Railway Hospital" is not a train station.
  { pattern: /\bhospitals?\b/i, area: /\b(?:railway\s+)?hospitals?\b/gi, category: 'healthcare.hospital' },
  { pattern: /\bbus\s+(?:stand|station|terminal)s?\b/i, area: /\bbus\s+(?:stand|station|terminal)s?\b/gi, category: 'public_transport.bus' },
  { pattern: /\bbus\s+stops?\b/i, area: /\bbus\s+stops?\b/gi, category: 'public_transport.bus' },
  { pattern: /\b(?:railway|train)\s+(?:station|junction)s?\b/i, area: /\b(?:railway|train)\s+(?:station|junction)s?\b/gi, category: 'public_transport.train' },
  { pattern: /\bairports?\b/i, area: /\bairports?\b/gi, category: 'airport' },
] as const;

export function normalizePlaceText(text: string): string {
  return text.toLowerCase().normalize('NFKC')
    .replace(/\bhubli\b/g, 'hubballi')
    .replace(/\bbangalore\b/g, 'bengaluru')
    .replace(/\bbus\s+(?:stand|station|terminal)s?\b/g, 'busstation')
    .replace(/\b(?:railway|train)\s+(?:station|junction)s?\b/g, 'trainstation')
    .replace(/\bhospitals\b/g, 'hospital')
    .replace(/\bairports\b/g, 'airport')
    .replace(/[^\p{L}\p{N}]+/gu, ' ').trim().replace(/\s+/g, ' ');
}

function text(value: unknown): string { return typeof value === 'string' ? value : ''; }
function numeric(value: unknown): number {
  if (typeof value === 'number') return value;
  return typeof value === 'string' && value.trim() !== '' ? Number(value) : NaN;
}

export function validIndiaPlace(place: unknown): place is ProviderPlace {
  if (!place || typeof place !== 'object' || Array.isArray(place)) return false;
  const row = place as ProviderPlace;
  const lat = numeric(row.lat); const lon = numeric(row.lon);
  return text(row.country_code).trim().toUpperCase() === 'IN' &&
    Number.isFinite(lat) && Number.isFinite(lon) &&
    lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180;
}

function words(value: string): string[] {
  return normalizePlaceText(value).split(' ').filter(w => w.length > 0 && !IGNORE.has(w));
}
function placeText(place: ProviderPlace): string {
  return [place.name, place.address_line1, place.formatted, place.city, place.state]
    .map(text).join(' ');
}
function matchesLandmark(place: ProviderPlace, query: string): boolean {
  if (COARSE_TYPES.has(text(place.result_type))) return false;
  const haystack = words(placeText(place));
  return words(query).every(word => haystack.includes(word));
}
function unique(places: ProviderPlace[]): ProviderPlace[] {
  const seen = new Set<string>();
  return places.filter(validIndiaPlace).filter(place => {
    // Coordinate/name key also collapses the same place across two endpoints
    // whose internal IDs differ. Distinct locations with the same name remain.
    const name = text(place.name) || text(place.address_line1) || text(place.formatted);
    const key = `${normalizePlaceText(name)}:${numeric(place.lat).toFixed(5)}:${numeric(place.lon).toFixed(5)}`;
    if (seen.has(key)) return false;
    seen.add(key); return true;
  });
}
function distanceMeters(a: ProviderPlace, b: ProviderPlace): number {
  const rad = Math.PI / 180;
  const lat1 = numeric(a.lat) * rad; const lat2 = numeric(b.lat) * rad;
  const dLat = lat2 - lat1; const dLon = (numeric(b.lon) - numeric(a.lon)) * rad;
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLon / 2) ** 2;
  return 12742000 * Math.asin(Math.min(1, Math.sqrt(h)));
}

type Reply = { ok: boolean; places: ProviderPlace[] };

export async function searchIndiaPlaceProvider(
  query: string, apiKey: string, fetcher: PlaceFetch = globalThis.fetch,
): Promise<ProviderPlace[]> {
  const clean = query.trim().replace(/\s+/g, ' ');
  if (!clean) return [];
  if (clean.length > 200) {
    throw Object.assign(new Error('Use a place search of 200 characters or fewer.'), { statusCode: 400 });
  }
  if (!apiKey.trim()) throw new LocationSearchUnavailable();
  const deadline = Date.now() + 7000;
  let calls = 0;

  async function request(path: string, params: Record<string, string>): Promise<Reply> {
    if (++calls > 4 || Date.now() >= deadline) return { ok: false, places: [] };
    const url = new URL(path, 'https://api.geoapify.com');
    for (const [key, value] of Object.entries(params)) url.searchParams.set(key, value);
    url.searchParams.set('apiKey', apiKey);
    try {
      const response = await fetcher(url.toString(), {
        signal: AbortSignal.timeout(Math.max(1, Math.min(3000, deadline - Date.now()))),
        headers: { Accept: 'application/json' },
      });
      if (!response.ok) return { ok: false, places: [] };
      const data: unknown = await response.json();
      if (!data || typeof data !== 'object') return { ok: false, places: [] };
      const payload = data as Record<string, unknown>;
      let rows: unknown[];
      if (path === '/v2/places') {
        if (!Array.isArray(payload.features)) return { ok: false, places: [] };
        rows = payload.features.map(feature => {
          if (!feature || typeof feature !== 'object') return null;
          return (feature as Record<string, unknown>).properties;
        });
      } else {
        if (!Array.isArray(payload.results)) return { ok: false, places: [] };
        rows = payload.results;
      }
      return { ok: true, places: rows.filter(validIndiaPlace) };
    } catch {
      // Never surface provider URLs, API keys, or raw upstream errors.
      return { ok: false, places: [] };
    }
  }

  const geocode = (endpoint: string, searchText: string, type?: string) => request(
    `/v1/geocode/${endpoint}`, {
      text: searchText, filter: 'countrycode:in', format: 'json', limit: '10',
      ...(type ? { type } : {}),
    });
  const expanded = clean.replace(/\bhubli\b/gi, 'Hubballi')
    .replace(/\bbangalore\b/gi, 'Bengaluru').replace(/\bbus\s+stand\b/gi, 'bus station');
  const rule = RULES.find(candidate => candidate.pattern.test(clean));

  if (!rule) {
    const auto = await geocode('autocomplete', clean);
    if (auto.places.length) return unique(auto.places).slice(0, 10);
    const full = await geocode('search', expanded);
    if (!auto.ok && !full.ok) throw new LocationSearchUnavailable();
    return unique(full.places).slice(0, 10);
  }

  // A city-only autocomplete must not suppress the full landmark lookup.
  const [auto, full] = await Promise.all([
    geocode('autocomplete', clean), geocode('search', expanded),
  ]);
  const direct = unique([...full.places, ...auto.places]
    .filter(place => matchesLandmark(place, clean)));
  if (direct.length) return direct.slice(0, 10);
  if (!auto.ok && !full.ok) throw new LocationSearchUnavailable();

  const queryWords = words(clean);
  const mentionedCities = [...full.places, ...auto.places].map(place => text(place.city))
    .filter(city => words(city).length > 0 && words(city).every(word => queryWords.includes(word)));
  const cityHint = mentionedCities[0] || expanded.replace(rule.area, ' ')
    .replace(/\b(old|new|central|main|in|at|near|the)\b/gi, ' ').trim().replace(/\s+/g, ' ');
  if (!cityHint || words(cityHint).length === 0) return [];
  const cityReply = await geocode('search', cityHint, 'city');
  if (!cityReply.ok) throw new LocationSearchUnavailable();
  const anchors = unique(cityReply.places).filter(place => {
    if (text(place.result_type) !== 'city') return false;
    const city = text(place.city) || text(place.name) || text(place.address_line1);
    const cityWords = words(city);
    return cityWords.length > 0 && cityWords.every(word => queryWords.includes(word));
  });
  // Do not silently choose between multiple cities or invent a search centre.
  if (anchors.length !== 1) return [];
  const anchor = anchors[0]!;
  const radius = 35000;
  const nearby = await request('/v2/places', {
    categories: rule.category,
    filter: `circle:${numeric(anchor.lon)},${numeric(anchor.lat)},${radius}`,
    bias: `proximity:${numeric(anchor.lon)},${numeric(anchor.lat)}`,
    limit: '20', lang: 'en',
  });
  if (!nearby.ok) throw new LocationSearchUnavailable();
  return unique(nearby.places
    .filter(place => distanceMeters(anchor, place) <= radius)
    .filter(place => matchesLandmark(place, clean))).slice(0, 10);
}

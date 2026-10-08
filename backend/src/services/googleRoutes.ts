import { config } from '../config.js';
import { getGeoapifyCache, setGeoapifyCache } from './geoapifyCache.js';

type LatLon = { lat: number; lon: number };

export type ComputedRoadRoute = {
  geoJson: { type: 'LineString'; coordinates: [number, number][] };
  distanceMeters: number;
  durationSeconds: number;
};

export async function computeRoadRoute(origin: LatLon, destination: LatLon): Promise<ComputedRoadRoute> {
  const cacheKey = `https://cache.shipdehop.internal/geoapify/route?o=${origin.lat.toFixed(4)},${origin.lon.toFixed(4)}&d=${destination.lat.toFixed(4)},${destination.lon.toFixed(4)}`;
  const cached = await getGeoapifyCache<ComputedRoadRoute>(cacheKey);
  if (cached) return cached;

  const apiKey = process.env.GEOAPIFY_API_KEY || config.GEOAPIFY_API_KEY;

  if (!apiKey || apiKey === 'mock-key-for-tests') {
    // Development/Test fallback
    const coordinates: [number, number][] = [
      [origin.lon, origin.lat],
      [destination.lon, destination.lat],
    ];
    return {
      geoJson: { type: 'LineString', coordinates },
      distanceMeters: 50000,
      durationSeconds: 3600,
    };
  }

  const url = `https://api.geoapify.com/v1/routing?waypoints=${origin.lat},${origin.lon}|${destination.lat},${destination.lon}&mode=drive&format=geojson&apiKey=${apiKey}`;
  const response = await fetch(url, { signal: AbortSignal.timeout(15000) });
  if (!response.ok) {
    throw new Error('Road route provider is unavailable. Please try again.');
  }

  const payload = (await response.json()) as any;
  const feature = payload.features?.[0];
  if (!feature || !feature.properties || !feature.geometry) {
    throw new Error('Geoapify Routing returned no usable route');
  }

  const distanceMeters = Number(feature.properties.distance);
  const durationSeconds = Number(feature.properties.time);
  const geom = feature.geometry;

  if (!Number.isFinite(distanceMeters) || distanceMeters <= 0 || !Number.isFinite(durationSeconds) || durationSeconds <= 0) {
    throw new Error('Road route provider returned incomplete data');
  }

  const coordinates: [number, number][] = [];

  if (geom.type === 'MultiLineString' && Array.isArray(geom.coordinates)) {
    for (const leg of geom.coordinates) {
      if (!Array.isArray(leg)) continue;
      for (const pt of leg) {
        if (!Array.isArray(pt) || pt.length < 2 || typeof pt[0] !== 'number' || typeof pt[1] !== 'number') continue;
        const lon = pt[0];
        const lat = pt[1];
        if (coordinates.length > 0) {
          const lastPt = coordinates[coordinates.length - 1]!;
          if (lastPt[0] === lon && lastPt[1] === lat) {
            // Remove duplicate shared endpoint between consecutive legs
            continue;
          }
        }
        coordinates.push([lon, lat]);
      }
    }
  } else if (geom.type === 'LineString' && Array.isArray(geom.coordinates)) {
    for (const pt of geom.coordinates) {
      if (!Array.isArray(pt) || pt.length < 2 || typeof pt[0] !== 'number' || typeof pt[1] !== 'number') continue;
      coordinates.push([pt[0], pt[1]]);
    }
  } else {
    throw new Error('Geoapify Routing returned unrecognized geometry type');
  }

  if (coordinates.length < 2) {
    throw new Error('Road route provider returned insufficient coordinate points');
  }

  const routeResult: ComputedRoadRoute = {
    geoJson: {
      type: 'LineString',
      coordinates,
    },
    distanceMeters,
    durationSeconds,
  };

  await setGeoapifyCache(cacheKey, routeResult, 86400); // Cache 24h

  return routeResult;
}

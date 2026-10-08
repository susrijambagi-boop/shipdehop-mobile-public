import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import { z } from 'zod';
import { verifyIndiaLocation, verifyRoadRouteInIndia } from '../lib/locationValidation.js';
import { computeRoadRoute } from '../services/googleRoutes.js';
import { searchGeocodingProvider, reverseGeocodeProvider } from '../services/productionGeocoder.js';

const pointSchema = z.object({
  lat: z.number().min(-90).max(90),
  lon: z.number().min(-180).max(180),
});

export async function locationRoutes(app: FastifyInstance): Promise<void> {
  // Search places in India using production geocoding service
  app.get('/location/search', async (request: FastifyRequest, reply: FastifyReply) => {
    const { q } = z.object({ q: z.string().optional().default('') }).parse(request.query);
    const cleanQuery = q.trim();

    if (!cleanQuery) {
      return { results: [] };
    }

    const results = await searchGeocodingProvider(cleanQuery);
    return { results: results || [] };
  });

  // Reverse geocode lat/lon
  app.get('/location/reverse', async (request: FastifyRequest, reply: FastifyReply) => {
    const { lat, lon } = z.object({
      lat: z.coerce.number().min(-90).max(90),
      lon: z.coerce.number().min(-180).max(180),
    }).parse(request.query);

    const [check, result] = await Promise.all([
      verifyIndiaLocation({ lat, lon }),
      reverseGeocodeProvider(lat, lon, { skipValidation: true }),
    ]);

    if (!check.isValid) {
      if (check.status === 'SERVICE_UNAVAILABLE') {
        throw app.httpErrors.serviceUnavailable(check.errorMessage || "We couldn't verify this location. Please try again.");
      }
      throw app.httpErrors.badRequest(check.errorMessage || 'Location is outside India');
    }

    if (!result || (result.countryCode !== 'IN' && result.countryName !== 'India')) {
      throw app.httpErrors.badRequest('Location reverse lookup failed or is outside India');
    }

    return result;
  });

  // Authoritative road route computation using backend road routing
  app.post('/routes/compute', async (request: FastifyRequest) => {
    const body = z.object({
      origin: pointSchema,
      destination: pointSchema,
    }).parse(request.body);

    const [originCheck, destCheck, roadRoute] = await Promise.all([
      verifyIndiaLocation({ lat: body.origin.lat, lon: body.origin.lon }),
      verifyIndiaLocation({ lat: body.destination.lat, lon: body.destination.lon }),
      computeRoadRoute(body.origin, body.destination),
    ]);

    if (!originCheck.isValid) {
      if (originCheck.status === 'SERVICE_UNAVAILABLE') {
        throw app.httpErrors.serviceUnavailable(originCheck.errorMessage || "We couldn't verify this location. Please try again.");
      }
      throw app.httpErrors.badRequest(`Origin location error: ${originCheck.errorMessage || 'Currently available in India.'}`);
    }

    if (!destCheck.isValid) {
      if (destCheck.status === 'SERVICE_UNAVAILABLE') {
        throw app.httpErrors.serviceUnavailable(destCheck.errorMessage || "We couldn't verify this location. Please try again.");
      }
      throw app.httpErrors.badRequest(`Destination location error: ${destCheck.errorMessage || 'Currently available in India.'}`);
    }

    if (!roadRoute) {
      throw app.httpErrors.badRequest('Route computation failed');
    }

    const routeCheck = await verifyRoadRouteInIndia(roadRoute.geoJson.coordinates);
    if (!routeCheck.isValid) {
      if (routeCheck.httpStatusCode === 503) {
        throw app.httpErrors.serviceUnavailable(routeCheck.errorMessage || "We couldn't verify this route location. Please try again.");
      }
      throw app.httpErrors.badRequest(routeCheck.errorMessage || 'Road route crosses outside India coverage.');
    }

    return roadRoute;
  });
}

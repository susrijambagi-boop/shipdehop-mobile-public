import type { FastifyInstance, FastifyRequest } from 'fastify';
import fp from 'fastify-plugin';
import { config } from '../config.js';
import { adminSupabase, createUserSupabase } from './supabase.js';
import { JwtSessionManager } from '../services/jwt_session.js';

export const registerAuth = fp(async function registerAuth(app: FastifyInstance): Promise<void> {
  app.decorateRequest(
    'authUser',
    null as unknown as FastifyRequest['authUser'],
  );

  app.decorateRequest(
    'userSupabase',
    null as unknown as FastifyRequest['userSupabase'],
  );

  app.addHook('preHandler', async (request: FastifyRequest) => {
    const rawUrl = request.url || (request.raw && request.raw.url) || '/';
    let urlPath = '/';
    try {
      urlPath = new URL(rawUrl, 'http://localhost').pathname;
    } catch {
      urlPath = typeof rawUrl === 'string' ? rawUrl : '/';
    }
    const routePath = request.routeOptions?.url || (request as any).routerPath;

    if (
      urlPath === '/health' ||
      urlPath.startsWith('/webhooks/') ||
      urlPath.startsWith('/dev/auth/') ||
      urlPath.startsWith('/auth/phone/') ||
      urlPath.startsWith('/auth/session/') ||
      routePath === '/health' ||
      routePath?.startsWith('/webhooks/') ||
      routePath?.startsWith('/dev/auth/') ||
      routePath?.startsWith('/auth/phone/') ||
      routePath?.startsWith('/auth/session/')
    ) {
      return;
    }

    if (config.DEV_TEST_AUTH && request.headers['x-dev-test-auth'] === 'true') {
      const devUserId = (request.headers['x-user-id'] as string) || 'ed9517fc-7ebe-437c-bdc0-abb45bef9079';
      request.authUser = {
        id: devUserId,
        email: devUserId === 'dc07d14a-b820-4178-928f-4de1cfab13bb' ? 'susrijambagi@gmail.com' : 'shipsterheadquarter@gmail.com',
        role: 'authenticated',
        app_metadata: {},
        user_metadata: {},
        aud: 'authenticated',
        created_at: new Date().toISOString(),
      } as any;
      request.userSupabase = adminSupabase as any;
      return;
    }

    const headers = request.headers || (request.raw && request.raw.headers) || {};
    const header = (headers.authorization || headers.Authorization) as string | undefined;

    if (!header?.startsWith('Bearer ')) {
      const err: any = new Error('Missing bearer token');
      err.statusCode = 401;
      err.name = 'Unauthorized';
      throw err;
    }

    const accessToken = header.slice(
      'Bearer '.length,
    );

    let resolvedUser: any = null;
    let isCustomJwt = false;

    // 1. Try verifying custom ShipdeHop ES256 JWT
    try {
      const customPayload = JwtSessionManager.verifyUserAccessJwt(accessToken);
      resolvedUser = {
        id: customPayload.userId,
        role: customPayload.role,
        aud: 'authenticated',
        phone: customPayload.phone || '',
        app_metadata: {},
        user_metadata: {},
        created_at: new Date().toISOString(),
      };
      isCustomJwt = true;
    } catch {
      // 2. Fallback to Supabase GoTrue Auth token verification via getClaims
      try {
        if (typeof (adminSupabase.auth as any).getClaims === 'function') {
          const { data: claimsData, error: claimsErr } = await (adminSupabase.auth as any).getClaims(accessToken);
          if (!claimsErr && claimsData && (claimsData.claims || claimsData.sub || claimsData.id)) {
            const claims = claimsData.claims || claimsData;
            resolvedUser = {
              id: claims.sub || claims.id,
              email: claims.email || '',
              phone: claims.phone || '',
              role: claims.role || 'authenticated',
              aud: claims.aud || 'authenticated',
              app_metadata: claims.app_metadata || {},
              user_metadata: claims.user_metadata || {},
              created_at: claims.created_at || new Date().toISOString(),
            };
          }
        }
      } catch (_claimsError) {
        resolvedUser = null;
      }

      if (!resolvedUser) {
        const { data, error } = await adminSupabase.auth.getUser(accessToken);
        if (error || !data.user) {
          const err = (request.server as any).httpErrors?.unauthorized('Invalid or expired token') ||
            Object.assign(new Error('Invalid or expired token'), { statusCode: 401, name: 'Unauthorized' });
          throw err;
        }
        resolvedUser = data.user;
      }
    }

    if (!resolvedUser?.id) {
      const err = (request.server as any).httpErrors?.unauthorized('Invalid or expired token') ||
        Object.assign(new Error('Invalid or expired token'), { statusCode: 401, name: 'Unauthorized' });
      throw err;
    }

    // Canonical active account check against public.users
    const { data: userRow } = await adminSupabase
      .from('users')
      .select('full_name')
      .eq('id', resolvedUser.id)
      .maybeSingle();

    if (!userRow || userRow.full_name === 'Deleted User') {
      const err = (request.server as any).httpErrors?.unauthorized('Account has been deleted or deactivated') ||
        Object.assign(new Error('Account has been deleted or deactivated'), { statusCode: 401, name: 'Unauthorized' });
      throw err;
    }

    request.authUser = resolvedUser;
    request.userSupabase = isCustomJwt ? (adminSupabase as any) : createUserSupabase(accessToken);
  });
});
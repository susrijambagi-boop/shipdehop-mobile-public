import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { adminSupabase, createUserSupabase } from '../lib/supabase.js';

export async function notificationRoutes(app: FastifyInstance): Promise<void> {
  // GET /notifications — Fetch authenticated user's notifications feed
  app.get('/notifications', async (request) => {
    const query = z.object({
      limit: z.coerce.number().int().min(1).max(100).default(50),
      offset: z.coerce.number().int().min(0).default(0),
    }).parse(request.query);

    const userId = request.authUser.id;
    const authHeader = request.headers.authorization;
    const userClient = authHeader ? createUserSupabase(authHeader.replace(/^Bearer\s+/i, '')) : adminSupabase;

    const { data: notifications, error } = await userClient
      .from('notifications')
      .select('*')
      .eq('user_id', userId)
      .order('created_at', { ascending: false })
      .range(query.offset, query.offset + query.limit - 1);

    if (error) {
      throw app.httpErrors.internalServerError(`Failed to fetch notifications: ${error.message}`);
    }

    return { notifications: notifications || [] };
  });

  // GET /notifications/unread-count — Get count of unread notifications
  app.get('/notifications/unread-count', async (request) => {
    const userId = request.authUser.id;
    const authHeader = request.headers.authorization;
    const userClient = authHeader ? createUserSupabase(authHeader.replace(/^Bearer\s+/i, '')) : adminSupabase;

    const { count, error } = await userClient
      .from('notifications')
      .select('id', { count: 'exact', head: true })
      .eq('user_id', userId)
      .is('read_at', null);

    if (error) {
      throw app.httpErrors.internalServerError(`Failed to count unread notifications: ${error.message}`);
    }

    return { unreadCount: count || 0 };
  });

  // PATCH /notifications/:id/read — Mark single notification as read under user auth context
  app.patch('/notifications/:id/read', async (request) => {
    const params = z.object({ id: z.string().uuid() }).parse(request.params);
    const userId = request.authUser.id;
    const authHeader = request.headers.authorization;

    if (authHeader) {
      const userClient = createUserSupabase(authHeader.replace(/^Bearer\s+/i, ''));
      const { error: rpcError } = await userClient.rpc('mark_notification_read', {
        p_notification_id: params.id,
      });

      if (!rpcError) {
        return { success: true };
      }
    }

    // Fallback scoped update matching user_id strictly
    const { error } = await adminSupabase
      .from('notifications')
      .update({ read_at: new Date().toISOString() })
      .eq('id', params.id)
      .eq('user_id', userId)
      .is('read_at', null);

    if (error) {
      throw app.httpErrors.badRequest(`Failed to mark notification read: ${error.message}`);
    }

    return { success: true };
  });

  // PATCH /notifications/read-all — Mark all unread notifications read for authenticated user
  app.patch('/notifications/read-all', async (request) => {
    const userId = request.authUser.id;
    const authHeader = request.headers.authorization;

    if (authHeader) {
      const userClient = createUserSupabase(authHeader.replace(/^Bearer\s+/i, ''));
      const { error: rpcError } = await userClient.rpc('mark_all_notifications_read');

      if (!rpcError) {
        return { success: true };
      }
    }

    const { error } = await adminSupabase
      .from('notifications')
      .update({ read_at: new Date().toISOString() })
      .eq('user_id', userId)
      .is('read_at', null);

    if (error) {
      throw app.httpErrors.badRequest(`Failed to mark all notifications read: ${error.message}`);
    }

    return { success: true };
  });
}

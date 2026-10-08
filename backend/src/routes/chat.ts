import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { adminSupabase } from '../lib/supabase.js';
import { assessChat } from '../services/antiScam.js';

export async function chatRoutes(app: FastifyInstance): Promise<void> {
  // 1. Get Global Chat Inbox Threads for Authenticated User
  app.get('/chat/threads', async (request) => {
    const query = z.object({
      limit: z.coerce.number().int().min(1).max(100).default(50),
      offset: z.coerce.number().int().min(0).default(0),
    }).parse(request.query);

    const userId = request.authUser.id;

    // Fetch escrow orders where user is buyer or provider
    const { data: orders, error: ordersErr } = await adminSupabase
      .from('escrow_orders')
      .select('id, order_type, buyer_id, provider_id, marketplace_item_id, shipment_task_id, trip_id, escrow_status, fulfillment_status')
      .or(`buyer_id.eq.${userId},provider_id.eq.${userId}`)
      .order('created_at', { ascending: false })
      .range(query.offset, query.offset + query.limit - 1);

    if (ordersErr || !orders || orders.length === 0) {
      return { threads: [] };
    }

    const orderIds = orders.map((o) => o.id);
    const itemIds = orders.map((o) => o.marketplace_item_id).filter(Boolean) as string[];
    const taskIds = orders.map((o) => o.shipment_task_id).filter(Boolean) as string[];
    const tripIds = orders.map((o) => o.trip_id).filter(Boolean) as string[];

    const [{ data: threads }, { data: reads }, { data: mktItems }, { data: shipTasks }, { data: trips }, { data: users }] = await Promise.all([
      adminSupabase.from('chat_threads').select('id, order_id, created_at').in('order_id', orderIds),
      adminSupabase.from('chat_thread_reads').select('thread_id, last_read_at').eq('user_id', userId),
      itemIds.length ? adminSupabase.from('marketplace_items').select('*').in('id', itemIds) : Promise.resolve({ data: [] }),
      taskIds.length ? adminSupabase.from('shipment_tasks').select('*').in('id', taskIds) : Promise.resolve({ data: [] }),
      tripIds.length ? adminSupabase.from('trip_routes').select('*').in('id', tripIds) : Promise.resolve({ data: [] }),
      adminSupabase.from('users').select('id, email, full_name, avatar_url, ekyc_tier, trust_score'),
    ]);

    if (!threads || threads.length === 0) {
      return { threads: [] };
    }

    const threadIds = threads.map((t) => t.id);
    const { data: latestMsgs } = await adminSupabase
      .from('chat_messages')
      .select('id, thread_id, sender_id, body, image_url, created_at')
      .in('thread_id', threadIds)
      .order('created_at', { ascending: false });

    const orderMap = new Map(orders.map((o) => [o.id, o]));
    const readMap = new Map((reads || []).map((r) => [r.thread_id, r.last_read_at]));
    const mktItemMap = new Map((mktItems || []).map((i) => [i.id, i]));
    const shipTaskMap = new Map((shipTasks || []).map((t) => [t.id, t]));
    const tripMap = new Map((trips || []).map((t) => [t.id, t]));
    const userMap = new Map((users || []).map((u) => [u.id, u]));

    // Group latest messages and calculate unread counts per thread
    const threadMsgMap = new Map<string, any[]>();
    (latestMsgs || []).forEach((m) => {
      if (!threadMsgMap.has(m.thread_id)) threadMsgMap.set(m.thread_id, []);
      threadMsgMap.get(m.thread_id)!.push(m);
    });

    const result = threads.map((t) => {
      const order = orderMap.get(t.order_id);
      if (!order) return null;

      const isBuyer = order.buyer_id === userId;
      const counterpartyId = isBuyer ? order.provider_id : order.buyer_id;
      const counterpartyUser = userMap.get(counterpartyId);

      const msgs = threadMsgMap.get(t.id) || [];
      const lastMsg = msgs[0] ?? null;
      const lastReadAt = readMap.get(t.id) ? new Date(readMap.get(t.id)) : new Date(0);

      const unreadCount = msgs.filter((m) => m.sender_id !== userId && new Date(m.created_at) > lastReadAt).length;

      let module: 'PARCELPOOL' | 'CARPOOL' | 'MARKETPLACE' = 'PARCELPOOL';
      let contextTitle = 'Transaction Chat';

      if (order.order_type === 'MARKETPLACE' || order.marketplace_item_id) {
        module = 'MARKETPLACE';
        const item = mktItemMap.get(order.marketplace_item_id);
        contextTitle = `Marketplace · ${item?.title ?? 'Purchase'}`;
      } else if (order.order_type === 'RIDE' || order.trip_id) {
        module = 'CARPOOL';
        const trip = tripMap.get(order.trip_id);
        contextTitle = `CarPool · ${trip?.origin_name ?? 'Origin'} → ${trip?.dest_name ?? 'Destination'}`;
      } else {
        module = 'PARCELPOOL';
        const task = shipTaskMap.get(order.shipment_task_id);
        contextTitle = `ParcelPool · ${task?.origin_name ?? 'Origin'} → ${task?.dest_name ?? 'Destination'}`;
      }

      return {
        id: t.id,
        orderId: t.order_id,
        module,
        contextTitle,
        counterparty: {
          id: counterpartyId,
          fullName: counterpartyUser?.full_name ?? (counterpartyId.startsWith('ed9517fc') ? 'Shipster Headquarter' : 'Hopster Carrier'),
          avatarUrl: counterpartyUser?.avatar_url ?? null,
          ekycTier: counterpartyUser?.ekyc_tier ?? 'TIER_1',
          trustScore: counterpartyUser?.trust_score ? Number(counterpartyUser.trust_score) : 50.0,
        },
        lastMessage: lastMsg ? {
          body: lastMsg.body ?? (lastMsg.image_url ? '[Image]' : ''),
          senderId: lastMsg.sender_id,
          createdAt: lastMsg.created_at,
        } : null,
        unreadCount,
        orderStatus: order.fulfillment_status,
        escrowStatus: order.escrow_status,
        createdAt: t.created_at,
      };
    }).filter(Boolean);

    // Sort by latest message date or thread created_at
    result.sort((a: any, b: any) => {
      const dateA = a.lastMessage?.createdAt || a.createdAt;
      const dateB = b.lastMessage?.createdAt || b.createdAt;
      return new Date(dateB).getTime() - new Date(dateA).getTime();
    });

    return { threads: result };
  });

  // 2. Get Messages for a Specific Thread
  app.get('/chat/threads/:threadId/messages', async (request) => {
    const { threadId } = z.object({ threadId: z.string().uuid() }).parse(request.params);
    const userId = request.authUser.id;

    // Verify actor is participant
    const { data: thread } = await adminSupabase.from('chat_threads').select('id, order_id').eq('id', threadId).single();
    if (!thread) throw app.httpErrors.notFound('Chat thread not found');

    const { data: order } = await adminSupabase.from('escrow_orders').select('buyer_id, provider_id').eq('id', thread.order_id).single();
    if (!order || (order.buyer_id !== userId && order.provider_id !== userId)) {
      throw app.httpErrors.forbidden('Access denied to chat thread');
    }

    const { data: messages, error } = await adminSupabase
      .from('chat_messages')
      .select('id, thread_id, sender_id, body, image_url, safety_status, created_at')
      .eq('thread_id', threadId)
      .order('created_at', { ascending: true });

    if (error) throw app.httpErrors.internalServerError(error.message);

    // Automatically mark thread as read for actor
    await adminSupabase.rpc('mark_chat_thread_read', {
      p_actor_id: userId,
      p_thread_id: threadId,
    });

    return { messages: messages || [] };
  });

  // 3. Mark Chat Thread as Read
  app.post('/chat/threads/:threadId/read', async (request) => {
    const { threadId } = z.object({ threadId: z.string().uuid() }).parse(request.params);
    const userId = request.authUser.id;

    const { error } = await adminSupabase.rpc('mark_chat_thread_read', {
      p_actor_id: userId,
      p_thread_id: threadId,
    });

    if (error) throw app.httpErrors.forbidden(error.message);
    return { success: true };
  });

  // 4. Get or Create Chat Thread for Order
  app.post('/chat/threads/order/:orderId', async (request) => {
    const { orderId } = z.object({ orderId: z.string().uuid() }).parse(request.params);
    const userId = request.authUser.id;

    const { data: order } = await adminSupabase
      .from('escrow_orders')
      .select('id, buyer_id, provider_id')
      .eq('id', orderId)
      .single();

    if (!order || (order.buyer_id !== userId && order.provider_id !== userId)) {
      throw app.httpErrors.forbidden('Access denied to order thread');
    }

    let { data: thread } = await adminSupabase
      .from('chat_threads')
      .select('*')
      .eq('order_id', orderId)
      .single();

    if (!thread) {
      const { data: newThread, error: createErr } = await adminSupabase
        .from('chat_threads')
        .insert({ order_id: orderId })
        .select('*')
        .single();

      if (createErr) throw app.httpErrors.internalServerError(createErr.message);
      thread = newThread;
    }

    const isBuyer = order.buyer_id === userId;
    const counterpartyId = isBuyer ? order.provider_id : order.buyer_id;

    const { data: counterpartyUser } = await adminSupabase
      .from('users')
      .select('id, full_name, avatar_url')
      .eq('id', counterpartyId)
      .maybeSingle();

    return {
      thread,
      counterparty: {
        id: counterpartyId,
        fullName: counterpartyUser?.full_name ?? (isBuyer ? 'Traveller' : 'Sender'),
        avatarUrl: counterpartyUser?.avatar_url ?? null,
      },
    };
  });

  // 5. Global Unread Messages Count across all threads
  app.get('/chat/unread-count', async (request) => {
    const userId = request.authUser.id;

    const { data: orders } = await adminSupabase
      .from('escrow_orders')
      .select('id')
      .or(`buyer_id.eq.${userId},provider_id.eq.${userId}`);

    if (!orders || orders.length === 0) return { unreadCount: 0 };

    const orderIds = orders.map((o) => o.id);
    const { data: threads } = await adminSupabase.from('chat_threads').select('id').in('order_id', orderIds);
    if (!threads || threads.length === 0) return { unreadCount: 0 };

    const threadIds = threads.map((t) => t.id);
    const [{ data: reads }, { data: msgs }] = await Promise.all([
      adminSupabase.from('chat_thread_reads').select('thread_id, last_read_at').eq('user_id', userId),
      adminSupabase.from('chat_messages').select('thread_id, sender_id, created_at').in('thread_id', threadIds),
    ]);

    const readMap = new Map((reads || []).map((r) => [r.thread_id, r.last_read_at]));
    let totalUnread = 0;

    (msgs || []).forEach((m) => {
      if (m.sender_id !== userId) {
        const lastRead = readMap.get(m.thread_id) ? new Date(readMap.get(m.thread_id)) : new Date(0);
        if (new Date(m.created_at) > lastRead) {
          totalUnread++;
        }
      }
    });

    return { unreadCount: totalUnread };
  });

  // 6. Send Message to Thread
  app.post('/chat/:threadId/messages', { bodyLimit: 8 * 1024 * 1024 }, async (request) => {
    const { threadId } = z.object({ threadId: z.string().uuid() }).parse(request.params);
    const body = z.object({
      text: z.string().trim().max(4000).optional(),
      imageBase64: z.string().max(7_000_000).optional(),
      imageMimeType: z.enum(['image/jpeg', 'image/png', 'image/webp']).optional(),
      imageUrl: z.string().url().optional(),
    }).refine((v) => Boolean(v.text || v.imageBase64 || v.imageUrl), 'Message text or image is required').parse(request.body);

    const { data: thread } = await adminSupabase.from('chat_threads').select('id, order_id').eq('id', threadId).single();
    if (!thread) throw app.httpErrors.notFound('Chat thread not found');

    const { data: order } = await adminSupabase.from('escrow_orders').select('buyer_id, provider_id').eq('id', thread.order_id).single();
    if (!order || (order.buyer_id !== request.authUser.id && order.provider_id !== request.authUser.id)) {
      throw app.httpErrors.forbidden('Access denied to chat thread');
    }

    const assessment = await assessChat({
      ...(body.text ? { text: body.text } : {}),
      ...(body.imageBase64 ? { imageBase64: body.imageBase64 } : {}),
      ...(body.imageMimeType ? { imageMimeType: body.imageMimeType } : {}),
    });
    if (assessment.action === 'BLOCKED') {
      throw app.httpErrors.forbidden(`HopShield blocked this message: ${assessment.reasons.join('; ')}`);
    }

    const { data, error } = await adminSupabase.from('chat_messages').insert({
      thread_id: threadId,
      sender_id: request.authUser.id,
      body: body.text ?? null,
      image_url: body.imageUrl ?? null,
      safety_status: assessment.action,
      safety_reason: assessment.reasons.join('; ').slice(0, 2000),
    }).select('*').single();

    if (error) throw app.httpErrors.internalServerError(error.message);

    // Update sender's read status
    await adminSupabase.rpc('mark_chat_thread_read', {
      p_actor_id: request.authUser.id,
      p_thread_id: threadId,
    });

    return { message: data, hopShield: assessment };
  });
}

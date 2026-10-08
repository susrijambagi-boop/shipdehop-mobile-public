import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { adminSupabase } from '../lib/supabase.js';

export async function historyRoutes(app: FastifyInstance): Promise<void> {
  app.get('/history', async (request) => {
    const query = z.object({
      statusFilter: z.enum(['ALL', 'ACTIVE', 'COMPLETED', 'CANCELLED']).default('ALL'),
      moduleFilter: z.enum(['ALL', 'PARCELPOOL', 'CARPOOL', 'MARKETPLACE']).default('ALL'),
      limit: z.coerce.number().int().min(1).max(100).default(50),
      offset: z.coerce.number().int().min(0).default(0),
    }).parse(request.query);

    const userId = request.authUser.id;

    // Fetch escrow orders involving user as buyer or provider
    const { data: orders, error } = await adminSupabase
      .from('escrow_orders')
      .select('*')
      .or(`buyer_id.eq.${userId},provider_id.eq.${userId}`)
      .order('created_at', { ascending: false })
      .range(query.offset, query.offset + query.limit - 1);

    if (error) {
      throw app.httpErrors.internalServerError(error.message);
    }

    if (!orders || orders.length === 0) {
      return { history: [], total: 0 };
    }

    const orderIds = orders.map((o) => o.id);
    const itemIds = orders.map((o) => o.marketplace_item_id).filter(Boolean) as string[];
    const taskIds = orders.map((o) => o.shipment_task_id).filter(Boolean) as string[];
    const tripIds = orders.map((o) => o.trip_id).filter(Boolean) as string[];

    // Fetch related domain entities in batch
    const [{ data: chatThreads }, { data: mktPurchases }, { data: mktItems }, { data: shipTasks }, { data: trips }, { data: users }] = await Promise.all([
      adminSupabase.from('chat_threads').select('id, order_id').in('order_id', orderIds),
      itemIds.length ? adminSupabase.from('marketplace_purchases').select('*').in('escrow_order_id', orderIds) : Promise.resolve({ data: [] }),
      itemIds.length ? adminSupabase.from('marketplace_items').select('*').in('id', itemIds) : Promise.resolve({ data: [] }),
      taskIds.length ? adminSupabase.from('shipment_tasks').select('*').in('id', taskIds) : Promise.resolve({ data: [] }),
      tripIds.length ? adminSupabase.from('trip_routes').select('*').in('id', tripIds) : Promise.resolve({ data: [] }),
      adminSupabase.from('users').select('id, email, phone, full_name, avatar_url, ekyc_tier, trust_score'),
    ]);

    const threadMap = new Map((chatThreads || []).map((t) => [t.order_id, t.id]));
    const mktPurchaseMap = new Map((mktPurchases || []).map((p) => [p.escrow_order_id, p]));
    const mktItemMap = new Map((mktItems || []).map((i) => [i.id, i]));
    const shipTaskMap = new Map((shipTasks || []).map((t) => [t.id, t]));
    const tripMap = new Map((trips || []).map((t) => [t.id, t]));
    const userMap = new Map((users || []).map((u) => [u.id, u]));

    const historyItems = orders.map((o) => {
      const isBuyer = o.buyer_id === userId;
      const counterpartyId = isBuyer ? o.provider_id : o.buyer_id;
      const counterpartyUser = userMap.get(counterpartyId);
      const threadId = threadMap.get(o.id) ?? null;

      let module: 'PARCELPOOL' | 'CARPOOL' | 'MARKETPLACE' = 'PARCELPOOL';
      let roleLabel = 'Participant';
      let title = 'Transaction';
      let originName: string | null = null;
      let destName: string | null = null;
      let targetScreen = 'orders';

      if (o.order_type === 'MARKETPLACE' || o.marketplace_item_id) {
        module = 'MARKETPLACE';
        roleLabel = isBuyer ? 'Buyer' : 'Seller';
        const item = mktItemMap.get(o.marketplace_item_id);
        title = item ? item.title : 'Marketplace Purchase';
        originName = item?.location_name ?? null;
        targetScreen = 'marketplace';
      } else if (o.order_type === 'SHIPMENT' || o.shipment_task_id) {
        module = 'PARCELPOOL';
        const task = shipTaskMap.get(o.shipment_task_id);
        const trip = tripMap.get(o.trip_id);
        roleLabel = isBuyer ? 'Sender' : 'Traveller';
        originName = task?.pickup_name ?? trip?.origin_name ?? null;
        destName = task?.drop_name ?? trip?.dest_name ?? null;
        title = task ? `Parcel: ${task.pickup_name} → ${task.drop_name}` : 'Parcel Delivery';
        targetScreen = 'delivery';
      } else if (o.order_type === 'RIDE' || o.trip_id) {
        module = 'CARPOOL';
        roleLabel = isBuyer ? 'Pooler' : 'Driver';
        const trip = tripMap.get(o.trip_id);
        originName = trip?.origin_name ?? null;
        destName = trip?.dest_name ?? null;
        title = trip ? `CarPool: ${trip.origin_name} → ${trip.dest_name}` : 'CarPool Ride';
        targetScreen = 'carpool';
      } else {
        module = 'PARCELPOOL';
        const task = shipTaskMap.get(o.shipment_task_id);
        roleLabel = isBuyer ? 'Sender' : 'Traveller';
        originName = task?.pickup_name ?? null;
        destName = task?.drop_name ?? null;
        title = task ? `Parcel: ${task.pickup_name} → ${task.drop_name}` : 'Parcel Delivery';
        targetScreen = 'delivery';
      }

      // Determine Normalized User-Facing Status & Filter Category
      let statusCategory: 'ACTIVE' | 'COMPLETED' | 'CANCELLED' = 'ACTIVE';
      let userStatusLabel = 'Awaiting Match Acceptance';

      if (o.escrow_status === 'RELEASED' || o.fulfillment_status === 'COMPLETED' || o.fulfillment_status === 'DELIVERED') {
        statusCategory = 'COMPLETED';
        userStatusLabel = 'Delivered & Completed';
      } else if (o.escrow_status === 'REFUNDED' || o.fulfillment_status === 'CANCELLED') {
        statusCategory = 'CANCELLED';
        userStatusLabel = 'Cancelled';
      } else if (o.fulfillment_status === 'VERIFIED') {
        statusCategory = 'COMPLETED';
        userStatusLabel = 'Delivered & Verified';
      } else if (o.fulfillment_status === 'IN_TRANSIT') {
        statusCategory = 'ACTIVE';
        userStatusLabel = 'In Transit';
      } else if (o.fulfillment_status === 'READY') {
        statusCategory = 'ACTIVE';
        userStatusLabel = 'Match Accepted · Ready for Pickup';
      } else if (o.fulfillment_status === 'CREATED') {
        statusCategory = 'ACTIVE';
        userStatusLabel = 'Match Requested';
      } else {
        statusCategory = 'ACTIVE';
        userStatusLabel = 'Active';
      }

      const isMatchAccepted = ['READY', 'IN_TRANSIT', 'VERIFIED', 'COMPLETED'].includes(o.fulfillment_status);

      return {
        id: o.id,
        orderType: o.order_type,
        module,
        roleLabel,
        title,
        amount: Number(o.total_amount),
        currency: o.currency || 'INR',
        createdAt: o.created_at,
        escrowStatus: o.escrow_status,
        fulfillmentStatus: o.fulfillment_status,
        statusCategory,
        userStatusLabel,
        originName,
        destName,
        threadId,
        counterparty: {
          id: counterpartyId,
          fullName: counterpartyUser?.full_name ?? (isBuyer ? 'Traveller' : 'Sender'),
          email: null, // Privacy: In-app chat preferred
          avatarUrl: counterpartyUser?.avatar_url ?? null,
          ekycTier: counterpartyUser?.ekyc_tier ?? 'TIER_1',
          trustScore: counterpartyUser?.trust_score ? Number(counterpartyUser.trust_score) : 85.0,
        },
        deepLink: {
          targetScreen,
          orderId: o.id,
          marketplaceItemId: o.marketplace_item_id,
          shipmentTaskId: o.shipment_task_id,
          tripId: o.trip_id,
        },
      };
    });

    // Filter results according to query parameters
    let filtered = historyItems;
    if (query.statusFilter !== 'ALL') {
      filtered = filtered.filter((i) => i.statusCategory === query.statusFilter);
    }
    if (query.moduleFilter !== 'ALL') {
      filtered = filtered.filter((i) => i.module === query.moduleFilter);
    }

    return {
      history: filtered,
      total: filtered.length,
    };
  });
}

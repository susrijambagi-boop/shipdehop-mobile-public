import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { productionConversationDeps, respondToConversation } from '../services/conversationAssistant.js';
const context = z.object({
  intent: z.string().max(40).optional(), originQuery: z.string().max(180).optional(),
  destinationQuery: z.string().max(180).optional(), travelDate: z.string().max(20).optional(),
  dateFlexible: z.boolean().optional(), availableWeightKg: z.number().finite().nonnegative().optional(),
  passengers: z.number().finite().nonnegative().optional(), marketplaceQuery: z.string().max(180).optional(),
  itemDescription: z.string().max(180).optional(), productUrl: z.string().max(180).optional(),
  maxPrice: z.number().finite().nonnegative().optional(),
});
export async function conversationRoutes(app: FastifyInstance): Promise<void> {
  app.post('/assistant/converse', async (request, reply) => {
    if (!request.authUser?.id || !request.userSupabase) {
      return reply.code(401).send({message:'Sign in to use Ask ShipdeHop.'});
    }
    const body = z.object({
      message: z.string().trim().min(1).max(1200), context: context.optional(),
      history: z.array(z.object({role: z.enum(['user','assistant']),text:z.string().max(1200)})).max(16).optional(),
    }).safeParse(request.body);
    if (!body.success) return reply.code(400).send({message:'Please send a shorter message or start a new conversation.'});
    return respondToConversation({
      message: body.data.message,
      ...(body.data.context ? {context: body.data.context} : {}),
      ...(body.data.history ? {history: body.data.history} : {}),
    }, productionConversationDeps(request.userSupabase));
  });
}

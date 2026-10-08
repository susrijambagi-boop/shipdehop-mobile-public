import Fastify from 'fastify';
import sensible from '@fastify/sensible';
// Non-secret local fixtures; registration never contacts these services.
process.env.NODE_ENV = 'test';
process.env.SUPABASE_URL = 'https://example.supabase.co';
process.env.SUPABASE_PUBLISHABLE_KEY = 'local-test-placeholder';
process.env.SUPABASE_SECRET_KEY = 'local-test-placeholder';
process.env.GEMINI_API_KEY = 'local-test';
process.env.GOOGLE_ROUTES_API_KEY = 'local-test';
const app = Fastify();
await app.register(sensible);
for (const [file, name] of [
 ['trips','tripRoutes'], ['orders','orderRoutes'], ['marketplace','marketplaceRoutes'],
 ['rideRequests','rideRequestRoutes'], ['chat','chatRoutes'], ['tracking','trackingRoutes'],
 ['notifications','notificationRoutes'], ['history','historyRoutes'], ['profile','profileRoutes'],
 ['phone_verification','phoneVerificationRoutes'], ['identity','identityRoutes'],
 ['hopshield','hopShieldRoutes'], ['devAuth','devAuthRoutes'], ['webhooks','webhookRoutes'],
]) {
 const routes = await import(`./routes/${file}.js`);
 await app.register(routes[name!]);
}
await app.ready();
await app.close();
console.log('All backend routes register without conflicts');

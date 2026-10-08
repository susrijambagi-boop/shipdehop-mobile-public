/**
 * Safe Cloudflare Cache API Wrapper for Geoapify Provider Responses.
 *
 * Requirements:
 * - Cache provider responses ONLY, NEVER user/private responses.
 * - Cache keys MUST NOT contain: Authorization headers, Supabase tokens, Geoapify API key, user IDs.
 * - Graceful fallback in non-Cloudflare/Node test environments.
 */

export async function getGeoapifyCache<T>(cacheKeyUrl: string): Promise<T | null> {
  const cacheStorage = typeof caches !== 'undefined' ? (caches as any) : null;
  if (!cacheStorage || !cacheStorage.default) {
    return null;
  }
  try {
    const cache = cacheStorage.default;
    const request = new Request(cacheKeyUrl, { method: 'GET' });
    const response = await cache.match(request);
    if (response && response.ok) {
      return (await response.json()) as T;
    }
  } catch (_err) {
    // Graceful fallback for environments without Cloudflare Cache API
  }
  return null;
}

export async function setGeoapifyCache<T>(cacheKeyUrl: string, data: T, ttlSeconds: number): Promise<void> {
  const cacheStorage = typeof caches !== 'undefined' ? (caches as any) : null;
  if (!cacheStorage || !cacheStorage.default) {
    return;
  }
  try {
    const cache = cacheStorage.default;
    const request = new Request(cacheKeyUrl, { method: 'GET' });
    const response = new Response(JSON.stringify(data), {
      status: 200,
      headers: {
        'Content-Type': 'application/json',
        'Cache-Control': `public, max-age=${ttlSeconds}`,
      },
    });
    await cache.put(request, response);
  } catch (_err) {
    // Graceful fallback for environments without Cloudflare Cache API
  }
}

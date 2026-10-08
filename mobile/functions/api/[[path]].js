/**
 * Cloudflare Pages Function: Same-Origin Reverse Proxy
 *
 * Proxies https://shipdehop-app.pages.dev/api/* to https://backend-production-543f.up.railway.app/*
 * Enables 1st-party HttpOnly session cookies, eliminates Safari cross-site cookie blocking,
 * and preserves status codes, headers, and Set-Cookie headers without embedding secrets.
 */
export async function onRequest(context) {
  const { request, params, env } = context;
  const url = new URL(request.url);

  // Target Railway backend origin (configurable via Cloudflare env or production default)
  const backendBaseUrl = env.BACKEND_API_URL || 'https://backend-production-543f.up.railway.app';

  // Extract path following /api
  const proxyPath = params.path
    ? Array.isArray(params.path)
      ? params.path.join('/')
      : params.path
    : '';

  const targetUrl = new URL(`/${proxyPath}${url.search}`, backendBaseUrl);

  // Hop-by-hop headers that should not be proxied
  const hopByHopHeaders = new Set([
    'connection',
    'keep-alive',
    'proxy-authenticate',
    'proxy-authorization',
    'te',
    'trailer',
    'transfer-encoding',
    'upgrade',
    'cf-connecting-ip',
    'cf-ipcountry',
    'cf-ray',
    'cf-visitor',
  ]);

  // Clone safe request headers
  const forwardHeaders = new Headers();
  for (const [key, value] of request.headers.entries()) {
    const lower = key.toLowerCase();
    if (!hopByHopHeaders.has(lower)) {
      forwardHeaders.set(key, value);
    }
  }

  // Add standard forwarding metadata
  forwardHeaders.set('X-Forwarded-Host', url.host);
  forwardHeaders.set('X-Forwarded-Proto', url.protocol.replace(':', ''));

  const init = {
    method: request.method,
    headers: forwardHeaders,
    redirect: 'manual',
  };

  if (request.method !== 'GET' && request.method !== 'HEAD') {
    init.body = request.body;
  }

  try {
    const backendResponse = await fetch(targetUrl.toString(), init);

    // Build safe response headers, preserving Set-Cookie and CORS metadata
    const responseHeaders = new Headers();
    for (const [key, value] of backendResponse.headers.entries()) {
      const lower = key.toLowerCase();
      if (!hopByHopHeaders.has(lower)) {
        responseHeaders.set(key, value);
      }
    }

    return new Response(backendResponse.body, {
      status: backendResponse.status,
      statusText: backendResponse.statusText,
      headers: responseHeaders,
    });
  } catch (err) {
    return new Response(
      JSON.stringify({ error: 'Backend gateway proxy error', message: err?.message || 'Network error' }),
      {
        status: 502,
        headers: { 'Content-Type': 'application/json' },
      }
    );
  }
}

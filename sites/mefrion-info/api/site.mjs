import site from '../worker/index.js';
import { observe } from '../security/monitor.mjs';

// Public pages share the existing router. Off-site encrypted backup storage
// remains on its independent object store; no backup credentials enter Vercel.
export async function route(request) {
  const path = new URL(request.url).pathname;
  if (path === '/internal-backup' || path.startsWith('/internal-backup/')) {
    return new Response('ページが見つかりません。', {
      status: 404,
      headers: { 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' },
    });
  }
  return site.fetch(request);
}

// Short-lived, project-bound OIDC; no deployment token or service-role key on Vercel.
export default async function handler(req, res) {
  try {
    const url = new URL(req.url, 'https://mefrion.invalid');
    const rewrittenPath = url.searchParams.getAll('__mefrion_path');
    if (rewrittenPath.length > 1) {
      res.statusCode = 400;
      observe(req, new URL('https://mefrion.vercel.app/[unknown]'), 400);
      res.setHeader('Cache-Control', 'no-store');
      res.end();
      return;
    }
    if (rewrittenPath.length) url.pathname = '/' + rewrittenPath[0].replace(/^\/+/, '');
    url.searchParams.delete('__mefrion_path');
    const response = await route(new Request(url, { method: req.method || 'GET' }));
    res.statusCode = response.status;
    observe(req, url, response.status);
    response.headers.forEach((value, key) => res.setHeader(key, value));
    res.end(req.method === 'HEAD' ? undefined : Buffer.from(await response.arrayBuffer()));
  } catch {
    // Do not log incoming URLs, request headers, tokens, or error payloads.
    observe(req, new URL('https://mefrion.vercel.app/[unknown]'), 503);
    res.statusCode = 503;
    res.setHeader('Cache-Control', 'no-store');
    res.setHeader('Content-Type', 'text/plain; charset=utf-8');
    res.end('読み込めませんでした。もう一度お試しください。');
  }
}

import { getVercelOidcToken } from '@vercel/oidc';
import { waitUntil, ipAddress, geolocation } from '@vercel/functions';
import { randomUUID } from 'node:crypto';
import { classify } from './classifier.mjs';
const ENDPOINT = 'https://pbnimpqrthvznbwewtcf.supabase.co/functions/v1/security-collector';
let heartbeat = 0, windowStart = 0, sent = 0, lost = 0;
export function observe(req, url, status) {
  try { return observeSafely(req, url, status); } catch { /* Monitoring cannot break the user response. */ }
}
function observeSafely(req, url, status) {
  if (process.env.VERCEL !== '1' || process.env.VERCEL_ENV !== 'production') return;
  const event = classify({ path: url.pathname, query: url.search, method: req.method, status });
  const now = Date.now();
  if (!event && now - heartbeat < 300_000) return;
  if (now - windowStart > 60_000) { windowStart = now; sent = 0; }
  if (++sent > 500) { if (event) lost++; return; }
  heartbeat = now;
  const dropped = Math.min(lost, 100_000); lost -= dropped;
  const operation = async () => {
    try {
      const assertion = await getVercelOidcToken();
      const headers = new Headers();
      for (const [key,value] of Object.entries(req.headers)) if (value !== undefined) headers.set(key, Array.isArray(value) ? value.join(',') : value);
      const webRequest = new Request('https://mefrion.vercel.app/', { headers });
      let country; try { country = geolocation(webRequest).country; } catch { /* optional */ }
      const trace = req.headers['x-vercel-id'];
      const payload = { event: event ? { ...event, id: randomUUID(), country: /^[A-Z]{2}$/.test(country || '') ? country : null, request_id: typeof trace === 'string' && /^[\w:.-]{1,120}$/.test(trace) ? trace : null } : null, address: ipAddress(webRequest) || null, lost: dropped };
      const response = await fetch(ENDPOINT, { method: 'POST', headers: { Authorization: 'Bearer ' + assertion, 'Content-Type': 'application/json' }, body: JSON.stringify(payload), signal: AbortSignal.timeout(3000) });
      if (!response.ok) throw new Error('delivery');
    } catch {
      lost += dropped + (event ? 1 : 0);
      // No tokens, URLs, IPs, request bodies or raw exceptions in runtime logs.
      console.warn(JSON.stringify({ component: 'mefrion.security', event: 'delivery_failed' }));
    }
  };
  waitUntil(operation());
}

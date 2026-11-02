// Server-only classification. Do not persist raw paths, queries, bodies or headers.
export const KINDS = ['secret_probe','path_traversal','injection_probe','auth_denied','access_denied','rate_limited','not_found','method_denied','server_error'];
/** @param {{path?: string, query?: string, status?: number, method?: string, edge?: string|null}} input */
export function classify({ path = '/', query = '', status = 200, method = 'GET', edge = null }) {
  let decoded = (path + '?' + query).slice(0, 8192);
  for (let i = 0; i < 2; i++) { try { decoded = decodeURIComponent(decoded); } catch { break; } }
  let target = canonicalTarget(path, edge);
  let kind, severity = 'info';
  if (/(?:^|\/)\.(?:env(?:\b|\.)|git(?:\/|\b)|aws(?:\/|\b))|(?:^|\/)(?:wp-login\.php|phpmyadmin|actuator\/env)(?:\b|\/)/i.test(decoded)) { kind = 'secret_probe'; severity = 'high'; target = '/[secret-probe]'; }
  else if (/(?:\.\.[\/\\]|(?:%2e){2}(?:%2f|%5c)|\/etc\/passwd|\\windows\\system32)/i.test(decoded)) { kind = 'path_traversal'; severity = 'high'; target = '/[traversal]'; }
  else if (/(?:<script\b|javascript:|onerror\s*=|union\s+(?:all\s+)?select\b|\bor\s+['"]?1['"]?\s*=\s*['"]?1|\bsleep\s*\(|\$\{jndi:)/i.test(decoded)) { kind = 'injection_probe'; severity = 'high'; target = '/[injection]'; }
  else if (status >= 500) { kind = 'server_error'; severity = 'high'; }
  else if (status === 429) { kind = 'rate_limited'; severity = 'medium'; }
  else if (status === 401) { kind = 'auth_denied'; severity = 'low'; }
  else if (status === 403) { kind = 'access_denied'; severity = 'low'; }
  else if (status === 405) { kind = 'method_denied'; severity = 'low'; }
  else if (status === 404) { kind = 'not_found'; severity = 'info'; }
  else return null;
  const outcome = status >= 500 ? 'failed' : status === 429 ? 'limited' : status >= 400 ? 'denied' : 'observed';
  return { kind, severity, outcome, status, target };
}
/** @param {string} path @param {string|null} edge */
export function canonicalTarget(path, edge = null) {
  const functions = ['private-image','private-video','public-image','public-video','shared-page','cloud-worker','stock-worker','asset-ingest','database-backup','offsite-backup','security-collector'];
  if (functions.includes(edge)) return '/functions/' + edge;
  const safe = new Set(['/','/privacy','/terms','/console','/console/config.json','/console/cloud.js','/console/security.js','/console/security.css','/console/security','/healthz']);
  if (path.endsWith('.html')) path = path.slice(0, -5);
  if (path === '/console/') path = '/console';
  if (safe.has(path)) return path;
  if (/^\/cloud-shared\/[0-9a-f-]{36}$/i.test(path)) return '/cloud-shared/:id';
  if (/^\/cloud-development-shared\/[0-9a-f-]{36}$/i.test(path)) return '/cloud-development-shared/:id';
  return '/[unknown]';
}

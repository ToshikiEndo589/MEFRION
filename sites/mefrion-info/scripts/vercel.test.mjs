import assert from 'node:assert/strict';
import test from 'node:test';
import handler, { route } from '../api/site.mjs';

test('public pages and operator assets preserve security headers', async () => {
  for (const path of ['/', '/privacy', '/terms', '/console/', '/console/cloud.js', '/console/config.json']) {
    const response = await route(new Request('https://site.invalid' + path));
    assert.equal(response.status, 200, path);
    assert.equal(response.headers.get('X-Content-Type-Options'), 'nosniff');
    assert.equal(response.headers.get('Cache-Control'), 'no-store');
    if (path.startsWith('/console/')) assert.match(response.headers.get('Content-Security-Policy'), /frame-ancestors 'none'/);
  }
});
test('does not expose files, backup storage, or accept writes', async () => {
  for (const path of ['/.env', '/.git/config', '/worker/index.js', '/internal-backup/health', '/cloud-shared/not-a-uuid']) {
    assert.equal((await route(new Request('https://site.invalid' + path))).status, 404, path);
  }
  assert.equal((await route(new Request('https://site.invalid/privacy', { method: 'POST' }))).status, 405);
});
test('shared page router only contacts allowlisted Supabase origin', async () => {
  const previous = globalThis.fetch;
  const calls = [];
  globalThis.fetch = async (url) => { calls.push(url); return new Response('shared', { status: 200 }); };
  try {
    const response = await route(new Request('https://site.invalid/cloud-shared/11111111-2222-3333-4444-555555555555'));
    assert.equal(response.status, 200);
    assert.equal(await response.text(), 'shared');
    assert.equal(new URL(calls[0]).origin, 'https://pbnimpqrthvznbwewtcf.supabase.co');
  } finally { globalThis.fetch = previous; }
});
test('Vercel rewrite adapter serves routes and HEAD correctly', async () => {
  for (const method of ['GET', 'HEAD']) {
    const res = { headers: {}, setHeader(k, v) { this.headers[k] = v; }, end(body) { this.body = body; } };
    await handler({ url: '/api/site?__mefrion_path=privacy', method }, res);
    assert.equal(res.statusCode, 200);
    assert.equal(method === 'HEAD' ? res.body : res.body.includes('MEFRION'), method === 'HEAD' ? undefined : true);
  }
  const res = { setHeader() {}, end() {} };
  await handler({ url: '/api/site?__mefrion_path=privacy&__mefrion_path=terms', method: 'GET' }, res);
  assert.equal(res.statusCode, 400);
});

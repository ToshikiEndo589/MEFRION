import assert from 'node:assert/strict';
import test from 'node:test';
import { route } from '../api/site.mjs';
import { adsHandler } from '../api/x-ads.mjs';

const env = {
  VERCEL_ENV: 'production', X_ADS_ACCOUNT_ID: 'test123', X_ADS_CURRENCY: 'JPY',
  X_ADS_CONSUMER_KEY: 'test-key', X_ADS_CONSUMER_SECRET: 'test-consumer-secret',
  X_ADS_ACCESS_TOKEN: 'test-token', X_ADS_ACCESS_TOKEN_SECRET: 'test-token-secret',
  X_ADS_MAX_TOTAL_MICROS: '5000000000', X_ADS_ENABLE_ACTIVATION: 'true',
};
const campaign = {
  id: 'campaign1', name: 'MEFRION · X', currency: 'JPY', entity_status: 'PAUSED',
  daily_budget_amount_local_micro: 1000000000,
  total_budget_amount_local_micro: 5000000000,
  updated_at: '2026-11-08T03:00:00Z',
};
const activation = {
  id: campaign.id, status: 'ACTIVE', currency: 'JPY',
  dailyMicros: 1000000000, totalMicros: 5000000000, updatedAt: campaign.updated_at,
};
const request = {
  url: '/ads/api/x', method: 'GET',
  headers: {
    authorization: 'Bearer example.valid.operator-session',
    origin: 'https://mefrion.vercel.app', 'content-type': 'application/json',
  },
};

async function invoke(req, { permissions = { publish: true }, settings = env, current = campaign } = {}) {
  const calls = [];
  const res = { setHeader() {}, end(body) { this.body = JSON.parse(body); } };
  const handler = adsHandler(settings, async (input, options) => {
    const url = new URL(input);
    calls.push({ url, method: options.method, authorization: options.headers.Authorization });
    if (url.hostname.endsWith('.supabase.co')) {
      if (url.pathname.endsWith('/mefrion_operator_alert_status')) return new Response('null', { status: 403 });
      return Response.json(permissions);
    }
    if (options.method === 'PUT') {
      return Response.json({ data: { ...current, entity_status: url.searchParams.get('entity_status') } });
    }
    const data = url.pathname.endsWith('/campaigns') ? [current] : current;
    return Response.json({ data });
  }, 'x', () => {});
  await handler(req, res);
  return { ...res, calls };
}

test('Ads serves a separate, non-indexed page with MFA login', async () => {
  const response = await route(new Request('https://site.invalid/ads'));
  assert.equal(response.status, 200);
  assert.match(response.headers.get('X-Robots-Tag'), /noindex/);
  assert.match(response.headers.get('Content-Security-Policy'), /frame-ancestors 'none'/);
  const page = await response.text();
  assert.match(page, /id="ads-workspace" hidden/);
  assert.match(page, /id="mfa"/);
  assert.doesNotMatch(page, /id="overview-section"/);
});

test('anonymous and non-admin sessions cannot reach X', async () => {
  const anonymous = await invoke({ ...request, headers: {} });
  assert.equal(anonymous.statusCode, 401);
  assert.equal(anonymous.calls.length, 0);
  const staff = await invoke(request, { permissions: { edit: true, publish: false } });
  assert.equal(staff.statusCode, 403);
  assert.equal(staff.calls.length, 2);
  const badOrigin = await invoke({
    ...request, method: 'POST', body: activation,
    headers: { ...request.headers, origin: 'https://untrusted.invalid' },
  });
  assert.equal(badOrigin.statusCode, 403);
  assert.equal(badOrigin.calls.length, 0);
});

test('unconfigured and preview environments cannot touch real campaigns', async () => {
  for (const settings of [{}, { ...env, VERCEL_ENV: 'preview' }]) {
    const reply = await invoke(request, { settings });
    assert.deepEqual(reply.body, { connected: false });
    assert.equal(reply.calls.length, 1);
  }
});

test('activation rechecks the campaign and sends the reviewed amounts to the configured account', async () => {
  const reply = await invoke({ ...request, method: 'POST', body: activation });
  assert.equal(reply.statusCode, 200);
  assert.equal(reply.body.item.status, 'ACTIVE');
  assert.deepEqual(reply.calls.map(call => call.method), ['POST', 'GET', 'PUT']);
  const write = reply.calls[2];
  assert.equal(write.url.origin, 'https://ads-api.x.com');
  assert.equal(write.url.pathname, '/12/accounts/test123/campaigns/campaign1');
  assert.match(write.authorization, /^OAuth /);
  assert.equal(write.url.searchParams.get('total_budget_amount_local_micro'), '5000000000');
  assert.equal(write.url.searchParams.get('daily_budget_amount_local_micro'), '1000000000');
  assert.doesNotMatch(JSON.stringify(reply.body), /test-consumer-secret|test-token-secret/);
});

test('changed budgets, expired review, disabled activation and out-of-cap campaigns cannot start', async () => {
  for (const overrides of [
    { current: { ...campaign, daily_budget_amount_local_micro: 2000000000 } },
    { current: { ...campaign, updated_at: '2026-11-08T03:01:00Z' } },
    { settings: { ...env, X_ADS_ENABLE_ACTIVATION: 'false' } },
    { settings: { ...env, X_ADS_MAX_TOTAL_MICROS: '4999999999' } },
  ]) {
    const reply = await invoke({ ...request, method: 'POST', body: activation }, overrides);
    assert.equal(reply.statusCode, 409);
    assert.ok(reply.calls.every(call => call.method !== 'PUT'));
  }
});

test('pausing is available when activation is disabled', async () => {
  const reply = await invoke({ ...request, method: 'POST', body: { ...activation, status: 'PAUSED' } }, {
    current: { ...campaign, entity_status: 'ACTIVE' },
    settings: { ...env, X_ADS_ENABLE_ACTIVATION: 'false' },
  });
  assert.equal(reply.statusCode, 200);
  assert.equal(reply.calls[2].url.searchParams.get('entity_status'), 'PAUSED');
  assert.equal(reply.calls[2].url.searchParams.has('total_budget_amount_local_micro'), false);
});

test('X uses campaign analytics, splits the date range into at most seven-day calls, and preserves gaps', async () => {
  const calls = [];
  const res = { setHeader() {}, end(body) { this.body = JSON.parse(body); } };
  const handler = adsHandler(env, async input => {
    const url = new URL(input);
    if (url.hostname.endsWith('.supabase.co')) return Response.json({ publish: true });
    if (url.pathname.endsWith('/campaigns')) return Response.json({ data: [campaign], next_cursor: 'more' });
    calls.push(url);
    return Response.json({ data: [{ id: campaign.id, id_data: [{ segment: null, metrics: {
      billed_charge_local_micro: [1000000], impressions: [12], url_clicks: [0],
    } }] }] });
  });
  await handler({ ...request, url: '/ads/api/x?view=report&start=2026-10-20&end=2026-10-27' }, res);
  assert.equal(res.statusCode, 200);
  assert.equal(res.body.partial, true);
  assert.equal(calls.length, 2);
  assert.ok(calls.every(url => url.pathname === '/12/stats/accounts/test123' &&
    url.searchParams.get('placement') === 'ALL_ON_TWITTER'));
  assert.equal(calls[0].searchParams.get('end_time'), calls[1].searchParams.get('start_time'));
  assert.equal(res.body.rows[0].clicks, 0);
  assert.equal(res.body.rows[1].clicks, null);
});

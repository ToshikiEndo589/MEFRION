import assert from 'node:assert/strict';
import { createHash, createHmac, generateKeyPairSync } from 'node:crypto';
import test from 'node:test';
import { adsHandler } from '../api/x-ads.mjs';
import { appleAdsHandler } from '../api/apple-ads.mjs';
import { aggregate, csvCell, diagnostics, parseAppleFile, appleColumns, previousPeriod, metricChange } from '../ads/insights.js';
import { reportQuery } from '../ads/report.mjs';
import { campaignDownloadDays, collectAppleCampaigns } from '../analytics/apple.mjs';

const account = '12345';
const id = '23456';
const updatedAt = '2026-11-06 10:00:00';
const env = {
  VERCEL_ENV: 'production',
  META_ADS_ACCOUNT_ID: account, META_ADS_ACCESS_TOKEN: 'meta-secret', META_ADS_API_VERSION: 'v25.0',
  META_ADS_ENABLE_ACTIVATION: 'true', META_ADS_CURRENCY: 'JPY', META_ADS_MAX_TOTAL_MICROS: '2000000000',
  TIKTOK_ADS_ADVERTISER_ID: account, TIKTOK_ADS_ACCESS_TOKEN: 'tiktok-secret',
  TIKTOK_ADS_ENABLE_ACTIVATION: 'true', TIKTOK_ADS_CURRENCY: 'JPY', TIKTOK_ADS_MAX_TOTAL_MICROS: '2000000000',
};
const headers = {
  origin: 'https://mefrion.vercel.app', authorization: 'Bearer mock.verified.session.00000', 'content-type': 'application/json',
};
const dates = 'start=2026-11-05&end=2026-11-06';
const change = { id, updatedAt, status: 'ACTIVE', currency: 'JPY', totalMicros: 2000000000 };

async function invoke(provider, scenario, { query = '', body, permissions = { publish: true }, moderator = false, userId, settings = env } = {}) {
  const calls = [], audit = [];
  const response = { setHeader() {}, end(value) { this.body = JSON.parse(value); } };
  const fetcher = async (input, options) => {
    const url = new URL(input);
    calls.push({ url, options });
    if (url.hostname.endsWith('.supabase.co')) {
      if (url.pathname === '/auth/v1/user') {
        assert.equal(options.headers.Authorization, headers.authorization);
        assert.equal(options.redirect, 'error');
        return userId ? Response.json({ id: userId }) : new Response('{}', { status: 401 });
      }
      if (url.pathname.endsWith('/mefrion_operator_alert_status')) {
        return new Response('null', { status: moderator ? 200 : 403 });
      }
      return Response.json(permissions);
    }
    const result = await scenario(url, options);
    return result instanceof Response ? result : Response.json(result);
  };
  const handler = provider === 'apple' ? appleAdsHandler(settings, fetcher) : adsHandler(settings, fetcher, provider, entry => audit.push(JSON.parse(entry)));
  await handler({ method: body ? 'POST' : 'GET', url: '/ads/api/' + provider + '?' + query, headers, body }, response);
  return { ...response, calls, audit };
}

function metaScenario({ platforms = ['instagram'], row = {}, more = false } = {}) {
  return (url, options) => {
    const path = url.pathname.replace(/^\/v25\.0\//, '');
    if (options.method === 'POST') return { success: true };
    if (path === 'act_' + account) return { account_id: account, currency: 'JPY', timezone_name: 'Asia/Tokyo' };
    if (path === id) return { id, account_id: account, name: 'Dog', status: 'PAUSED', updated_time: updatedAt,
      daily_budget: '0', lifetime_budget: '2000', ...row };
    if (path === id + '/adsets') return {
      data: [{ status: 'ACTIVE', targeting: { publisher_platforms: platforms, instagram_positions: ['story'] } }],
      ...(more ? { paging: { next: 'https://untrusted.invalid/' } } : {}),
    };
    if (path.endsWith('/insights')) {
      assert.equal(url.searchParams.get('breakdowns'), 'publisher_platform');
      assert.equal(url.searchParams.get('level'), 'adset');
      return { data: ['instagram', 'facebook'].map(publisher_platform => ({
        publisher_platform, adset_id: id, adset_name: 'Story', date_start: '2026-11-05', account_currency: 'JPY',
        spend: '123.5', impressions: '1245', inline_link_clicks: '21',
        actions: [{ action_type: 'mobile_app_install', value: '3' }, { action_type: 'link_click', value: '500' }],
      })) };
    }
    throw Error('unexpected ' + path);
  };
}

test('reporting requires an operator role and preview has no live provider access', async () => {
  for (const provider of ['instagram', 'tiktok', 'apple']) {
    const unexpected = () => assert.fail('provider request');
    const staff = await invoke(provider, unexpected, { permissions: { publish: false } });
    assert.equal(staff.statusCode, 403);
    assert.equal(staff.calls.length, 2);
    const preview = await invoke(provider, unexpected, { settings: { ...env, VERCEL_ENV: 'preview' } });
    assert.equal(preview.statusCode, 200);
    assert.equal(preview.calls.length, 1);
  }
});

test('a verified moderator can view Ads, but cannot change delivery', async () => {
  const settings = { VERCEL_ENV: 'production' };
  const moderator = { permissions: { publish: false }, moderator: true, settings };
  for (const provider of ['x', 'instagram', 'tiktok', 'apple']) {
    const unexpected = () => assert.fail('provider request');
    const report = await invoke(provider, unexpected, moderator);
    assert.equal(report.statusCode, 200);
    assert.match(report.calls[1].url.pathname, /mefrion_operator_alert_status$/);
    if (provider === 'apple') continue;
    const write = await invoke(provider, unexpected, { ...moderator, body: change });
    assert.equal(write.statusCode, 403);
    assert.equal(write.calls.length, 1);
  }
});

test('only the named, currently authorized operator can review and change Instagram delivery', async () => {
  const userId = '11111111-2222-4333-8444-555555555555';
  const settings = { ...env, META_ADS_OPERATOR_USER_ID: userId };
  const operator = { permissions: { publish: false }, moderator: true, userId, settings };
  const reviewed = await invoke('instagram', metaScenario(), { ...operator, query: 'view=review&id=' + id });
  assert.equal(reviewed.statusCode, 200);
  assert.equal(reviewed.body.item.canActivate, true);
  const write = await invoke('instagram', metaScenario(), { ...operator, body: change });
  assert.equal(write.statusCode, 200);
  assert.equal(write.calls.at(-1).options.body, 'status=ACTIVE');
  const never = () => assert.fail('provider must not be called');
  for (const [options, code] of [
    [{ userId: 'other' }, 403], [{ userId: undefined }, 401], [{ moderator: false }, 403],
    [{ settings: { ...settings, VERCEL_ENV: 'preview' } }, 403],
  ]) {
    const denied = await invoke('instagram', never, { ...operator, ...options, body: change });
    assert.equal(denied.statusCode, code);
  }
  for (const provider of ['x', 'tiktok']) {
    const denied = await invoke(provider, never, { ...operator, body: change });
    assert.equal(denied.statusCode, 403);
    assert.equal(denied.calls.length, 1);
  }
});

test('Meta app secret proof stays server side and is sent only to Meta', async () => {
  const settings = { ...env, META_ADS_APP_SECRET: 'mock-app-secret' };
  const expected = createHmac('sha256', settings.META_ADS_APP_SECRET).update(settings.META_ADS_ACCESS_TOKEN).digest('hex');
  const scenario = metaScenario();
  const reply = await invoke('instagram', (url, options) => {
    assert.equal(url.origin, 'https://graph.facebook.com');
    assert.equal(options.headers.Authorization, 'Bearer ' + settings.META_ADS_ACCESS_TOKEN);
    const parameters = options.method === 'POST' ? new URLSearchParams(options.body) : url.searchParams;
    assert.equal(parameters.get('appsecret_proof'), expected);
    assert.doesNotMatch(url.href, /mock-app-secret|meta-secret/);
    return scenario(url, options);
  }, { settings, body: change });
  assert.equal(reply.statusCode, 200);
  assert.doesNotMatch(JSON.stringify([reply.body, reply.audit]), new RegExp('mock-app-secret|meta-secret|' + expected));
});

test('Instagram reports strictly exclude Facebook spend and map only the expected app install action', async () => {
  const reply = await invoke('instagram', metaScenario(), { query: 'view=report&level=adgroup&' + dates });
  assert.equal(reply.statusCode, 200);
  assert.deepEqual(reply.body.rows, [{
    id, name: 'Story', date: '2026-11-05', spendMicros: 123500000, impressions: 1245, clicks: 21,
    installs: 3, results: null, videoViews: null, video25: null, video50: null, video75: null, videoComplete: null,
  }]);
  assert.ok(reply.calls.slice(1).every(call => !call.url.href.includes('meta-secret') && call.options.redirect === 'error'));
});

test('Instagram falls back to core placement data when advanced metrics are rejected', async () => {
  const scenario = metaScenario();
  const reply = await invoke('instagram', (url, options) => {
    if (url.searchParams.get('fields')?.includes('video_play_actions')) return new Response('{}', { status: 400 });
    return scenario(url, options);
  }, { query: 'view=report&level=adgroup&' + dates });
  assert.equal(reply.statusCode, 200);
  assert.equal(reply.body.limitedMetrics, true);
  assert.equal(reply.body.rows.length, 1);
});

test('Instagram activation fails closed on mixed placements, truncated inspection, external ownership or changed budgets', async () => {
  for (const options of [
    { platforms: ['instagram', 'facebook'] },
    { platforms: [] },
    { more: true },
    { row: { account_id: '9999' } },
    { row: { lifetime_budget: '1000' } },
    { row: { updated_time: '2026-11-06 11:00:00' } },
  ]) {
    const reply = await invoke('instagram', metaScenario(options), { body: change });
    assert.ok([404, 409].includes(reply.statusCode));
    assert.equal(reply.calls.filter(call => call.url.hostname === 'graph.facebook.com' && call.options.method === 'POST').length, 0);
  }
  const allowed = await invoke('instagram', metaScenario(), { body: change });
  assert.equal(allowed.statusCode, 200);
  assert.equal(allowed.calls.at(-1).url.pathname, '/v25.0/' + id);
  assert.equal(allowed.calls.at(-1).options.body, 'status=ACTIVE');
  assert.deepEqual(allowed.audit, [{ event: 'ads_delivery_change', provider: 'instagram', campaignId: id, requestedStatus: 'ACTIVE', outcome: 'confirmed' }]);
});

function tiktokScenario(mode = 'BUDGET_MODE_TOTAL', smart = false, fail = false) {
  let state = 'DISABLE';
  return (url, options) => {
    const ok = data => ({ code: 0, data });
    const paged = (list, pages = 1) => ok({ list, page_info: { total_page: pages } });
    assert.equal(options.headers['Access-Token'], 'tiktok-secret');
    if (url.pathname.endsWith('/advertiser/info/')) return ok({ list: [{ advertiser_id: account, currency: 'JPY', timezone: 'Asia/Tokyo' }] });
    if (url.pathname.endsWith('/campaign/get/')) return paged([{
      campaign_id: id, advertiser_id: account, operation_status: state, modify_time: updatedAt,
      budget: 2000, budget_mode: mode, is_smart_performance_campaign: smart, campaign_type: 'REGULAR_CAMPAIGN',
    }]);
    if (url.pathname.endsWith('/campaign/status/update/')) {
      assert.deepEqual(JSON.parse(options.body), { advertiser_id: account, campaign_ids: [id], operation_status: 'ENABLE' });
      if (fail) return { code: 40001, message: 'token or detailed upstream error' };
      state = 'ENABLE';
      return ok({ campaign_ids: [id] });
    }
    if (url.pathname.endsWith('/report/integrated/get/')) {
      assert.deepEqual(JSON.parse(url.searchParams.get('dimensions')), ['ad_id', 'stat_time_day']);
      const page = url.searchParams.get('page');
      return paged([{
        dimensions: { ad_id: id + page, stat_time_day: '2026-11-05 00:00:00' },
        metrics: { ad_name: 'Kitten', spend: '20.5', impressions: '100', clicks: '2', conversion: '1', app_install: '-', video_views_p100: '5' },
      }], 5);
    }
    throw Error('unexpected request');
  };
}

test('TikTok paginates reports, preserves unavailable installs and marks truncated coverage', async () => {
  const reply = await invoke('tiktok', tiktokScenario(), { query: 'view=report&level=ad&' + dates });
  assert.equal(reply.statusCode, 200);
  assert.equal(reply.body.partial, true);
  assert.equal(reply.body.rows.length, 3);
  assert.equal(reply.body.rows[0].installs, null);
  assert.equal(reply.body.rows[0].videoComplete, 5);
  assert.equal(reply.body.rows[0].spendMicros, 20500000);
});

test('TikTok only activates a regular campaign with a verified lifetime budget and never retries ambiguous writes', async () => {
  for (const scenario of [tiktokScenario('BUDGET_MODE_DAY'), tiktokScenario('BUDGET_MODE_TOTAL', true)]) {
    const reply = await invoke('tiktok', scenario, { body: change });
    assert.equal(reply.statusCode, 409);
    assert.equal(reply.calls.filter(call => call.url.pathname.endsWith('/campaign/status/update/')).length, 0);
  }
  const allowed = await invoke('tiktok', tiktokScenario(), { body: change });
  assert.equal(allowed.statusCode, 200);
  assert.equal(allowed.body.item.status, 'ACTIVE');
  const unconfirmed = await invoke('tiktok', tiktokScenario('BUDGET_MODE_TOTAL', false, true), { body: change });
  assert.deepEqual(unconfirmed.body, { code: 'write_unconfirmed' });
  assert.equal(unconfirmed.audit[0].outcome, 'unconfirmed');
  assert.equal(unconfirmed.calls.filter(call => call.url.pathname.endsWith('/campaign/status/update/')).length, 1);
});

test('date validation rejects rollover, future and oversized ranges', () => {
  const now = new Date('2026-11-07T16:00:00Z');
  for (const params of ['start=2026-02-30&end=2026-03-01', 'start=2026-10-01&end=2026-11-01', 'end=2026-11-08']) {
    assert.throws(() => reportQuery(new URLSearchParams(params), now), /invalid_dates/);
  }
  assert.deepEqual(reportQuery(new URLSearchParams(dates), now), { start: '2026-11-05', end: '2026-11-06', level: 'campaign' });
});

test('rollups use weighted rates and suppress ratios with missing inputs', () => {
  const complete = { id, spendMicros: 2e6, impressions: 100, clicks: 10, installs: 0, results: 1, videoComplete: 8 };
  const [rollup] = aggregate([complete, { ...complete, impressions: 900, clicks: 10, installs: null }], row => row.id);
  assert.equal(rollup.ctr, 2);
  assert.equal(rollup.cpc, 200000);
  assert.equal(rollup.installs, 0);
  assert.equal(rollup.missing.installs, 1);
  assert.equal(rollup.cpi, null);
  const measured = aggregate([{ ...complete, impressions: 1500, clicks: 2, installs: 2 }], row => row.id);
  assert.deepEqual(diagnostics(measured, 1000), []);
  assert.equal(csvCell(' =SUM(A1:A10)'), '"\' =SUM(A1:A10)"');
  assert.deepEqual(previousPeriod('2026-11-01', '2026-11-03'), { start: '2026-10-29', end: '2026-10-31' });
  assert.equal(metricChange(2.5, 2, true), 0.5);
  assert.equal(metricChange(0, 0), null);
  assert.equal(csvCell('Quotes "inside"'), '"Quotes ""inside"""');
});

test('Apple CSV accepts privacy gaps and rejects duplicate source attribution and invalid retention', () => {
  const head = appleColumns.join(',');
  const row = 'instagram,123,campaign1,2026-11-05,2026-11-06,10,,20,';
  assert.deepEqual(parseAppleFile(head + '\n' + row)[0].rates, [null, 20, null]);
  assert.throws(() => parseAppleFile(head + '\n' + row + '\n' + row.replace('123', '999')), /重複/);
  assert.throws(() => parseAppleFile(head + '\n' + row.replace(',20,', ',120,')), /継続率/);
});

test('Apple API aggregates official first-time campaign download counts and excludes suppressed campaigns', async () => {
  const header = 'App Apple Identifier\tDate\tDownload Type\tCampaign\tCounts\n';
  const tsv = header + [
    '6825337314\t2026-11-05\tFirst-time Download\tinstagram_test\t7',
    '6825337314\t2026-11-05\tRedownload\tinstagram_test\t80',
    '6825337314\t2026-11-06\tFirst-time Download\tprivacy_limited\t4',
    '1234\t2026-11-06\tFirst-time Download\tother_app\t12',
  ].join('\n');
  assert.equal(campaignDownloadDays(tsv, '2026-11-05', '2026-11-06').get('2026-11-05').get('instagram_test'), 7);
  const { privateKey } = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
  const settings = { ASC_KEY_ID: 'TEST', ASC_ISSUER_ID: 'test', ASC_PRIVATE_KEY: privateKey.export({ format: 'pem', type: 'pkcs8' }) };
  const rows = value => Response.json({ data: [value] });
  const fetcher = async (input, options) => {
    const url = new URL(input);
    assert.equal(options.redirect, 'error');
    if (url.hostname === 'downloads.apple.com') {
      assert.equal(options.headers, undefined);
      return new Response(tsv);
    }
    if (url.pathname.endsWith('/analyticsReportRequests')) return rows({ id: 'request', attributes: { accessType: 'ONGOING' } });
    if (url.pathname.endsWith('/reports')) return rows({ id: 'report', attributes: { name: 'App Store Downloads Detailed' } });
    if (url.pathname.endsWith('/instances')) return rows({ id: 'instance', attributes: { processingDate: '2026-11-06' } });
    if (url.pathname.endsWith('/segments')) return rows({
      id: 'segment', attributes: { url: 'https://downloads.apple.com/example.tsv', checksum: createHash('sha256').update(tsv).digest('hex') },
    });
    throw Error('unexpected');
  };
  const result = await collectAppleCampaigns(settings, { start: '2026-11-05', end: '2026-11-06' }, fetcher);
  assert.deepEqual(result, { status: 'ok', days: ['2026-11-05', '2026-11-06'], rows: [{ campaign: 'instagram_test', downloads: 7 }] });
});

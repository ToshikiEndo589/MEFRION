import assert from 'node:assert/strict';
import test from 'node:test';
import { instagramClient, instagramConfig } from '../ads/instagram.mjs';
import { creativeToken, estimateSpend, evaluateExperiment, experimentWindow, variantLink } from '../ads/experiments.js';
import { creativeArchive } from '../ads/experiment-ui.js';
import site from '../worker/index.js';

const base = 'https://apps.apple.com/jp/app/mefrion/id6825337314?pt=12&ct=base&mt=8';
const url = token => variantLink(base, token);
const study = { id: '100', name: 'Photo test', business: { id: '200' }, type: 'SPLIT_TEST_V2',
  start_time: '2026-10-01T00:00:00+09:00', end_time: '2026-10-03T00:00:00+09:00' };
const env = { VERCEL_ENV: 'production', META_ADS_ACCOUNT_ID: '300', META_ADS_BUSINESS_ID: '200',
  META_ADS_ACCESS_TOKEN: 'fixture-only', META_ADS_API_VERSION: 'v25.0' };
const latest = Date.parse('2026-10-08T00:00:00Z');

function fixture({ wrongOwner, mixed, repeatedToken, unequal, sameImage, partial } = {}) {
  const calls = [];
  const fetcher = async (input, options) => {
    const { pathname, origin } = new URL(input);
    assert.equal(origin, 'https://graph.facebook.com');
    assert.equal(options.method, 'GET');
    calls.push(pathname);
    if (pathname.endsWith('/100')) return Response.json(study);
    if (pathname.endsWith('/act_300')) return Response.json({ account_id: '300', timezone_name: 'Asia/Tokyo', currency: 'JPY' });
    if (pathname.endsWith('/100/cells')) return Response.json({ data: [1, 2].map(i => ({ ad_ids: [String(400 + i)], treatment_percentage: unequal ? (i === 1 ? 60 : 40) : 50 })) });
    const id = pathname.split('/')[2];
    if (pathname.endsWith('/insights')) {
      assert.equal(new URL(input).searchParams.get('time_range'), '{"since":"2026-10-01","until":"2026-10-02"}');
      return Response.json({ data: [{ ad_id: id, publisher_platform: 'instagram', account_currency: 'JPY', spend: '3000', impressions: '32000', inline_link_clicks: '325' }],
        ...(partial ? { paging: { next: 'https://other.example' } } : {}) });
    }
    return Response.json({ id, name: id, account_id: wrongOwner && id === '402' ? '999' : '300', adset_id: '500',
      adset: { targeting: { publisher_platforms: mixed ? ['instagram', 'facebook'] : ['instagram'], instagram_positions: ['story'] } },
      creative: { object_story_spec: { link_data: { link: url('variant_' + (repeatedToken ? 'a' : id)), image_hash: sameImage ? 'same' : id,
        message: 'One copy for both ads', name: 'Same', call_to_action: { type: 'INSTALL_MOBILE_APP' } } } } });
  };
  return { client: instagramClient(instagramConfig(env), fetcher), calls };
}

test('only a balanced, scoped Meta study with distinct Apple links can be used for judging', async () => {
  const result = await fixture().client.experiment('100', latest);
  assert.equal(result.comparable, true);
  assert.equal(result.metaEnd, '2026-10-02');
  assert.equal(result.appleStart, '2026-09-30');
  assert.equal(result.appleEnd, '2026-10-03');
  assert.equal(result.arms[0].spendMicros, 3000000000);
  for (const [options, code] of [[{ repeatedToken: true }, 'tracking'], [{ unequal: true }, 'split'], [{ sameImage: true }, 'creative']]) {
    const excluded = await fixture(options).client.experiment('100', latest);
    assert.equal(excluded.comparable, false);
    assert.ok(excluded.issues.includes(code));
  }
  for (const [options, error] of [[{ wrongOwner: true }, /experiment_missing/], [{ mixed: true }, /placement_blocked/]]) {
    const refused = fixture(options);
    await assert.rejects(refused.client.experiment('100', latest), error);
    assert.ok(refused.calls.every(path => !path.endsWith('/insights')));
  }
  const partial = await fixture({ partial: true }).client.experiment('100', latest);
  assert.equal(partial.arms[0].spendMicros, undefined);
});

test('judging waits for final and visible counts and distinguishes strong from inconclusive lifts', async () => {
  const input = await fixture().client.experiment('100', latest);
  const apple = { status: 'ok', days: ['2026-09-30', '2026-10-01', '2026-10-02', '2026-10-03'],
    rows: [{ campaign: 'variant_401', downloads: 90 }, { campaign: 'variant_402', downloads: 30 }] };
  assert.equal(evaluateExperiment(input, apple, Date.parse('2026-10-01T00:00Z')).state, 'running');
  assert.equal(evaluateExperiment(input, apple, Date.parse('2026-10-04T00:00Z')).state, 'settling');
  assert.equal(evaluateExperiment(input, { ...apple, days: apple.days.slice(1) }, latest).state, 'apple_pending');
  const privateRow = evaluateExperiment(input, { ...apple, rows: apple.rows.slice(0, 1) }, latest);
  assert.equal(privateRow.state, 'insufficient');
  assert.equal(privateRow.arms[1].downloads, null);
  const close = { ...apple, rows: [apple.rows[0], { campaign: 'variant_402', downloads: 84 }] };
  assert.equal(evaluateExperiment(input, close, latest).state, 'inconclusive');
  assert.equal(evaluateExperiment(input, apple, latest).winner, '401');
  assert.equal(experimentWindow('2026-10-01', '2026-10-12', 'Asia/Tokyo'), null);
  assert.ok(estimateSpend(100, 5, .2).total > estimateSpend(100, 2, .2).total);
  assert.ok(estimateSpend(100, 2, .1).total > estimateSpend(100, 2, .2).total);
});

test('generated links preserve provider and reject overrides or foreign App Store targets', () => {
  assert.deepEqual(creativeToken({ link_url: url('test_a') }), { token: 'test_a', provider: '12' });
  assert.equal(creativeToken({ link_url: url('test_a'), url_tags: '%63t=other' }), null);
  assert.equal(creativeToken({ link_url: url('test_a'), object_story_spec: { link_data: { link: url('test_b') } } }), null);
  assert.throws(() => variantLink(base.replace('6825337314', '9999'), 'test_a'));
  assert.throws(() => variantLink(base + '&pt=99', 'test_a'));
});

test('Ads serves the experiment UI and produces a valid ZIP structure', async () => {
  for (const path of ['/ads', '/ads/experiments.js', '/ads/experiment-ui.js']) {
    const response = await site.fetch(new Request('https://mefrion.vercel.app' + path));
    assert.equal(response.status, 200);
    assert.equal(response.headers.get('X-Robots-Tag'), 'noindex, nofollow');
    if (path === '/ads') assert.match(await response.text(), /広告クリエイティブ実験室/);
  }
  const zip = Buffer.from(await (await creativeArchive([['links.csv', new Blob(['123456789'])]])).arrayBuffer());
  assert.equal(zip.readUInt32LE(0), 0x04034b50);
  assert.equal(zip.readUInt32LE(14), 0xcbf43926);
  assert.equal(zip.readUInt32LE(zip.length - 22), 0x06054b50);
  assert.equal(zip.readUInt32LE(zip.readUInt32LE(zip.length - 6)), 0x02014b50);
});

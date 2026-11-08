import site from '../worker/index.js';
import { AdsError, xAdsClient, xAdsConfig } from '../ads/x-ads.mjs';
import { instagramClient, instagramConfig } from '../ads/instagram.mjs';
import { tiktokClient, tiktokConfig } from '../ads/tiktok.mjs';
import { reportQuery } from '../ads/report.mjs';

const providers = {
  x: [xAdsConfig, xAdsClient], instagram: [instagramConfig, instagramClient], tiktok: [tiktokConfig, tiktokClient],
};

export async function authorize(headers, fetcher, change = false, instagramOperatorId = null) {
  const bearer = headers?.authorization;
  if (typeof bearer !== 'string' || !/^Bearer [\w.-]{20,8192}$/.test(bearer)) {
    throw new AdsError(401, 'login_required');
  }
  const config = await (await site.fetch(new Request('https://mefrion.vercel.app/console/config.json'))).json();
  const rpc = name => fetcher(config.url + '/rest/v1/rpc/' + name, {
    method: 'POST',
    headers: { Authorization: bearer, apikey: config.anon_key, 'Content-Type': 'application/json' },
    body: '{}',
    redirect: 'error',
    signal: AbortSignal.timeout(5000),
  });
  const check = response => {
    if (response.status === 401) throw new AdsError(401, 'login_required');
    if (!response.ok && response.status !== 403) throw new AdsError(503, 'auth_unavailable');
  };
  const permissions = await rpc('mefrion_seed_permissions');
  check(permissions);
  if (permissions.ok && (await permissions.json())?.publish === true) return true;
  if (change && !instagramOperatorId) throw new AdsError(403, 'admin_required');

  // This lightweight read checks the active operator role, allowlisted
  // identity, current session and verified MFA through require_moderator.
  const operator = await rpc('mefrion_operator_alert_status');
  check(operator);
  if (!operator.ok) throw new AdsError(403, 'operator_required');
  if (instagramOperatorId) {
    const user = await fetcher(config.url + '/auth/v1/user', {
      method: 'GET', headers: { Authorization: bearer, apikey: config.anon_key },
      redirect: 'error', signal: AbortSignal.timeout(5000),
    });
    check(user);
    if (user.ok && (await user.json())?.id === instagramOperatorId) return true;
  }
  if (change) throw new AdsError(403, 'admin_required');
  return false;
}

export function adsHandler(env = process.env, fetcher = fetch, provider = 'x', audit = console.info) {
  const [readConfig, createClient] = providers[provider];
  // Do not grant the Instagram operator broader console, X or TikTok powers.
  const instagramOperatorId = provider === 'instagram' && env.VERCEL_ENV === 'production' &&
    /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/.test(env.META_ADS_OPERATOR_USER_ID || '')
    ? env.META_ADS_OPERATOR_USER_ID : null;
  return async (req, res) => {
    res.setHeader('Cache-Control', 'no-store');
    res.setHeader('Content-Type', 'application/json; charset=utf-8');
    res.setHeader('X-Content-Type-Options', 'nosniff');
    res.setHeader('X-Robots-Tag', 'noindex, nofollow');
    const send = (status, body) => { res.statusCode = status; res.end(JSON.stringify(body)); };
    try {
      if (!['GET', 'POST'].includes(req.method)) throw new AdsError(405, 'method_not_allowed');
      const change = req.method === 'POST';
      if (change && (req.headers?.origin !== 'https://mefrion.vercel.app' ||
          !/^application\/json(?:;|$)/i.test(req.headers?.['content-type'] || ''))) {
        throw new AdsError(403, 'origin_denied');
      }
      const canManage = await authorize(req.headers, fetcher, change, instagramOperatorId);
      const config = readConfig(env);
      if (!config) {
        if (change) throw new AdsError(503, 'provider_not_connected');
        return send(200, { connected: false });
      }
      const client = createClient(config, fetcher);
      if (change) {
        if (typeof req.body === 'string' && req.body.length > 8192) throw new AdsError(400, 'bad_request');
        const input = typeof req.body === 'string' ? JSON.parse(req.body) : req.body;
        const record = outcome => audit(JSON.stringify({
          event: 'ads_delivery_change', provider, campaignId: input.id, requestedStatus: input.status, outcome,
        }));
        let item;
        try {
          item = await client.changeStatus(input);
        } catch (error) {
          if (error instanceof AdsError && error.message === 'write_unconfirmed') record('unconfirmed');
          throw error;
        }
        record('confirmed');
        return send(200, { accountId: config.accountId ?? config.account, item });
      }
      const params = new URL(req.url, 'https://mefrion.vercel.app').searchParams;
      const action = params.get('view') || 'campaigns';
      if (action === 'report') {
        const query = reportQuery(params);
        const report = await client.report(query);
        return send(200, { connected: true, ...query, ...report, fetchedAt: new Date().toISOString() });
      }
      if (action === 'review' && client.review) {
        if (!canManage) throw new AdsError(403, 'admin_required');
        return send(200, { item: await client.review(params.get('id')) });
      }
      if (action !== 'campaigns') throw new AdsError(400, 'bad_request');
      const cursor = params.get('cursor');
      if (cursor && cursor.length > 500) throw new AdsError(400, 'bad_request');
      return send(200, { connected: true, ...await client.list(cursor), canManage });
    } catch (error) {
      if (error instanceof SyntaxError) return send(400, { code: 'bad_request' });
      if (error instanceof AdsError) return send(error.status, { code: error.message });
      return send(503, { code: 'service_unavailable' });
    }
  };
}

export default adsHandler();

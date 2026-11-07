import { createHmac, randomBytes } from 'node:crypto';

const apiOrigin = 'https://ads-api.x.com';
const idPattern = /^[a-z0-9]{1,32}$/i;
const currencyPattern = /^[A-Z]{3}$/;
const encode = value => encodeURIComponent(value).replace(/[!'()*]/g, char =>
  '%' + char.charCodeAt(0).toString(16).toUpperCase());
const positiveInteger = value => {
  if (typeof value !== 'number' && (typeof value !== 'string' || !/^\d+$/.test(value))) return null;
  const number = Number(value);
  return Number.isSafeInteger(number) && number > 0 ? number : null;
};

export class AdsError extends Error {
  constructor(status, code) {
    super(code);
    this.status = status;
  }
}

export function oauthHeader(method, url, keys, nonce = randomBytes(16).toString('hex'),
  timestamp = String(Math.floor(Date.now() / 1000))) {
  const oauth = {
    oauth_consumer_key: keys.consumerKey,
    oauth_nonce: nonce,
    oauth_signature_method: 'HMAC-SHA1',
    oauth_timestamp: timestamp,
    oauth_token: keys.accessToken,
    oauth_version: '1.0',
  };
  const compare = (a, b) => a < b ? -1 : a > b ? 1 : 0;
  const params = [...url.searchParams, ...Object.entries(oauth)]
    .map(([key, value]) => [encode(key), encode(value)])
    .sort(([keyA, valueA], [keyB, valueB]) => compare(keyA, keyB) || compare(valueA, valueB))
    .map(([key, value]) => key + '=' + value).join('&');
  const base = [method, url.origin + url.pathname, params].map(encode).join('&');
  const signingKey = [keys.consumerSecret, keys.accessTokenSecret].map(encode).join('&');
  oauth.oauth_signature = createHmac('sha1', signingKey).update(base).digest('base64');
  return 'OAuth ' + Object.entries(oauth)
    .map(([key, value]) => key + '="' + encode(value) + '"').join(', ');
}

export function xAdsConfig(env) {
  const keys = {
    consumerKey: env.X_ADS_CONSUMER_KEY,
    consumerSecret: env.X_ADS_CONSUMER_SECRET,
    accessToken: env.X_ADS_ACCESS_TOKEN,
    accessTokenSecret: env.X_ADS_ACCESS_TOKEN_SECRET,
  };
  if (env.VERCEL_ENV !== 'production' || !idPattern.test(env.X_ADS_ACCOUNT_ID || '') ||
      !Object.values(keys).every(Boolean)) return null;
  return {
    keys,
    accountId: env.X_ADS_ACCOUNT_ID,
    currency: env.X_ADS_CURRENCY,
    maxTotalMicros: positiveInteger(env.X_ADS_MAX_TOTAL_MICROS),
    activationEnabled: env.X_ADS_ENABLE_ACTIVATION === 'true',
  };
}

function campaign(row) {
  if (!row || typeof row.id !== 'string' || !idPattern.test(row.id) || row.deleted === true) return null;
  return {
    id: row.id,
    name: String(row.name || row.id).slice(0, 255),
    status: row.entity_status || 'UNKNOWN',
    delivery: row.effective_status || 'UNKNOWN',
    currency: currencyPattern.test(row.currency || '') ? row.currency : null,
    dailyMicros: positiveInteger(row.daily_budget_amount_local_micro),
    totalMicros: positiveInteger(row.total_budget_amount_local_micro),
    updatedAt: typeof row.updated_at === 'string' ? row.updated_at : null,
  };
}

export function activationAllowed(item, config) {
  return Boolean(config.activationEnabled && config.maxTotalMicros && item.status === 'PAUSED' &&
    item.updatedAt && item.currency && item.currency === config.currency && item.dailyMicros &&
    item.totalMicros && item.dailyMicros <= item.totalMicros && item.totalMicros <= config.maxTotalMicros);
}

export function xAdsClient(config, fetcher = fetch) {
  const accountPath = '/12/accounts/' + config.accountId;
  async function call(method, path, params = {}, base = accountPath) {
    const url = new URL(base + path, apiOrigin);
    for (const [key, value] of Object.entries(params)) url.searchParams.set(key, value);
    let response;
    try {
      response = await fetcher(url, {
        method,
        headers: { Authorization: oauthHeader(method, url, config.keys), Accept: 'application/json' },
        redirect: 'error',
        signal: AbortSignal.timeout(6500),
      });
    } catch {
      throw new AdsError(502, method === 'PUT' ? 'write_unconfirmed' : 'x_unavailable');
    }
    if (!response.ok) {
      if (response.status === 401 || response.status === 403) throw new AdsError(502, 'x_access_denied');
      if (response.status === 429) throw new AdsError(429, 'x_rate_limit');
      throw new AdsError(502, method === 'PUT' ? 'write_unconfirmed' : 'x_unavailable');
    }
    const payload = await response.json().catch(() => null);
    if (!payload || !('data' in payload)) {
      throw new AdsError(502, method === 'PUT' ? 'write_unconfirmed' : 'x_unavailable');
    }
    return payload;
  }

  return {
    async report({ start, end, level }) {
      if (level !== 'campaign') throw new AdsError(400, 'unsupported_level');
      const accounts = await call('GET', '/campaigns', { count: '20' });
      if (!Array.isArray(accounts.data)) throw new AdsError(502, 'x_unavailable');
      const items = accounts.data.map(campaign).filter(Boolean);
      const date = value => new Date(value).toISOString().slice(0, 10);
      const dates = [];
      for (let time = Date.parse(start); time <= Date.parse(end); time += 86400000) dates.push(date(time));
      const requests = [];
      for (let offset = 0; items.length && offset < dates.length; offset += 7) {
        const batch = dates.slice(offset, offset + 7);
        requests.push(call('GET', '', {
          entity: 'CAMPAIGN', entity_ids: items.map(item => item.id).join(','),
          start_time: batch[0] + 'T00:00:00Z',
          end_time: date(Date.parse(batch.at(-1)) + 86400000) + 'T00:00:00Z',
          granularity: 'DAY', placement: 'ALL_ON_TWITTER', metric_groups: 'BILLING,ENGAGEMENT,VIDEO',
        }, '/12/stats/accounts/' + config.accountId).then(payload => ({ payload, batch })));
      }
      const currency = items.length && items.every(item => item.currency === items[0].currency) ? items[0].currency : null;
      const byId = new Map(items.map(item => [item.id, item]));
      const metric = (series, index) => Number.isSafeInteger(series?.[index]) && series[index] >= 0 ? series[index] : null;
      const rows = (await Promise.all(requests)).flatMap(({ payload, batch }) => {
        if (!Array.isArray(payload.data)) throw new AdsError(502, 'x_unavailable');
        return payload.data.flatMap(row => {
          if (!byId.has(row?.id)) return [];
          const item = byId.get(row.id);
          const value = row.id_data?.find(entry => entry?.segment === null)?.metrics;
          return value ? batch.map((date, index) => ({
            id: item.id, name: item.name, date,
            spendMicros: currency ? metric(value.billed_charge_local_micro, index) : null,
            impressions: metric(value.impressions, index), clicks: metric(value.url_clicks, index),
            installs: null, results: null, videoViews: metric(value.video_total_views, index),
            video25: metric(value.video_views_25, index), video50: metric(value.video_views_50, index),
            video75: metric(value.video_views_75, index), videoComplete: metric(value.video_views_100, index),
          })) : [];
        });
      });
      return { rows, currency, timezone: 'UTC', partial: Boolean(accounts.next_cursor), coverage: 'ALL_ON_TWITTER' };
    },
    async list(cursor) {
      const params = { count: '50' };
      if (cursor) params.cursor = cursor;
      const payload = await call('GET', '/campaigns', params);
      if (!Array.isArray(payload.data)) throw new AdsError(502, 'x_unavailable');
      return {
        accountId: config.accountId,
        items: payload.data.map(campaign).filter(Boolean).map(item => ({
          ...item, canActivate: activationAllowed(item, config),
        })),
        next: typeof payload.next_cursor === 'string' ? payload.next_cursor : null,
      };
    },
    async changeStatus(input) {
      if (typeof input?.id !== 'string' || !idPattern.test(input.id) || !['ACTIVE', 'PAUSED'].includes(input.status) ||
          typeof input.updatedAt !== 'string' || !input.updatedAt || input.updatedAt.length > 64) throw new AdsError(400, 'bad_request');
      const path = '/campaigns/' + input.id;
      const current = campaign((await call('GET', path)).data);
      if (!current || current.id !== input.id) throw new AdsError(404, 'campaign_missing');
      if (current.updatedAt !== input.updatedAt) throw new AdsError(409, 'campaign_changed');
      const params = { entity_status: input.status };
      if (input.status === 'ACTIVE') {
        if (!activationAllowed(current, config) || current.currency !== input.currency ||
            current.dailyMicros !== input.dailyMicros || current.totalMicros !== input.totalMicros) {
          throw new AdsError(409, 'activation_blocked');
        }
        // Send the reviewed budgets with the state change, even if X settings
        // were edited independently after the last read.
        params.daily_budget_amount_local_micro = current.dailyMicros;
        params.total_budget_amount_local_micro = current.totalMicros;
      } else if (current.status !== 'ACTIVE') {
        throw new AdsError(409, 'campaign_changed');
      }
      const updated = campaign((await call('PUT', path, params)).data);
      if (!updated || updated.id !== current.id || updated.status !== input.status) {
        throw new AdsError(502, 'write_unconfirmed');
      }
      return { ...updated, canActivate: activationAllowed(updated, config) };
    },
  };
}

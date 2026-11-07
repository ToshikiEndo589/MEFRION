import { AdsError } from './x-ads.mjs';
import { currencyCode, micros, number, numericId, requireChange, title, upstream, verifyChange } from './report.mjs';

export function instagramConfig(env) {
  if (env.VERCEL_ENV !== 'production' || !numericId(env.META_ADS_ACCOUNT_ID) || !env.META_ADS_ACCESS_TOKEN ||
      !/^v\d{2}\.0$/.test(env.META_ADS_API_VERSION || '')) return null;
  return {
    account: env.META_ADS_ACCOUNT_ID, token: env.META_ADS_ACCESS_TOKEN, version: env.META_ADS_API_VERSION,
    enable: env.META_ADS_ENABLE_ACTIVATION === 'true', cap: micros(env.META_ADS_MAX_TOTAL_MICROS, 1),
    currency: currencyCode(env.META_ADS_CURRENCY),
  };
}

const fields = 'id,account_id,name,status,effective_status,updated_time,daily_budget,lifetime_budget';
const breakdowns = 'publisher_platform';
const ids = {
  campaign: ['campaign_id', 'campaign_name'], adgroup: ['adset_id', 'adset_name'], ad: ['ad_id', 'ad_name'],
};
function actionValue(actions, type) {
  return Array.isArray(actions) ? number(actions.find(row => row?.action_type === type)?.value) : null;
}
function manualInstagram(adset) {
  const target = adset?.targeting;
  const platforms = target?.publisher_platforms;
  return Array.isArray(platforms) && platforms.length === 1 && platforms[0] === 'instagram' &&
    Array.isArray(target.instagram_positions) && target.instagram_positions.length > 0 &&
    ['facebook_positions', 'audience_network_positions', 'messenger_positions', 'threads_positions']
      .every(key => !target[key] || (Array.isArray(target[key]) && !target[key].length));
}

export function instagramClient(config, fetcher) {
  const accountPath = 'act_' + config.account;
  const request = async (path, query = {}, body) => {
    const url = new URL('https://graph.facebook.com/' + config.version + '/' + path);
    url.search = new URLSearchParams(query);
    const data = await upstream(fetcher, url, {
      Authorization: 'Bearer ' + config.token,
      ...(body ? { 'Content-Type': 'application/x-www-form-urlencoded' } : {}),
    }, body && new URLSearchParams(body).toString(), path.endsWith('/insights'));
    if (!data || data.error) throw new AdsError(502, body ? 'write_unconfirmed' : 'provider_unavailable');
    return data;
  };
  const getAccount = () => request(accountPath, { fields: 'account_id,currency,timezone_name' });
  const page = async (path, query, limit = 3) => {
    const rows = [];
    let after;
    for (let i = 0; i < limit; i++) {
      const result = await request(path, { ...query, ...(after ? { after } : {}) });
      if (!Array.isArray(result.data)) throw new AdsError(502, 'provider_unavailable');
      rows.push(...result.data);
      if (!result.paging?.next) return { rows, partial: false };
      const next = result.paging.cursors?.after;
      if (typeof next !== 'string' || !next || next === after || next.length > 4096) break;
      after = next;
    }
    return { rows, partial: true };
  };
  function campaign(row, account, scoped = false) {
    if (!numericId(row?.id) || row.account_id !== config.account || !['ACTIVE', 'PAUSED'].includes(row.status)) return null;
    const currency = account.account_id === config.account ? currencyCode(account.currency) : null;
    // Meta reports budgets in minor units, including a zero-decimal JPY.
    const decimals = currency ? new Intl.NumberFormat('en', { style: 'currency', currency }).resolvedOptions().maximumFractionDigits : 2;
    const unit = 10 ** (6 - decimals);
    const totalMicros = micros(row.lifetime_budget, unit);
    const dailyMicros = micros(row.daily_budget, unit);
    const updatedAt = title(row.updated_time, null);
    return { id: row.id, name: title(row.name, row.id), status: row.status, delivery: title(row.effective_status, 'UNKNOWN'),
      currency, totalMicros, dailyMicros, updatedAt, canPause: scoped && row.status === 'ACTIVE' && !!updatedAt,
      canActivate: !!(scoped && config.enable && currency && currency === config.currency && row.status === 'PAUSED' &&
        updatedAt && totalMicros > 0 && totalMicros <= config.cap && (dailyMicros === 0 || dailyMicros === null)) };
  }
  return {
    async list() {
      const [account, listed] = await Promise.all([
        getAccount(), page(accountPath + '/campaigns', { fields, limit: '100' }, 1),
      ]);
      // Every write is scoped using the live ad set targeting. Do not infer
      // manual placement from historic Instagram impressions.
      return { accountId: config.account, items: listed.rows.map(row => campaign(row, account)).filter(Boolean)
        .map(item => ({ ...item, needsReview: true })), partial: listed.partial };
    },
    async review(id) {
      if (!numericId(id)) throw new AdsError(400, 'bad_request');
      const [row, account] = await Promise.all([request(id, { fields }), getAccount()]);
      if (!campaign(row, account)) throw new AdsError(404, 'campaign_missing');
      const adsets = await page(id + '/adsets', {
        fields: 'id,status,targeting', limit: '100',
      }, 1);
      const applicable = adsets.rows.filter(adset => !['DELETED', 'ARCHIVED'].includes(adset?.status));
      const scoped = !adsets.partial && applicable.length > 0 && applicable.every(manualInstagram);
      return { ...campaign(row, account, scoped), scoped };
    },
    async changeStatus(input) {
      requireChange(input, numericId);
      const item = await this.review(input.id);
      if (!item.scoped) throw new AdsError(409, 'placement_blocked');
      verifyChange(item, input);
      const response = await request(item.id, {}, { status: input.status });
      if (response.success !== true) throw new AdsError(502, 'write_unconfirmed');
      return { ...item, status: input.status, canActivate: false, canPause: false, needsReview: true };
    },
    async report(query) {
      const { start, end, level } = query;
      const [id, name] = ids[level];
      const read = extra => page(accountPath + '/insights', {
        level: level === 'adgroup' ? 'adset' : level, limit: '250',
        time_range: JSON.stringify({ since: start, until: end }), time_increment: '1', breakdowns,
        fields: [id, name, 'date_start', 'account_currency', 'spend', 'impressions', 'inline_link_clicks', ...extra].join(','),
      });
      const detailed = ['actions', 'video_play_actions', 'video_p25_watched_actions', 'video_p50_watched_actions',
        'video_p75_watched_actions', 'video_p100_watched_actions'];
      const [account, report] = await Promise.all([
        getAccount(), read(detailed).catch(async error => {
          if (error.message !== 'report_parameters_rejected') throw error;
          return { ...await read([]), limitedMetrics: true };
        }),
      ]);
      const currency = account.account_id === config.account ? currencyCode(account.currency) : null;
      return { currency, timezone: title(account.timezone_name, null), partial: report.partial, limitedMetrics: !!report.limitedMetrics, rows: report.rows
        .filter(row => row?.publisher_platform === 'instagram' && numericId(row[id]))
        .map(row => ({
          id: row[id], name: title(row[name], row[id]), date: row.date_start,
          spendMicros: currency && row.account_currency === currency ? micros(row.spend) : null,
          impressions: number(row.impressions), clicks: number(row.inline_link_clicks),
          installs: actionValue(row.actions, 'mobile_app_install'), results: null,
          videoViews: actionValue(row.video_play_actions, 'video_view'),
          video25: actionValue(row.video_p25_watched_actions, 'video_view'),
          video50: actionValue(row.video_p50_watched_actions, 'video_view'),
          video75: actionValue(row.video_p75_watched_actions, 'video_view'),
          videoComplete: actionValue(row.video_p100_watched_actions, 'video_view'),
        })) };
    },
  };
}

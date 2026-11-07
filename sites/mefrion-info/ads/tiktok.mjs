import { AdsError } from './x-ads.mjs';
import { currencyCode, micros, number, numericId, requireChange, title, upstream, verifyChange } from './report.mjs';

export function tiktokConfig(env) {
  if (env.VERCEL_ENV !== 'production' || !numericId(env.TIKTOK_ADS_ADVERTISER_ID) || !env.TIKTOK_ADS_ACCESS_TOKEN) return null;
  return {
    account: env.TIKTOK_ADS_ADVERTISER_ID, token: env.TIKTOK_ADS_ACCESS_TOKEN,
    enable: env.TIKTOK_ADS_ENABLE_ACTIVATION === 'true', cap: micros(env.TIKTOK_ADS_MAX_TOTAL_MICROS, 1),
    currency: currencyCode(env.TIKTOK_ADS_CURRENCY),
  };
}

const levels = { campaign: ['AUCTION_CAMPAIGN', 'campaign_id'], adgroup: ['AUCTION_ADGROUP', 'adgroup_id'], ad: ['AUCTION_AD', 'ad_id'] };

export function tiktokClient(config, fetcher) {
  const request = async (path, query = {}, body) => {
    const url = new URL('https://business-api.tiktok.com/open_api/v1.3/' + path + '/');
    url.search = new URLSearchParams(query);
    const data = await upstream(fetcher, url, {
      'Access-Token': config.token, ...(body ? { 'Content-Type': 'application/json' } : {}),
    }, body && JSON.stringify(body));
    if (data?.code !== 0 || !data.data) throw new AdsError(502, body ? 'write_unconfirmed' : 'provider_unavailable');
    return data.data;
  };
  const list = async (path, query, maxPages) => {
    const rows = [];
    for (let page = 1; page <= maxPages; page++) {
      const result = await request(path, { ...query, page: String(page) });
      if (!Array.isArray(result.list) || !Number.isInteger(result.page_info?.total_page)) {
        throw new AdsError(502, 'provider_unavailable');
      }
      rows.push(...result.list);
      if (page >= result.page_info.total_page) return { rows, partial: false };
    }
    return { rows, partial: true };
  };
  const campaigns = id => list('campaign/get', {
    advertiser_id: config.account, page_size: '100',
    ...(id ? { filtering: JSON.stringify({ campaign_ids: [id] }) } : {}),
  }, 1);
  const getAccount = async () => {
    const result = await request('advertiser/info', {
      advertiser_ids: JSON.stringify([config.account]),
      fields: JSON.stringify(['advertiser_id', 'currency', 'timezone']),
    });
    return result.list?.find(account => account.advertiser_id === config.account) || {};
  };
  function campaign(row, account) {
    if (!numericId(row?.campaign_id) || row.advertiser_id !== config.account) return null;
    const status = { ENABLE: 'ACTIVE', DISABLE: 'PAUSED' }[row.operation_status];
    if (!status) return null;
    const currency = currencyCode(account.currency);
    const totalMicros = row.budget_mode === 'BUDGET_MODE_TOTAL' ? micros(row.budget) : null;
    const dailyMicros = row.budget_mode === 'BUDGET_MODE_DAY' ? micros(row.budget) : null;
    const updatedAt = title(row.modify_time, null);
    // Smart+ and reserved campaigns have different management contracts.
    const regular = row.campaign_type === 'REGULAR_CAMPAIGN' && row.is_smart_performance_campaign === false;
    return { id: row.campaign_id, name: title(row.campaign_name, row.campaign_id), status,
      delivery: title(row.secondary_status, 'UNKNOWN'), currency, totalMicros, dailyMicros, updatedAt,
      canPause: !!(regular && updatedAt && status === 'ACTIVE'),
      canActivate: !!(regular && updatedAt && status === 'PAUSED' && config.enable && currency &&
        currency === config.currency && totalMicros > 0 && totalMicros <= config.cap) };
  }
  return {
    async list() {
      const [account, result] = await Promise.all([getAccount(), campaigns()]);
      return { accountId: config.account, items: result.rows.map(row => campaign(row, account)).filter(Boolean), partial: result.partial };
    },
    async changeStatus(input) {
      requireChange(input, numericId);
      const [account, result] = await Promise.all([getAccount(), campaigns(input.id)]);
      const item = campaign(result.rows.find(row => row?.campaign_id === input.id), account);
      if (!item || result.partial) throw new AdsError(404, 'campaign_missing');
      verifyChange(item, input);
      if (input.status === 'PAUSED' && !item.canPause) throw new AdsError(409, 'activation_blocked');
      await request('campaign/status/update', {}, {
        advertiser_id: config.account, campaign_ids: [item.id],
        operation_status: input.status === 'ACTIVE' ? 'ENABLE' : 'DISABLE',
      });
      const confirmed = (await campaigns(item.id).catch(() => null))?.rows
        .find(row => row?.campaign_id === item.id);
      const updated = campaign(confirmed, account);
      if (updated?.status !== input.status) throw new AdsError(502, 'write_unconfirmed');
      return updated;
    },
    async report({ start, end, level }) {
      const [dataLevel, id] = levels[level];
      const name = id.replace(/_id$/, '_name');
      const [account, report] = await Promise.all([
        getAccount(), list('report/integrated/get', {
          advertiser_id: config.account, report_type: 'BASIC', data_level: dataLevel, service_type: 'AUCTION',
          dimensions: JSON.stringify([id, 'stat_time_day']),
          metrics: JSON.stringify([name, 'spend', 'impressions', 'clicks', 'conversion', 'app_install',
            'video_play_actions', 'video_views_p25', 'video_views_p50', 'video_views_p75', 'video_views_p100']),
          start_date: start, end_date: end, page_size: '250',
        }, 3),
      ]);
      const currency = currencyCode(account.currency);
      return { currency, timezone: title(account.timezone, null), partial: report.partial, rows: report.rows
        .filter(row => numericId(row?.dimensions?.[id])).map(({ dimensions, metrics }) => ({
          id: dimensions[id], name: title(metrics?.[name], dimensions[id]), date: dimensions.stat_time_day?.split(' ')[0],
          spendMicros: currency ? micros(metrics?.spend) : null, impressions: number(metrics?.impressions),
          clicks: number(metrics?.clicks), installs: number(metrics?.app_install), results: number(metrics?.conversion),
          videoViews: number(metrics?.video_play_actions), video25: number(metrics?.video_views_p25),
          video50: number(metrics?.video_views_p50), video75: number(metrics?.video_views_p75),
          videoComplete: number(metrics?.video_views_p100),
        })) };
    },
  };
}

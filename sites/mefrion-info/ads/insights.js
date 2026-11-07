export const keys = ['spendMicros', 'impressions', 'clicks', 'installs', 'results', 'videoViews', 'video25', 'video50', 'video75', 'videoComplete'];
const known = value => typeof value === 'number' && Number.isFinite(value) && value >= 0;
export const ratio = (numerator, denominator, scale = 1) =>
  known(numerator) && known(denominator) && denominator > 0 ? numerator / denominator * scale : null;

export function previousPeriod(start, end) {
  const day = 86400000;
  const first = Date.parse(start), last = Date.parse(end);
  if (!Number.isFinite(first) || !Number.isFinite(last) || last < first) return null;
  const date = time => new Date(time).toISOString().slice(0, 10);
  return { start: date(first - (last - first) - day), end: date(first - day) };
}

export function metricChange(current, previous, percentagePoints = false) {
  if (!known(current) || !known(previous)) return null;
  return percentagePoints ? current - previous : previous > 0 ? (current - previous) / previous * 100 : null;
}

export function aggregate(rows, group) {
  const groups = new Map();
  for (const row of rows) {
    const key = group(row);
    if (!groups.has(key)) groups.set(key, { key, name: row.name, rows: 0, missing: {} });
    const target = groups.get(key);
    target.rows++;
    for (const metric of keys) {
      const value = row[metric];
      if (known(value)) target[metric] = (target[metric] ?? 0) + value;
      else target.missing[metric] = (target.missing[metric] || 0) + 1;
    }
  }
  return [...groups.values()].map(item => {
    const complete = key => item.missing[key] ? null : item[key];
    return { ...item,
      ctr: ratio(complete('clicks'), complete('impressions'), 100),
      cpc: ratio(complete('spendMicros'), complete('clicks')),
      cpm: ratio(complete('spendMicros'), complete('impressions'), 1000),
      cpi: ratio(complete('spendMicros'), complete('installs')),
      cpa: ratio(complete('spendMicros'), complete('results')),
    };
  });
}

// Descriptive diagnostics using aggregate data from the same platform and period.
export function diagnostics(items, targetMicros) {
  const eligible = items.filter(item => item.impressions >= 1000 && item.ctr !== null);
  const out = [];
  for (const item of items) {
    if (targetMicros > 0 && item.cpi > targetMicros * 1.25 && item.installs >= 20) {
      out.push({ name: item.name, kind: 'CPI', value: item.cpi, baseline: targetMicros,
        note: '獲得単価が目標を25%以上超えています。配信先とストア導線を見直す候補です。' });
    }
    const peers = eligible.filter(peer => peer !== item);
    if (!eligible.includes(item) || peers.length < 2) continue;
    const impressions = peers.reduce((sum, peer) => sum + peer.impressions, 0);
    const clicks = peers.reduce((sum, peer) => sum + peer.clicks, 0);
    const baseline = clicks / impressions * 100;
    if (clicks >= 30 && item.ctr < baseline * 0.7) {
      out.push({ name: item.name, kind: 'CTR', value: item.ctr, baseline,
        note: '他の配信よりクリック率が低めです。動画の冒頭や見出しを変えるテスト候補です。' });
    }
  }
  return out.slice(0, 12);
}

export function csvCell(value) {
  if (value == null) return '';
  const safe = typeof value === 'string' && (/^[\s\uFEFF]*[=+\-@]/u.test(value) || /^[\t\r\n]/.test(value)) ? "'" + value : String(value);
  return '"' + safe.replaceAll('"', '""') + '"';
}

export const appleColumns = ['platform','campaign_id','campaign_token','start','end','first_downloads','d1_pct','d7_pct','d30_pct'];

export function parseAppleFile(raw) {
  const lines = raw.replace(/^\uFEFF/, '').trim().split(/\r?\n/);
  if (lines.length > 1001 || lines.shift()?.trim() !== appleColumns.join(',')) throw Error('列名をテンプレートと同じにしてください。');
  const date = value => /^\d{4}-\d{2}-\d{2}$/.test(value) && Number.isFinite(Date.parse(value)) &&
    new Date(value).toISOString().slice(0, 10) === value;
  const value = (input, pattern) => {
    if (!input) return null;
    if (!pattern.test(input) || !known(Number(input))) throw Error('ダウンロード数と継続率を数値で入力してください。');
    return Number(input);
  };
  const unique = new Set();
  return lines.map((line, index) => {
    const fields = line.split(',').map(field => field.trim());
    const [platform, id, campaign, start, end, downloads, d1, d7, d30] = fields;
    if (fields.length !== appleColumns.length || !['x', 'instagram', 'tiktok'].includes(platform) ||
        !/^[a-z0-9]{1,32}$/i.test(id) || !/^[a-zA-Z0-9_-]{1,40}$/.test(campaign) ||
        !date(start) || !date(end) || start > end) throw Error((index + 2) + '行目の媒体、ID、トークン、期間を確認してください。');
    const rates = [d1, d7, d30].map(rate => value(rate, /^\d{1,3}(\.\d{1,4})?$/));
    if (rates.some(rate => rate > 100)) throw Error('継続率は0〜100で入力してください。');
    const key = [platform, id, start, end].join(':');
    const sourceKey = ['apple', campaign, start, end].join(':');
    if (unique.has(key) || unique.has(sourceKey)) throw Error('同じキャンペーン・期間の行が重複しています。');
    unique.add(key);
    unique.add(sourceKey);
    return { platform, id, campaign, start, end, downloads: value(downloads, /^\d{1,12}$/), rates };
  });
}

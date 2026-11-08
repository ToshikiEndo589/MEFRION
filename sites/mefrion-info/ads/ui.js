'use strict';

const adsPlatforms = {
  x: { name: 'X', manager: 'https://ads.x.com/', scope: 'X内の配信。レポートは最大20キャンペーン、日付はUTC。' },
  instagram: { name: 'Instagram', manager: 'https://adsmanager.facebook.com/', scope: 'Instagramへの配信実績のみ。配信操作はInstagram専用のキャンペーンに限ります。' },
  tiktok: { name: 'TikTok', manager: 'https://ads.tiktok.com/', scope: 'TikTok Adsの広告アカウント全体。設定によってTikTok以外の配信面も含みます。' },
};
const adsMessages = {
  login_required: 'ログインし直してください。',
  admin_required: '配信開始・停止には管理者権限が必要です。',
  operator_required: 'Adsを開くには有効な運営権限と二段階認証が必要です。',
  x_access_denied: '広告アカウントのAPI権限を確認してください。',
  provider_access_denied: '広告アカウントのAPI権限を確認してください。',
  x_rate_limit: '取得上限に達しました。少し時間をおいて更新してください。',
  provider_rate_limit: '取得上限に達しました。少し時間をおいて更新してください。',
  campaign_changed: '媒体側で設定が変わりました。更新してから操作してください。',
  activation_blocked: '媒体側のキャンペーン種別・通貨・予算上限を確認してください。',
  placement_blocked: 'Instagram専用の手動配置を確認できないため、この画面からは操作できません。',
  write_unconfirmed: '変更結果を確認できません。再操作する前に、媒体側で最新の状態を確認してください。',
  provider_not_connected: '広告APIが接続されていません。',
  invalid_dates: '有効な日付を選び、期間を31日以内にしてください。',
  unsupported_level: 'この媒体はキャンペーン単位で集計します。',
  apple_report_unavailable: 'Appleの詳細レポートを取得できませんでした。接続を確認するか、期間を短くしてください。',
};

let adsPlatform = 'all';
let adsRevision = 0;
let adsCursor = null;
let adsPending = null;
let adsReports = {};
let adsPrevious = {};
let adsAppleRows = [];
let adsAppleFeed = null;
let adsSort = 'spendMicros';
let adsMath;
const adsMathReady = import('/ads/insights.js');
const adsNames = {
  spendMicros: '消化額', impressions: '表示', clicks: 'リンク・遷移クリック', ctr: 'CTR', cpc: 'CPC',
  cpm: 'CPM', installs: '媒体計測インストール', cpi: '媒体CPI', results: '媒体CV', cpa: 'CPA',
  videoViews: '動画再生', video25: '動画25%', video50: '動画50%', video75: '動画75%', videoComplete: '動画100%',
};
const adsReportColumns = Object.keys(adsNames);
const adsMoneyKeys = ['spendMicros', 'cpc', 'cpm', 'cpi', 'cpa'];
const adsDash = '—';
const adsFormatted = new Intl.NumberFormat('ja-JP', { maximumFractionDigits: 2 });

async function adsRequest(platform, { query = {}, body } = {}) {
  const path = '/ads/api/' + platform + '?' + new URLSearchParams(query);
  const session = token;
  let result, data;
  try {
    result = await fetch(path, {
      method: body ? 'POST' : 'GET',
      headers: { Authorization: 'Bearer ' + session, 'Content-Type': 'application/json' },
      body: body ? JSON.stringify(body) : undefined,
      cache: 'no-store', credentials: 'omit', signal: AbortSignal.timeout(26000),
    });
    data = await result.json();
  } catch (error) {
    if (body) throw Error(adsMessages.write_unconfirmed);
    throw error;
  }
  if (session === token && (result.status === 401 || data.code === 'operator_required')) {
    clear();
    status(adsMessages[data.code] || adsMessages.login_required);
  }
  if (!result.ok) throw Error(adsMessages[data.code] || '広告データを取得できませんでした。接続を確認して更新してください。');
  return data;
}

function clearAds() {
  adsRevision++;
  $('ads-workspace').hidden = true;
  $('main-heading').hidden = false;
  for (const id of ['ads-campaigns', 'ads-report', 'ads-apple-results', 'ads-apple-feed', 'ads-diagnostics']) $(id).replaceChildren();
  for (const id of ['ads-link-url', 'ads-target', 'ads-apple-file']) $(id).value = '';
  for (const id of ['ads-link-status', 'ads-apple-status']) $(id).textContent = '';
  $('ads-link-result').hidden = true;
  $('ads-link-form').reset();
  $('ads-apple-feed-status').textContent = '詳細レポートからキャンペーントークン別に取得します。';
  adsReports = {};
  adsPrevious = {};
  adsAppleRows = [];
  adsAppleFeed = null;
  adsCursor = null;
  adsPending = null;
  if ($('ads-confirm').open) $('ads-confirm').close();
}

function adsMoney(value, currency) {
  return value != null && currency ? new Intl.NumberFormat('ja-JP', {
    style: 'currency', currency, currencyDisplay: 'code', maximumFractionDigits: 2,
  }).format(value / 1e6) : adsDash;
}

function adsValue(key, value, currency) {
  if (value == null) return adsDash;
  if (adsMoneyKeys.includes(key)) return adsMoney(value, currency);
  return adsFormatted.format(value) + (key === 'ctr' ? '%' : '');
}

function adsTable(headers, rows, label) {
  const region = node('div');
  region.className = 'ads-table-scroll';
  region.tabIndex = 0;
  region.setAttribute('role', 'region');
  region.setAttribute('aria-label', label);
  const table = node('table');
  const head = node('thead');
  const tr = node('tr');
  for (const text of headers) {
    const th = node('th', text);
    th.scope = 'col';
    tr.append(th);
  }
  head.append(tr);
  const body = node('tbody');
  for (const row of rows) {
    const line = node('tr');
    for (const value of row) line.append(node('td', value));
    body.append(line);
  }
  table.append(head, body);
  region.append(table);
  return region;
}

function adsTotals(report) {
  return adsMath.aggregate(report.rows, () => 'total')[0] || {};
}

function adsGrouped(report) {
  return adsMath.aggregate(report.rows, row => row.id);
}

function adsMetrics(item, currency) {
  return adsReportColumns.map(key => {
    const value = adsValue(key, item[key], currency);
    return value + (item[key] != null && item.missing?.[key] ? ' ※' : '');
  });
}

function adsDelta(report, previous, key, now, before) {
  if (!previous?.connected || previous.partial || report.partial || previous.currency !== report.currency ||
      now.missing?.[key] || before.missing?.[key]) return '';
  const points = key === 'ctr';
  const delta = adsMath.metricChange(now[key], before[key], points);
  return delta === null ? '' : (delta > 0 ? '+' : '') + adsFormatted.format(delta) + (points ? ' pt' : '%');
}

function adsReportInfo(platform, report) {
  const source = adsPlatforms[platform];
  if (report.error) return source.name + ' · ' + report.error;
  if (!report.connected) return source.name + ' · 未接続';
  if (!report.rows.length) return source.name + ' · 対象期間の配信データなし' + (report.partial ? '（一部取得）' : '');
  return source.name + ' · ' + (report.partial ? '一部取得' : '取得済み') + ' · ' +
    (report.timezone || '媒体のアカウント時刻') + (report.limitedMetrics ? ' · 基本指標のみ' : '');
}

function adsRenderReport() {
  const out = $('ads-report');
  out.replaceChildren();
  const reports = Object.entries(adsReports);
  const connected = reports.filter(([, report]) => report.connected);
  const compare = Object.keys(adsPrevious).length > 0;
  $('ads-connection').textContent = connected.length + ' / ' + reports.length + ' 媒体 接続';
  $('ads-export').hidden = !connected.some(([, report]) => report.rows.length);
  const previousPeriod = Object.values(adsPrevious).find(report => report.connected);
  $('ads-report-status').textContent = reports.map(([platform, report]) => adsReportInfo(platform, report)).join('　/　') +
    (compare ? previousPeriod ? '　前期 ' + previousPeriod.start + ' 〜 ' + previousPeriod.end : '　前期データなし' : '');
  if (adsPlatform === 'all') {
    $('ads-optimization').hidden = true;
    if (!connected.length) return;
    out.append(adsTable(['媒体', ...adsReportColumns.map(key => adsNames[key])],
      connected.map(([platform, report]) => {
        const total = adsTotals(report);
        const previous = adsPrevious[platform];
        const baseline = previous?.connected ? adsTotals(previous) : {};
        return [adsPlatforms[platform].name + (report.partial ? '（一部）' : ''), ...adsMetrics(total, report.currency)
          .map((value, index) => {
            const delta = adsDelta(report, previous, adsReportColumns[index], total, baseline);
            return delta ? value + ' (' + delta + ')' : value;
          })];
      }), '媒体別の実績'));
    const note = node('p', '媒体ごとに計測条件が異なります。※は一部の値を取得できた項目です。');
    note.className = 'ads-muted';
    out.append(note);
    return;
  }
  const report = adsReports[adsPlatform];
  if (!report?.connected || !report.rows.length) {
    $('ads-optimization').hidden = true;
    return;
  }
  const totals = adsTotals(report);
  const previous = adsPrevious[adsPlatform];
  const baseline = previous?.connected ? adsTotals(previous) : {};
  const kpis = node('div');
  kpis.className = 'ads-kpis';
  for (const key of ['spendMicros', 'impressions', 'clicks', 'ctr', 'installs', 'cpi']) {
    const card = node('div');
    card.append(node('span', adsNames[key]), node('strong', adsValue(key, totals[key], report.currency) +
      (totals[key] != null && totals.missing?.[key] ? ' ※' : '')));
    const delta = adsDelta(report, previous, key, totals, baseline);
    if (delta) card.append(node('small', '前期比 ' + delta));
    kpis.append(card);
  }
  out.append(kpis);
  const toolbar = node('div');
  toolbar.className = 'ads-heading';
  const sort = node('select');
  sort.setAttribute('aria-label', '並べ替え');
  for (const [key, label] of Object.entries(adsNames)) {
    const option = node('option', label + '順');
    option.value = key;
    sort.append(option);
  }
  sort.value = adsSort;
  sort.addEventListener('change', () => { adsSort = sort.value; adsRenderReport(); out.querySelector('select')?.focus(); });
  toolbar.append(node('h3', '広告実績'), sort);
  const items = adsGrouped(report).sort((a, b) => (b[adsSort] ?? -1) - (a[adsSort] ?? -1));
  out.append(toolbar, adsTable(['名前 / ID', ...adsReportColumns.map(key => adsNames[key])],
    items.map(item => [item.name + ' / ' + item.key, ...adsMetrics(item, report.currency)]), '広告別の実績'));
  const daily = adsMath.aggregate(report.rows, row => row.date).sort((a, b) => a.key.localeCompare(b.key));
  const trend = node('details');
  trend.className = 'ads-trend';
  const max = Math.max(1, ...daily.map(item => item.spendMicros ?? 0));
  const chart = node('div');
  chart.className = 'ads-chart';
  for (const item of daily) {
    if (item.spendMicros == null || item.missing.spendMicros) continue;
    const line = node('div');
    const bar = node('progress');
    bar.max = max;
    bar.value = item.spendMicros;
    bar.setAttribute('aria-label', item.key + 'の消化額');
    line.append(node('span', item.key), bar, node('span', adsMoney(item.spendMicros, report.currency)));
    chart.append(line);
  }
  trend.append(node('summary', '日別の推移'), chart,
    adsTable(['日付', ...adsReportColumns.map(key => adsNames[key])],
      daily.map(item => [item.key, ...adsMetrics(item, report.currency)]), '日別の実績'));
  const notes = node('p', adsPlatforms[adsPlatform].scope + ' ※は一部の値を取得できた項目です。ダッシュは値がないか、比較できない項目です。');
  notes.className = 'ads-muted';
  out.append(trend, notes);
  $('ads-optimization').hidden = false;
  adsRenderDiagnostics();
}

function adsRenderDiagnostics() {
  const report = adsReports[adsPlatform];
  const out = $('ads-diagnostics');
  out.replaceChildren();
  if (!report?.rows?.length) return;
  if (report.partial) {
    out.append(node('p', '取得範囲が一部のため、分析を保留しています。期間を短くして再取得してください。'));
    return;
  }
  const target = Number($('ads-target').value) * 1e6;
  const hints = adsMath.diagnostics(adsGrouped(report), report.currency ? target : 0);
  if (!hints.length) out.append(node('p', '現在の集計では、条件に該当する見直し候補はありません。'));
  else for (const hint of hints) {
    const card = node('article');
    card.className = 'ads-row';
    const key = hint.kind.toLowerCase();
    card.append(node('strong', hint.name + ' · ' + hint.kind),
      node('p', adsValue(key, hint.value, report.currency) + ' / 比較基準 ' + adsValue(key, hint.baseline, report.currency)),
      node('p', hint.note));
    out.append(card);
  }
}

function adsDownload(filename, rows) {
  const data = '\uFEFF' + rows.map(row => row.map(adsMath.csvCell).join(',')).join('\r\n');
  const url = URL.createObjectURL(new Blob([data], { type: 'text/csv;charset=utf-8' }));
  const anchor = node('a');
  anchor.href = url;
  anchor.download = filename;
  anchor.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

function adsRenderApple() {
  const out = $('ads-apple-results');
  out.replaceChildren();
  if (!adsAppleRows.length) return;
  const rows = adsAppleRows.filter(entry => adsPlatform === 'all' || entry.platform === adsPlatform);
  if (!rows.length) return;
  out.append(adsTable(['媒体', 'キャンペーンID / トークン', '対象期間', '初回DL', 'D1', 'D7', 'D30', 'Apple基準CPI'],
    rows.map(entry => {
      const report = adsReports[entry.platform];
      const matched = report?.connected && !report.partial && report.level === 'campaign' &&
        report.start === entry.start && report.end === entry.end &&
        adsGrouped(report).find(item => item.key === entry.id && !item.missing.spendMicros);
      const expected = Math.round((Date.parse(entry.end) - Date.parse(entry.start)) / 86400000) + 1;
      const fromApple = adsAppleFeed?.start === entry.start && adsAppleFeed.end === entry.end &&
        adsAppleFeed.days.length === expected ? adsAppleFeed.rows.find(row => row.campaign === entry.campaign)?.downloads : null;
      const downloads = fromApple ?? entry.downloads;
      const cpi = adsMath.ratio(matched?.spendMicros, downloads);
      return [adsPlatforms[entry.platform].name, entry.id + ' / ' + entry.campaign, entry.start + ' 〜 ' + entry.end,
        adsValue('installs', downloads), ...entry.rates.map(rate => adsValue('ctr', rate)),
        adsMoney(cpi, report?.currency)];
    }), 'Appleのキャンペーン別計測'));
}

function adsConfirm(platform, item, accountId, next) {
  adsPending = { platform, item: { ...item, status: next } };
  const starts = next === 'ACTIVE';
  $('ads-confirm-title').textContent = starts ? '広告の配信を開始' : '広告の配信を停止';
  $('ads-confirm-summary').textContent = adsPlatforms[platform].name + ' / ' + accountId + ' / ' + item.name +
    ' · 日額 ' + adsMoney(item.dailyMicros, item.currency) + ' · 総額 ' + adsMoney(item.totalMicros, item.currency);
  $('ads-confirm-notice').textContent = starts ? '媒体の設定に沿って配信され、広告費が発生します。' : '媒体側でキャンペーンを停止します。';
  $('ads-confirm-start').textContent = starts ? '予算を確認して開始' : '配信を停止';
  $('ads-confirm').returnValue = '';
  $('ads-confirm').showModal();
}

function adsRow(platform, item, accountId, canManage = true) {
  const row = node('article');
  row.className = 'ads-row ads-delivery-row';
  row.dataset.campaignId = item.id;
  const summary = node('div');
  const state = { ACTIVE: '有効', PAUSED: '停止中', DRAFT: '下書き' }[item.status] || item.status;
  summary.append(node('strong', item.name), node('p', state + ' · ' + item.id),
    node('p', '日額 ' + adsMoney(item.dailyMicros, item.currency) + ' / 総額 ' + adsMoney(item.totalMicros, item.currency)));
  row.append(summary);
  const next = item.canActivate ? 'ACTIVE' : item.canPause || (platform === 'x' && item.status === 'ACTIVE' && item.updatedAt) ? 'PAUSED' : null;
  if (canManage && (next || item.needsReview)) {
    const button = node('button', item.needsReview ? '配信先を確認' : next === 'ACTIVE' ? '配信開始…' : '配信停止…');
    button.type = 'button';
    button.addEventListener('click', () => {
      if (next) return adsConfirm(platform, item, accountId, next);
      perform(async () => {
        const stamp = adsRevision;
        const { item: review } = await adsRequest(platform, { query: { view: 'review', id: item.id } });
        if (stamp !== adsRevision) return;
        row.replaceWith(adsRow(platform, review, accountId));
        if (!review.scoped) status(adsMessages.placement_blocked);
        else if (!review.canActivate && !review.canPause) status('Instagram専用です。配信開始には総額予算と配信権限が必要です。');
      });
    });
    row.append(button);
  }
  return row;
}

async function adsLoadDelivery(platform, stamp, append = false) {
  const section = $('ads-delivery');
  section.hidden = platform === 'all';
  if (section.hidden) return;
  const provider = adsPlatforms[platform];
  const out = $('ads-campaigns');
  $('ads-manager').href = provider.manager;
  $('ads-delivery-note').textContent = provider.scope;
  if (!append) out.replaceChildren(node('p', 'キャンペーンを取得しています…'));
  $('ads-more').hidden = true;
  try {
    const result = await adsRequest(platform, { query: append ? { cursor: adsCursor } : {} });
    if (stamp !== adsRevision) return;
    if (!append) out.replaceChildren();
    if (!result.connected) return out.append(node('p', '広告APIを接続するとキャンペーンが表示されます。'));
    if (result.canManage !== true) $('ads-delivery-note').textContent += ' 配信操作には管理者権限が必要です。';
    if (result.items.length) out.append(...result.items.map(item => adsRow(platform, item, result.accountId, result.canManage === true)));
    else if (!append) out.append(node('p', '操作対象のキャンペーンがありません。'));
    if (result.partial) out.append(node('p', '一部のキャンペーンを表示しています。残りは媒体の管理画面で確認できます。'));
    adsCursor = result.next || null;
    $('ads-more').hidden = !adsCursor;
  } catch (error) {
    if (stamp === adsRevision) out.replaceChildren(node('p', error.message));
  }
}

async function refreshAds() {
  if (!token || !mfaComplete || Date.now() / 1000 >= expires) {
    clear();
    throw Error('Adsにログインし直してください。');
  }
  const stamp = ++adsRevision;
  adsMath = await adsMathReady;
  if (stamp !== adsRevision) return;
  $('ads-workspace').hidden = false;
  $('main-heading').hidden = true;
  const form = $('ads-period');
  const level = form.elements.level;
  level.disabled = ['all', 'x'].includes(adsPlatform);
  if (level.disabled) level.value = 'campaign';
  const { start, end, compare } = form.elements;
  const selected = adsPlatform === 'all' ? Object.keys(adsPlatforms) : [adsPlatform];
  const current = adsPlatform;
  adsReports = {};
  adsPrevious = {};
  $('ads-export').hidden = true;
  $('ads-optimization').hidden = true;
  $('ads-report').replaceChildren();
  $('ads-report-status').textContent = '媒体から集計を取得しています…';
  const dates = { start: start.value, end: end.value };
  const before = compare.checked ? adsMath.previousPeriod(dates.start, dates.end) : null;
  const getReport = async (platform, period) => {
    try {
      const result = await adsRequest(platform, { query: { view: 'report', ...period, level: level.value } });
      return [platform, result];
    } catch (error) {
      return [platform, { error: error.message }];
    }
  };
  const reports = Promise.all(selected.map(platform => getReport(platform, dates)));
  const comparison = before ? Promise.all(selected.map(platform => getReport(platform, before))) : [];
  const delivery = adsLoadDelivery(current, stamp);
  const [results, preceding] = await Promise.all([reports, comparison]);
  if (stamp === adsRevision) {
    adsReports = Object.fromEntries(results);
    adsPrevious = Object.fromEntries(preceding);
    adsRenderReport();
    adsRenderApple();
  }
  await delivery;
}

const adsDate = days => new Date(Date.now() + days * 86400000).toISOString().slice(0, 10);
$('ads-period').elements.start.value = adsDate(-7);
$('ads-period').elements.end.value = adsDate(-1);
$('ads-platforms').addEventListener('click', event => {
  const next = event.target.closest('button')?.dataset.platform;
  if (!next || next === adsPlatform) return;
  adsPlatform = next;
  $('ads-target').value = '';
  for (const button of $('ads-platforms').querySelectorAll('button')) button.setAttribute('aria-pressed', button.dataset.platform === next);
  refreshAds().catch(error => status(error.message));
});
$('ads-period').addEventListener('submit', event => {
  event.preventDefault();
  refreshAds().catch(error => status(error.message));
});
$('ads-target').addEventListener('input', adsRenderDiagnostics);
$('ads-apple-fetch').addEventListener('click', async () => {
  const button = $('ads-apple-fetch');
  const stamp = generation;
  const out = $('ads-apple-feed');
  const message = $('ads-apple-feed-status');
  const { start, end } = $('ads-period').elements;
  const query = { start: start.value, end: end.value };
  out.replaceChildren();
  message.textContent = 'Appleの詳細レポートを確認中…';
  button.disabled = true;
  try {
    const data = await adsRequest('apple', { query });
    if (stamp !== generation) return;
    if (data.status !== 'ok') {
      const states = {
        not_configured: 'Appleの分析APIが未接続です。',
        request_required: 'Appleの継続レポートがまだ設定されていません。',
        awaiting_reports: 'Appleの詳細レポートの生成待ちです。',
      };
      message.textContent = states[data.status] || 'Appleの集計はまだ利用できません。';
      return;
    }
    adsAppleFeed = data;
    adsRenderApple();
    const expected = Math.round((Date.parse(data.end) - Date.parse(data.start)) / 86400000) + 1;
    message.textContent = data.start + ' 〜 ' + data.end + ' · ' + data.days.length + '/' + expected +
      '日分にデータあり。' + (data.days.length < expected ? ' 表示は取得できた日付分の集計です。' : '') +
      (!data.rows.length ? ' 表示条件を満たすキャンペーンがありません。' : '');
    if (data.rows.length) out.append(adsTable(['キャンペーントークン', '初回ダウンロード'],
      data.rows.map(row => [row.campaign, adsFormatted.format(row.downloads)]), 'Appleの初回ダウンロード'));
  } catch (error) {
    if (stamp === generation) message.textContent = error.message;
  } finally {
    button.disabled = false;
  }
});
$('ads-more').addEventListener('click', () => adsLoadDelivery(adsPlatform, adsRevision, true));
$('ads-confirm').addEventListener('close', () => {
  const change = adsPending;
  adsPending = null;
  if (!change || $('ads-confirm').returnValue !== 'confirm') return;
  perform(async () => {
    const stamp = adsRevision;
    const { platform, item } = change;
    const updated = await adsRequest(platform, { body: item });
    if (stamp !== adsRevision) return;
    const row = [...$('ads-campaigns').children].find(row => row.dataset.campaignId === item.id);
    row?.replaceWith(adsRow(platform, updated.item, updated.accountId));
    status(item.status === 'ACTIVE' ? '媒体でキャンペーンを有効にしました。' : '媒体でキャンペーンを停止しました。');
  });
});
$('ads-export').addEventListener('click', () => {
  if ($('ads-export').hidden) return;
  const rows = [['platform', 'account_currency', 'timezone', 'coverage_partial', 'level', 'date', 'id', 'name', ...adsMath.keys]];
  for (const [platform, report] of Object.entries(adsReports)) {
    if (!report.connected) continue;
    for (const row of report.rows) rows.push([platform, report.currency, report.timezone, report.partial,
      report.level, row.date, row.id, row.name, ...adsMath.keys.map(key => key === 'spendMicros' && row[key] != null ? row[key] / 1e6 : row[key])]);
  }
  rows[0][8] = 'spend_in_account_currency';
  adsDownload('mefrion-ads.csv', rows);
});
$('ads-apple-template').addEventListener('click', () => {
  const url = URL.createObjectURL(new Blob([adsMath.appleColumns.join(',') + '\r\n'], { type: 'text/csv;charset=utf-8' }));
  const anchor = node('a');
  anchor.href = url;
  anchor.download = 'mefrion-apple-campaign-template.csv';
  anchor.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
});
$('ads-apple-file').addEventListener('change', async event => {
  const file = event.target.files[0];
  if (!file) return;
  const stamp = generation;
  try {
    if (file.size > 500_000) throw Error('500KB以下のCSVを指定してください。');
    const rows = adsMath.parseAppleFile(await file.text());
    if (stamp !== generation) return;
    adsAppleRows = rows;
    $('ads-apple-status').textContent = rows.length + '件のキャンペーンを読み込みました。';
    adsRenderApple();
  } catch (error) {
    if (stamp === generation) $('ads-apple-status').textContent = error.message;
  } finally {
    event.target.value = '';
  }
});
$('ads-link-form').addEventListener('submit', event => {
  event.preventDefault();
  const values = new FormData(event.currentTarget);
  $('ads-link-result').hidden = true;
  try {
    const url = new URL(values.get('base'));
    const campaign = values.get('campaign');
    if (url.origin !== 'https://apps.apple.com' || url.username || url.password ||
        !/\/app\/(?:[^/]+\/)?id6825337314\/?$/.test(url.pathname) ||
        !/^\d+$/.test(url.searchParams.get('pt') || '') || !url.searchParams.get('ct') ||
        !/^[A-Za-z0-9_-]{1,40}$/.test(campaign)) throw Error();
    const output = new URL(url.origin + url.pathname);
    output.searchParams.set('pt', url.searchParams.get('pt'));
    output.searchParams.set('ct', campaign);
    output.searchParams.set('mt', '8');
    $('ads-link-url').value = output.href;
    $('ads-link-result').hidden = false;
    $('ads-link-status').textContent = '広告ごとに異なる識別名を使ってください。';
  } catch {
    $('ads-link-status').textContent = 'MEFRIONのApp Store Connectで発行したキャンペーンリンクを入力してください。';
  }
});
$('ads-copy').addEventListener('click', async () => {
  try {
    await navigator.clipboard.writeText($('ads-link-url').value);
    $('ads-link-status').textContent = 'リンクをコピーしました。';
  } catch {
    $('ads-link-url').select();
    $('ads-link-status').textContent = '選択したリンクをコピーしてください。';
  }
});

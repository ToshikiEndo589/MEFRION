const appId = '6825337314';
const dayMs = 86400000;
const tokenPattern = /^[A-Za-z0-9_-]{1,30}$/;

export function trackingLink(raw) {
  if (typeof raw !== 'string' || raw.length > 2048) return null;
  let url;
  try { url = new URL(raw); } catch { return null; }
  if (url.origin !== 'https://apps.apple.com' || url.username || url.password ||
      !new RegExp('^/(?:[a-z]{2}/)?app/(?:[^/]+/)?id' + appId + '/?$').test(url.pathname) ||
      url.searchParams.getAll('pt').length !== 1 || !/^\d{1,24}$/.test(url.searchParams.get('pt')) ||
      url.searchParams.getAll('ct').length > 1) return null;
  return url;
}

export function variantLink(base, token) {
  const url = trackingLink(base);
  if (!url || !tokenPattern.test(token)) throw Error('MEFRIONのApp Store計測リンクを入力してください。');
  url.searchParams.set('ct', token);
  url.hash = '';
  return url.href;
}

export function creativeToken(creative) {
  const story = creative?.object_story_spec;
  const linkData = story?.link_data;
  // Carousels, dynamic creatives and URL overrides cannot establish one link per arm.
  if (!creative || creative.asset_feed_spec || linkData?.child_attachments?.length || creative.url_tags?.trim()) return null;
  const links = [creative.link_url, linkData?.link, linkData?.call_to_action?.value?.link,
    story?.video_data?.call_to_action?.value?.link].filter(Boolean);
  const params = links.map(raw => {
    const url = trackingLink(raw);
    const token = url?.searchParams.get('ct');
    return tokenPattern.test(token || '') ? { token, provider: url.searchParams.get('pt') } : null;
  });
  const first = params[0];
  return first && params.every(value => value?.token === first.token && value.provider === first.provider) ? first : null;
}

export function experimentWindow(start, end, timezone) {
  const parse = value => /^\d{10}$/.test(String(value)) ? Number(value) * 1000 : Date.parse(value);
  const begins = parse(start), finishes = parse(end);
  if (!Number.isFinite(begins) || !Number.isFinite(finishes) || finishes <= begins || finishes - begins > 7 * dayMs) return null;
  const utcDay = time => new Date(time).toISOString().slice(0, 10);
  let local;
  try { local = new Intl.DateTimeFormat('sv-SE', { timeZone: timezone, year: 'numeric', month: '2-digit', day: '2-digit' }); }
  catch { return null; }
  if (!timezone) return null;
  return {
    startAt: new Date(begins).toISOString(), endAt: new Date(finishes).toISOString(),
    metaStart: local.format(begins), metaEnd: local.format(finishes - 1),
    appleStart: utcDay(begins), appleEnd: utcDay(finishes + dayMs - 1),
    readyAt: new Date(Date.parse(utcDay(finishes + dayMs - 1)) + 3 * dayMs).toISOString(),
  };
}

// Upper tail of a standard normal, sufficient for the two-sided rate test.
function normalTail(z) {
  const t = 1 / (1 + 0.2316419 * Math.abs(z));
  return Math.exp(-z * z / 2) / Math.sqrt(2 * Math.PI) * t *
    (0.319381530 + t * (-0.356563782 + t * (1.781477937 + t * (-1.821255978 + t * 1.330274429))));
}

export function evaluateExperiment(study, apple, now = Date.now()) {
  const arms = study.arms.map(arm => {
    const count = apple?.rows?.find(row => row.campaign === arm.token)?.downloads;
    const downloads = Number.isSafeInteger(count) && count >= 5 ? count : null;
    return { ...arm, downloads, cpiMicros: arm.spendMicros > 0 && downloads ? arm.spendMicros / downloads : null };
  });
  const outcome = (state, other = {}) => ({ state, arms, ...other });
  if (study.canceled) return outcome('canceled');
  if (now < Date.parse(study.endAt)) return outcome('running');
  if (now < Date.parse(study.readyAt)) return outcome('settling');
  if (apple?.status !== 'ok') return outcome('apple_pending');
  const covered = new Set(apple.days);
  for (let time = Date.parse(study.appleStart); time <= Date.parse(study.appleEnd); time += dayMs) {
    if (!covered.has(new Date(time).toISOString().slice(0, 10))) return outcome('apple_pending');
  }
  if (!study.comparable || arms.some(arm => !arm.token || arm.cpiMicros == null || arm.downloads < 20)) return outcome('insufficient');
  const ranked = [...arms].sort((a, b) => a.cpiMicros - b.cpiMicros);
  const [best, second] = ranked;
  const tests = arms.length * (arms.length - 1) / 2;
  const savings = 1 - best.cpiMicros / second.cpiMicros;
  const adjustedP = Math.min(1, tests * Math.max(...ranked.slice(1).map(peer => {
    const logRatio = Math.log(peer.cpiMicros / best.cpiMicros);
    return 2 * normalTail(logRatio / Math.sqrt(1 / best.downloads + 1 / peer.downloads));
  })));
  return adjustedP < 0.05 && savings >= 0.15
    ? outcome('winner', { winner: best.id, savings, adjustedP }) : outcome('inconclusive', { savings, adjustedP });
}

export function estimateSpend(cpi, count, improvement) {
  if (!(cpi > 0 && cpi <= 1000000 && count >= 2 && count <= 5 && improvement >= 0.05 && improvement <= 0.5)) return null;
  // Approximate fixed-window power (80%) using the log Poisson rate ratio.
  const tests = count * (count - 1) / 2;
  let critical = 1.96;
  while (2 * normalTail(critical) > 0.05 / tests) critical += 0.01;
  const rateRatio = 1 / (1 - improvement);
  const downloads = Math.ceil(Math.max(20, ((critical + 0.842) ** 2) * (1 + 1 / rateRatio) / Math.log(rateRatio) ** 2));
  return { downloads, perArm: Math.ceil(cpi * downloads), total: Math.ceil(cpi * downloads) * count };
}

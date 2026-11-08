import { estimateSpend, evaluateExperiment, trackingLink, variantLink } from './experiments.js';
import { csvCell } from './insights.js';

const $ = id => document.getElementById(id);
const formats = { portrait: 1920, feed: 1350, square: 1080 };
const looks = [
  { name: 'A · シネマ', background: '#211937', text: '#fff9f6', accent: '#e4caff', split: .76 },
  { name: 'B · フォトカード', background: '#f7e9e3', text: '#35223e', accent: '#974256', split: .70 },
  { name: 'C · マガジン', background: '#eae6f9', text: '#252043', accent: '#5c4294', split: .64 },
];
const number = new Intl.NumberFormat('ja-JP', { maximumFractionDigits: 1 });
const show = value => value == null ? '—' : number.format(value);
const percent = value => value == null ? '—' : show(value * 100) + '%';
const element = (tag, text) => Object.assign(document.createElement(tag), text == null ? {} : { textContent: text });

function cover(ctx, image, x, y, width, height) {
  const scale = Math.max(width / image.width, height / image.height);
  const cropWidth = width / scale, cropHeight = height / scale;
  ctx.drawImage(image, (image.width - cropWidth) / 2, (image.height - cropHeight) / 2, cropWidth, cropHeight, x, y, width, height);
}

async function renderCreative(image, height, look, headline) {
  const width = 1080;
  const canvas = Object.assign(document.createElement('canvas'), { width, height });
  const ctx = canvas.getContext('2d', { alpha: false });
  const margin = look === looks[1] ? 64 : 0;
  const split = Math.round(height * look.split);
  ctx.fillStyle = look.background;
  ctx.fillRect(0, 0, width, height);
  cover(ctx, image, margin, margin, width - margin * 2, split - margin);
  ctx.fillStyle = look.accent;
  ctx.font = 'bold 28px sans-serif';
  ctx.fillText('M E F R I O N', 78, split + 46);
  ctx.fillStyle = look.text;
  ctx.font = 'bold 67px sans-serif';
  ctx.fillText(headline, 76, split + 116, width - 152);
  ctx.font = '32px sans-serif';
  ctx.fillText('App Storeで見る  →', 78, split + 168);
  const blob = await new Promise(resolve => canvas.toBlob(resolve, 'image/jpeg', 0.91));
  canvas.width = 1;
  canvas.height = 1;
  if (!blob) throw Error('広告画像を生成できませんでした。');
  return blob;
}

// Store-only ZIP keeps photos on this device and avoids adding a runtime dependency.
const crcTable = Array.from({ length: 256 }, (_, i) => {
  for (let j = 0; j < 8; j++) i = (i >>> 1) ^ (i & 1 ? 0xedb88320 : 0);
  return i;
});
export async function creativeArchive(files) {
  const encoder = new TextEncoder(), body = [], directory = [];
  let offset = 0, directorySize = 0;
  const header = size => new DataView(new ArrayBuffer(size));
  const short = (view, at, value) => view.setUint16(at, value, true);
  const long = (view, at, value) => view.setUint32(at, value, true);
  for (const [name, blob] of files) {
    const filename = encoder.encode(name);
    const bytes = new Uint8Array(await blob.arrayBuffer());
    let crc = 0xffffffff;
    for (const byte of bytes) crc = (crc >>> 8) ^ crcTable[(crc ^ byte) & 255];
    crc = (crc ^ 0xffffffff) >>> 0;
    const local = header(30), central = header(46);
    long(local, 0, 0x04034b50); short(local, 4, 20); short(local, 12, 33);
    long(local, 14, crc); long(local, 18, bytes.length); long(local, 22, bytes.length); short(local, 26, filename.length);
    long(central, 0, 0x02014b50); short(central, 4, 20); short(central, 6, 20); short(central, 14, 33);
    long(central, 16, crc); long(central, 20, bytes.length); long(central, 24, bytes.length); short(central, 28, filename.length);
    long(central, 42, offset);
    body.push(local.buffer, filename, bytes);
    directory.push(central.buffer, filename);
    offset += 30 + filename.length + bytes.length;
    directorySize += 46 + filename.length;
  }
  const end = header(22);
  long(end, 0, 0x06054b50); short(end, 8, files.length); short(end, 10, files.length);
  long(end, 12, directorySize); long(end, 16, offset);
  return new Blob([...body, ...directory, end.buffer], { type: 'application/zip' });
}

export function mountExperiments({ request, table, money, session }) {
  const studio = $('ads-experiments');
  const create = $('experiment-create'), exportForm = $('experiment-export'), plan = $('experiment-plan'), watch = $('experiment-watch');
  const previews = $('experiment-previews'), createStatus = $('experiment-create-status'), exportStatus = $('experiment-export-status');
  const result = $('experiment-result'), watchStatus = $('experiment-watch-status');
  const downloadButton = exportForm.querySelector('button');
  let variants = [], selected = new Set(), sessionStamp = null, trackedId = '', timer, queryRevision = 0, batchRevision = 0;
  const cacheKey = 'mefrion.ads.experiment.last-id';
  const validId = id => /^\d{1,24}$/.test(id || '');
  const storeId = id => { try { localStorage.setItem(cacheKey, id); } catch {} };
  const readId = () => { try { return localStorage.getItem(cacheKey); } catch { return ''; } };
  const forgetImages = () => {
    for (const item of variants) URL.revokeObjectURL(item.url);
    if (exportStatus.dataset.url) URL.revokeObjectURL(exportStatus.dataset.url);
    delete exportStatus.dataset.url;
    variants = []; selected = new Set(); previews.replaceChildren(); downloadButton.disabled = true;
  };
  function drawPreviews() {
    for (const [layout, look] of looks.entries()) {
      const group = element('details');
      group.className = 'experiment-preview-group';
      group.open = layout === 0;
      group.append(element('summary', look.name));
      const grid = element('div'); grid.className = 'experiment-grid';
      for (const item of variants.filter(row => row.layout === layout)) {
        const label = element('label'); label.className = 'experiment-option';
        const image = Object.assign(element('img'), { src: item.url, alt: '', loading: 'lazy' });
        const check = Object.assign(element('input'), { type: 'checkbox', value: item.name });
        check.addEventListener('change', () => {
          const first = [...selected][0];
          if (check.checked && (selected.size >= 5 || (first && first.layout !== layout))) {
            check.checked = false;
            exportStatus.textContent = '同じ枠から最大5案まで選べます。';
            return;
          }
          if (check.checked) selected.add(item);
          else selected.delete(item);
          downloadButton.disabled = selected.size < 2;
          exportStatus.textContent = selected.size ? selected.size + '案を選択中' : '';
        });
        const caption = element('span'); caption.append(check, ' ' + item.name);
        label.append(image, caption); grid.append(label);
      }
      group.append(grid); previews.append(group);
    }
  }

  create.addEventListener('submit', async event => {
    event.preventDefault();
    const button = create.querySelector('button');
    const form = new FormData(create);
    const files = form.getAll('photos');
    const headline = form.get('headline').trim();
    const height = formats[form.get('ratio')];
    if (!headline || !height || files.length < 2 || files.length > 8 || files.some(file =>
      !['image/jpeg', 'image/png', 'image/webp'].includes(file.type) || file.size < 1 || file.size > 15 * 1024 * 1024)) {
      createStatus.textContent = '見出しと、JPEG・PNG・WebPの写真を2〜8枚（各15 MB以下）選んでください。';
      return;
    }
    const stamp = ++batchRevision;
    const next = [];
    button.disabled = true;
    createStatus.textContent = '広告画像を作成しています…';
    try {
      for (const [index, file] of files.entries()) {
        const image = await createImageBitmap(file);
        try {
          if (image.width * image.height > 26_000_000 || Math.min(image.width, image.height) < 320) {
            throw Error('写真は短辺320px以上・2600万画素以下にしてください。');
          }
          for (const [layout, look] of looks.entries()) {
            if (stamp !== batchRevision) return;
            const name = String.fromCharCode(65 + layout) + String(index + 1).padStart(2, '0');
            next.push({ name, layout, blob: await renderCreative(image, height, look, headline) });
          }
        } finally { image.close(); }
      }
      if (stamp !== batchRevision) return;
      forgetImages();
      variants = next.map(item => ({ ...item, url: URL.createObjectURL(item.blob) }));
      drawPreviews();
      createStatus.textContent = variants.length + '案を生成しました。';
      exportStatus.textContent = '';
    } catch (error) {
      if (stamp === batchRevision) createStatus.textContent = error instanceof DOMException ? '読み込めない写真がありました。別のファイルをお試しください。' : error.message;
    } finally {
      if (stamp === batchRevision) button.disabled = false;
    }
  });

  exportForm.addEventListener('submit', async event => {
    event.preventDefault();
    const base = new FormData(exportForm).get('base');
    if (selected.size < 2 || !trackingLink(base)?.searchParams.get('ct')) {
      exportStatus.textContent = '2案以上と、App Store Connectで発行済みのMEFRIONの計測リンクが必要です。';
      return;
    }
    const stamp = batchRevision;
    const set = [...selected];
    const id = crypto.randomUUID().replaceAll('-', '').slice(0, 20);
    downloadButton.disabled = true;
    try {
      const rows = set.map(item => [item.name + '.jpg', variantLink(base, 'ig_' + id + '_' + item.name.toLowerCase())]);
      const csv = new Blob(['\uFEFF', [['画像', 'App Store計測リンク'], ...rows].map(row => row.map(csvCell).join(',')).join('\r\n')], { type: 'text/csv' });
      const zip = await creativeArchive([...set.map(item => [item.name + '.jpg', item.blob]), ['tracking-links.csv', csv]]);
      if (stamp !== batchRevision) return;
      const url = URL.createObjectURL(zip);
      const link = Object.assign(element('a', '画像と計測リンクをダウンロード'), { href: url, download: 'mefrion-ads-' + id + '.zip' });
      exportStatus.replaceChildren(link);
      const previous = exportStatus.dataset.url;
      if (previous) URL.revokeObjectURL(previous);
      exportStatus.dataset.url = url;
    } catch {
      if (stamp === batchRevision) exportStatus.textContent = 'ファイルを作成できませんでした。再度お試しください。';
    } finally {
      if (stamp === batchRevision) downloadButton.disabled = selected.size < 2;
    }
  });

  plan.addEventListener('submit', event => {
    event.preventDefault();
    const form = new FormData(plan);
    const estimate = estimateSpend(Number(form.get('cpi')), Number(form.get('variants')), Number(form.get('lift')) / 100);
    $('experiment-plan-result').textContent = estimate
      ? '目安は1案あたり ' + show(estimate.downloads) + '件・' + show(estimate.perArm) + '円、合計 ' + show(estimate.total) + '円。想定の差を約80%の確率で検出するための概算です。'
      : '現在の獲得単価と比較条件を確認してください。';
  });

  const stateText = {
    canceled: 'このテストはMetaでキャンセルされています。', running: '配信終了後に判定します。',
    settling: '終了後のダウンロードとAppleの集計を待っています。', apple_pending: 'Appleの詳細集計が揃うまで判定を保留します。',
    insufficient: '計測条件またはダウンロード数が不足しているため、判定を保留します。',
    inconclusive: '今回の結果から有力案は決められません。',
  };
  const issues = {
    tracking: '各広告に異なるMEFRIONの計測リンクを設定してください。', split: '配信グループを均等に割り当ててください。',
    adset: '全案を同じ広告セットに入れてください。', creative: '画像以外の広告文とボタンを揃えてください。',
    dates: '広告費を正しく比較できるよう、開始・終了を広告アカウントの午前0時に揃えてください。',
  };
  async function check() {
    if (!trackedId || document.hidden || session() === null) return;
    const stamp = ++queryRevision;
    const valid = () => stamp === queryRevision && session() === sessionStamp;
    watchStatus.textContent = 'MetaとAppleの集計を確認しています…';
    try {
      const data = await request('instagram', { query: { view: 'experiment', id: trackedId } });
      if (!valid()) return;
      if (!data.connected || !data.study) throw Error('Instagramの広告アカウントをMEFRION Adsに接続してください。');
      storeId(data.study.id);
      const { study } = data;
      let apple;
      if (!study.canceled && Date.now() >= Date.parse(study.endAt)) {
        const today = new Date().toISOString().slice(0, 10);
        apple = await request('apple', { query: { start: study.appleStart, end: study.appleEnd < today ? study.appleEnd : today } })
          .catch(() => null);
      }
      if (!valid()) return;
      const judged = evaluateExperiment(study, apple);
      const leader = judged.arms.find(arm => arm.id === judged.winner);
      const description = leader ? '有力案は「' + leader.name + '」。次点より初回ダウンロード単価が ' + percent(judged.savings) + ' 低くなりました。' : stateText[judged.state];
      const notice = element('p', description); notice.className = 'experiment-result-notice';
      const warning = study.issues.map(code => issues[code]).filter(Boolean).join(' ');
      const rows = judged.arms.map(arm => [arm.name, arm.token || '—', arm.share == null ? '—' : show(arm.share) + '%',
        show(arm.impressions), show(arm.clicks), money(arm.spendMicros, study.currency), show(arm.downloads), money(arm.cpiMicros, study.currency)]);
      result.replaceChildren(element('h4', study.name), notice);
      if (warning) result.append(element('p', warning));
      result.append(table(['広告', '計測トークン', '割り当て', '表示', 'クリック', '広告費', '初回DL', '初回DL単価'], rows, '画像テスト結果'));
      watchStatus.textContent = 'Meta ' + study.metaStart + '〜' + study.metaEnd + ' / Apple ' + study.appleStart + '〜' + study.appleEnd;
    } catch (error) {
      if (valid()) watchStatus.textContent = error.message;
    } finally {
      if (valid()) timer = setTimeout(check, 15 * 60 * 1000);
    }
  }

  watch.addEventListener('submit', event => {
    event.preventDefault();
    const id = new FormData(watch).get('study').trim();
    if (!validId(id)) return;
    clearTimeout(timer);
    trackedId = id;
    result.replaceChildren();
    check();
  });
  document.addEventListener('visibilitychange', () => {
    if (!document.hidden && trackedId && session() !== null) {
      clearTimeout(timer);
      check();
    }
  });
  studio.hidden = false;
  return {
    resume() {
      const active = session();
      if (active === null || active === sessionStamp) return;
      sessionStamp = active;
      const saved = readId();
      if (validId(saved)) {
        watch.elements.study.value = saved;
        trackedId = saved;
        check();
      }
    },
    reset() {
      clearTimeout(timer);
      queryRevision++;
      batchRevision++;
      sessionStamp = null;
      trackedId = '';
      forgetImages();
      for (const form of [create, exportForm, plan, watch]) form.reset();
      create.querySelector('button').disabled = false;
      for (const target of [createStatus, exportStatus, watchStatus, result, $('experiment-plan-result')]) target.replaceChildren();
    },
  };
}

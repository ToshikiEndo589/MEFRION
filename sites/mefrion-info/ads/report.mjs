import { AdsError } from './x-ads.mjs';

const dayMs = 86_400_000;
export const day = value => new Date(value).toISOString().slice(0, 10);
export const addDays = (date, count) => day(Date.parse(date) + count * dayMs);
export const numericId = value => typeof value === 'string' && /^\d{1,24}$/.test(value);
export const currencyCode = value => /^[A-Z]{3}$/.test(value || '') ? value : null;
export const title = (value, fallback) => typeof value === 'string' && value ? value.slice(0, 255) : fallback;

export function number(value) {
  if (typeof value !== 'number' && (typeof value !== 'string' || !/^\d+(\.\d+)?$/.test(value))) return null;
  const result = Number(value);
  return Number.isFinite(result) && result >= 0 && result <= Number.MAX_SAFE_INTEGER ? result : null;
}

export function micros(value, unit = 1_000_000) {
  const amount = number(value);
  if (amount === null) return null;
  const result = Math.round(amount * unit);
  return Number.isSafeInteger(result) ? result : null;
}

export function reportQuery(params, now = new Date()) {
  const today = day(now);
  const end = params.get('end') ?? addDays(today, -1);
  const start = params.get('start') ?? addDays(today, -7);
  const valid = date => /^\d{4}-\d{2}-\d{2}$/.test(date) &&
    Number.isFinite(Date.parse(date)) && day(Date.parse(date)) === date;
  if (!valid(start) || !valid(end) || start < '2020-01-01' || end > today ||
      start > end || (Date.parse(end) - Date.parse(start)) / dayMs >= 31) {
    throw new AdsError(400, 'invalid_dates');
  }
  const level = params.get('level') ?? 'campaign';
  if (!['campaign', 'adgroup', 'ad'].includes(level)) throw new AdsError(400, 'bad_request');
  return { start, end, level };
}

export function requireChange(input, validId) {
  if (!validId(input?.id) || !['ACTIVE', 'PAUSED'].includes(input?.status) ||
      typeof input?.updatedAt !== 'string' || !input.updatedAt || input.updatedAt.length > 64) {
    throw new AdsError(400, 'bad_request');
  }
}

export function verifyChange(item, input) {
  if (item.id !== input.id) throw new AdsError(404, 'campaign_missing');
  if (!item.updatedAt || item.updatedAt !== input.updatedAt ||
      item.status !== (input.status === 'ACTIVE' ? 'PAUSED' : 'ACTIVE')) {
    throw new AdsError(409, 'campaign_changed');
  }
  if (input.status === 'ACTIVE' && (!item.canActivate || input.totalMicros !== item.totalMicros ||
      input.currency !== item.currency)) throw new AdsError(409, 'activation_blocked');
}

export async function upstream(fetcher, url, headers, body, report = false) {
  try {
    const response = await fetcher(url, {
      method: body ? 'POST' : 'GET', headers, body, redirect: 'error', signal: AbortSignal.timeout(4500),
    });
    if (response.status === 429) throw new AdsError(429, 'provider_rate_limit');
    if (response.status === 401 || response.status === 403) throw new AdsError(502, 'provider_access_denied');
    if (report && response.status === 400) throw new AdsError(502, 'report_parameters_rejected');
    if (!response.ok) throw Error();
    return await response.json();
  } catch (error) {
    if (error instanceof AdsError) throw error;
    throw new AdsError(502, body ? 'write_unconfirmed' : 'provider_unavailable');
  }
}

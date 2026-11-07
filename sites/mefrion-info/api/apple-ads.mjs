import { collectAppleCampaigns } from '../analytics/apple.mjs';
import { reportQuery } from '../ads/report.mjs';
import { AdsError } from '../ads/x-ads.mjs';
import { authorize } from './x-ads.mjs';

export function appleAdsHandler(env = process.env, fetcher = fetch) {
  return async (req, res) => {
    res.setHeader('Cache-Control', 'no-store');
    res.setHeader('Content-Type', 'application/json; charset=utf-8');
    res.setHeader('X-Content-Type-Options', 'nosniff');
    res.setHeader('X-Robots-Tag', 'noindex, nofollow');
    const send = (status, payload) => {
      res.statusCode = status;
      res.end(JSON.stringify(payload));
    };
    try {
      if (req.method !== 'GET') throw new AdsError(405, 'method_not_allowed');
      await authorize(req.headers, fetcher);
      if (env.VERCEL_ENV !== 'production') return send(200, { status: 'not_configured', rows: [] });
      const query = reportQuery(new URL(req.url, 'https://mefrion.vercel.app').searchParams);
      const result = await collectAppleCampaigns(env, query, fetcher);
      return send(200, { start: query.start, end: query.end, ...result });
    } catch (error) {
      if (error instanceof AdsError) return send(error.status, { code: error.message });
      return send(502, { code: 'apple_report_unavailable' });
    }
  };
}

export default appleAdsHandler();

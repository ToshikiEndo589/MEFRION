import { adsHandler } from './x-ads.mjs';

export default adsHandler(process.env, fetch, 'instagram');

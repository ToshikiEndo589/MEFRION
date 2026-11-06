import {randomUUID} from 'node:crypto';
import {waitUntil} from '@vercel/functions';
import site from '../worker/index.js';
export async function sharedArrival(req,res,url){
 const match=/^\/open\/(instagram|x|system)$/.exec(url.pathname);if(!match)return false;
 if(req.method!=='GET'&&req.method!=='HEAD'){res.statusCode=405;res.end();return true;}
 const source=match[1],raw=/\bmefrion_visit=([0-9a-f-]{36})\b/i.exec(req.headers.cookie||'')?.[1];
 const installation=raw&&/^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(raw)?raw:randomUUID();
 if(req.method==='GET'&&!/bot|crawler|spider|preview/i.test(req.headers['user-agent']||'')){
  waitUntil((async()=>{try{const response=await site.fetch(new Request('https://mefrion.vercel.app/console/config.json'));const config=await response.json();await fetch(config.url+'/rest/v1/rpc/mefrion_product_events',{method:'POST',headers:{apikey:config.anon_key,'Content-Type':'application/json'},body:JSON.stringify({p_install:installation,p_events:[{id:randomUUID(),name:'share_visit',detail:source,version:'web'}]}),signal:AbortSignal.timeout(2500)});}catch{/* No personal URL, cookie, credentials or exceptions are logged. */}})());
 }
 res.statusCode=302;res.setHeader('Cache-Control','no-store');res.setHeader('Set-Cookie','mefrion_visit='+installation+'; Path=/open; Max-Age=2592000; HttpOnly; Secure; SameSite=Lax');res.setHeader('Referrer-Policy','no-referrer');res.setHeader('Location','https://apps.apple.com/jp/app/id6825337314');res.end();return true;
}

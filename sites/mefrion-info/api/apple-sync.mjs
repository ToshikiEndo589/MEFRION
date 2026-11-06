import {authorized,collectApple} from '../analytics/apple.mjs';
import site from '../worker/index.js';
export default async function handler(req,res){
 res.setHeader('Cache-Control','no-store');res.setHeader('Content-Type','application/json');res.setHeader('X-Content-Type-Options','nosniff');
 if(req.method!=='GET'){res.statusCode=405;res.end('{}');return;}
 if(process.env.VERCEL_ENV!=='production'||!authorized(req.headers?.authorization,process.env.CRON_SECRET)){res.statusCode=401;res.end('{}');return;}
 let result;try{result=await collectApple(process.env);}catch(e){const safe=new Set(['apple_auth','apple_api','download','integrity','schema','origin','size','budget','pagination']);result={status:safe.has(e?.message)?e.message:'sync_failure',rows:[]};}
 try{const config=await (await site.fetch(new Request('https://mefrion.vercel.app/console/config.json'))).json();const response=await fetch(config.url+'/rest/v1/rpc/mefrion_apple_metrics_ingest',{method:'POST',headers:{apikey:config.anon_key,'Content-Type':'application/json'},body:JSON.stringify({p_token:process.env.CRON_SECRET,p_rows:result.rows,p_status:result.status}),signal:AbortSignal.timeout(8000)});if(!response.ok||await response.text()!=='true')throw Error('save');}
 catch{res.statusCode=503;res.end('{"status":"save_failed"}');return;}
 res.statusCode=200;res.end(JSON.stringify({status:result.status,days:result.rows.length}));
}

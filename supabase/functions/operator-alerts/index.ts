import {serveMonitored} from '../_shared/security_monitor.ts';
const base=Deno.env.get('SUPABASE_URL')||'';
const serviceKey=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')||'';
const sendKey=Deno.env.get('BREVO_API_KEY')||'';
const reply=(status:number)=>new Response(JSON.stringify({ok:status===200}),{status,headers:{'Content-Type':'application/json','Cache-Control':'no-store'}});
const rpc=async(name:string,body:Record<string,unknown>)=>{
 const response=await fetch(base+'/rest/v1/rpc/mefrion_'+name,{method:'POST',headers:{apikey:serviceKey,Authorization:'Bearer '+serviceKey,'Content-Type':'application/json'},body:JSON.stringify(body),signal:AbortSignal.timeout(8000)});
 if(!response.ok)throw Error('rpc_failed');return response.json();
};
serveMonitored('operator-alerts',async request=>{
 if(request.method!=='POST')return reply(405);
 const token=request.headers.get('x-mefrion-worker')||'';
 if(token.length<32||token.length>512)return reply(401);
 if(!base||!serviceKey||!sendKey)return reply(503);
 try{
  if(await rpc('cloud_worker_authorize',{p_token:token})!==true)return reply(401);
  const alert=await rpc('operator_alert_claim',{});
  if(!alert)return reply(200);
  const lines=[
   `未対応の通報：${alert.reports}件`,
   `30分以上待っている投稿：${alert.posts}件`,
   `期限を過ぎた問い合わせ：${alert.cases}件`,
   `失敗した処理：${alert.jobs}件`,
   `直近1時間のサーバーエラー：${alert.server_errors}件`,
   '',
   '運営ダッシュボード: https://mefrion.vercel.app/console'
  ];
  let sent=false;
  try{
   const result=await fetch('https://api.brevo.com/v3/smtp/email',{
    method:'POST',headers:{'Content-Type':'application/json','api-key':sendKey,'Accept':'application/json'},
    body:JSON.stringify({sender:{name:'MEFRION',email:'mefrion@mefrion.com'},to:[{email:'mefrion@mefrion.com'}],subject:'MEFRION｜運営の確認事項があります',textContent:lines.join('\n')}),
    signal:AbortSignal.timeout(8000)
   });
   sent=result.ok;
  }finally{await rpc('operator_alert_finish',{p_claim:alert.claim,p_sent:sent});}
  return reply(sent?200:503);
 }catch{return reply(503);}
});

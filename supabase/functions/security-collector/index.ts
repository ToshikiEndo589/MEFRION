import {serveMonitored} from '../_shared/security_monitor.ts';
import {verifySender} from './trust.ts';
import {KINDS,canonicalTarget} from '../_shared/security_classifier.mjs';
const headers={'Cache-Control':'no-store','Content-Type':'application/json','X-Content-Type-Options':'nosniff'};
const reply=(status:number)=>new Response(JSON.stringify({ok:status===200}),{status,headers});
serveMonitored('security-collector',async request=>{
 if(request.method!=='POST')return reply(405);
 const auth=request.headers.get('Authorization')||'';
 if(!auth.startsWith('Bearer '))return reply(401);
 try{await verifySender(auth.slice(7));}catch{return reply(401);}
 try{
  if(Number(request.headers.get('Content-Length'))>8192)return reply(413);
  let length=0;const chunks:Uint8Array[]=[];const reader=request.body?.getReader();if(!reader)return reply(400);
  for(;;){const {done,value}=await reader.read();if(done)break;length+=value.length;if(length>8192){await reader.cancel();return reply(413);}chunks.push(value);}
  const bytes=new Uint8Array(length);let offset=0;for(const part of chunks){bytes.set(part,offset);offset+=part.length;}
  const data=JSON.parse(new TextDecoder().decode(bytes));const e=data.event;
  if(e!==null&&(!e||!KINDS.includes(e.kind)||!['info','low','medium','high','critical'].includes(e.severity)||!['observed','denied','limited','failed','allowed'].includes(e.outcome)||!Number.isInteger(e.status)||e.status<100||e.status>599||!/^[0-9a-f-]{36}$/i.test(e.id)))return reply(400);
  if(e&& !['/[secret-probe]','/[traversal]','/[injection]'].includes(e.target)&&canonicalTarget(e.target)!==e.target)return reply(400);
  const event=e?{id:e.id,kind:e.kind,severity:e.severity,outcome:e.outcome,status:e.status,target:e.target,country:typeof e.country==='string'&&/^[A-Z]{2}$/.test(e.country)?e.country:null,request_id:typeof e.request_id==='string'&&/^[\w:.-]{1,120}$/.test(e.request_id)?e.request_id:null}:null;
  const key=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;const base=Deno.env.get('SUPABASE_URL')!;
  const r=await fetch(base+'/rest/v1/rpc/mefrion_security_ingest',{method:'POST',headers:{apikey:key,Authorization:'Bearer '+key,'Content-Type':'application/json'},body:JSON.stringify({p_source:'vercel',p_event:event,p_ip:typeof data.address==='string'&&data.address.length<65?data.address:null,p_lost:Number.isInteger(data.lost)&&data.lost>=0&&data.lost<=100000?data.lost:0}),signal:AbortSignal.timeout(2500)});
  return reply(r.ok&&(await r.json())===true?200:503);
 }catch{return reply(400);}
});

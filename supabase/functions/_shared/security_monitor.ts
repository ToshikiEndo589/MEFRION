import { classify } from './security_classifier.mjs';
let lastHeartbeat = 0, minute = 0, sent = 0, lost = 0;
export function serveMonitored(name: string, handler: (request: Request) => Response | Promise<Response>) {
  Deno.serve(monitoredHandler(name,handler));
}
export function monitoredHandler(name:string,handler:(request:Request)=>Response|Promise<Response>){
  return async (request: Request) => {
    let response: Response;
    try { response = await handler(request); }
    catch { response = new Response(JSON.stringify({error:'temporarily_unavailable'}), { status: 503, headers: { 'Content-Type':'application/json', 'Cache-Control':'no-store' } }); }
    const url = new URL(request.url);
    const event = classify({path:url.pathname,query:url.search,status:response.status,method:request.method,edge:name});
    const now=Date.now();
    if (event || now-lastHeartbeat>300_000) {
      if(now-minute>60_000){minute=now;sent=0;}
      if(++sent>500){if(event)lost++;return response;}
      lastHeartbeat=now;
      const dropped=Math.min(lost,100_000);lost-=dropped;
      const pending=(async()=>{
        try{
          const key=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');const base=Deno.env.get('SUPABASE_URL');
          if(!key||!base)throw Error('unavailable');
          const address=request.headers.get('cf-connecting-ip')||request.headers.get('x-forwarded-for')?.split(',').at(-1)?.trim()||null;
          const trace=request.headers.get('sb-request-id')||request.headers.get('cf-ray');
          const country=request.headers.get('cf-ipcountry');
          const r=await fetch(base+'/rest/v1/rpc/mefrion_security_ingest',{method:'POST',headers:{apikey:key,Authorization:'Bearer '+key,'Content-Type':'application/json'},body:JSON.stringify({p_source:'edge:'+name,p_event:event?{...event,id:crypto.randomUUID(),request_id:trace&&/^[\w:.-]{1,120}$/.test(trace)?trace:null,country:country&&/^[A-Z]{2}$/.test(country)?country:null}:null,p_ip:address,p_lost:dropped}),signal:AbortSignal.timeout(2500)});
          if(!r.ok||(await r.json())!==true)throw Error('delivery');
        }catch{lost+=dropped+(event?1:0);console.warn(JSON.stringify({component:'mefrion.security',event:'delivery_failed',source:name}));}
      })();
      const runtime=(globalThis as unknown as {EdgeRuntime?:{waitUntil:(p:Promise<unknown>)=>void}}).EdgeRuntime;
      if(runtime?.waitUntil)runtime.waitUntil(pending);else await pending;
    }
    return response;
  };
}

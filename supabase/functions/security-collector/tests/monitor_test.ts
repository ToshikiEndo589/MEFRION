import {monitoredHandler} from '../../_shared/security_monitor.ts';
function assert(ok:boolean,label:string){if(!ok)throw Error(label);}
Deno.test('monitor preserves response and strips original credentials/body/query from telemetry',async()=>{
 const oldFetch=globalThis.fetch,oldBase=Deno.env.get('SUPABASE_URL'),oldKey=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');let payload:Record<string,unknown>={};
 try{
  Deno.env.set('SUPABASE_URL','https://backend-fixture.invalid');Deno.env.set('SUPABASE_SERVICE_ROLE_KEY','fixture-server-only-key');
  globalThis.fetch=async(_input,init)=>{payload=JSON.parse(String(init?.body));return new Response('true',{status:200});};
  const response=await monitoredHandler('private-image',()=>new Response('original denial',{status:403,headers:{'x-original':'preserved'}}))(new Request('https://backend-fixture.invalid/functions/v1/private-image?email=private-marker@example.invalid&token=client-secret-marker',{method:'POST',headers:{authorization:'Bearer client-private-marker','x-forwarded-for':'192.0.2.1','cf-ipcountry':'JP'},body:'private-body-marker'}));
  assert(response.status===403&&response.headers.get('x-original')==='preserved'&&await response.text()==='original denial','response changed');
  const serialized=JSON.stringify(payload);assert(!/private-marker|client-secret-marker|client-private-marker|private-body-marker/.test(serialized),'private request data leaked');
  assert((payload.p_event as Record<string,unknown>).kind==='access_denied','wrong classification');assert(payload.p_source==='edge:private-image','wrong source');
 }finally{globalThis.fetch=oldFetch;for(const[key,value]of Object.entries({SUPABASE_URL:oldBase,SUPABASE_SERVICE_ROLE_KEY:oldKey}))if(value===undefined)Deno.env.delete(key);else Deno.env.set(key,value);}
});
Deno.test('collection failure cannot break original API response or expose exception secrets',async()=>{
 const oldFetch=globalThis.fetch,oldWarn=console.warn;const logs:string[]=[];
 try{console.warn=(value:unknown)=>logs.push(String(value));globalThis.fetch=()=>Promise.reject(Error('private-token-that-must-never-appear'));
 const response=await monitoredHandler('public-video',()=>new Response('not found',{status:404}))(new Request('https://backend-fixture.invalid/functions/v1/public-video'));
 assert(response.status===404&&await response.text()==='not found','response changed on collection failure');assert(logs.every(line=>!line.includes('private-token')),'raw exception leaked');
 }finally{globalThis.fetch=oldFetch;console.warn=oldWarn;}
});
Deno.test('unhandled API error is generic and monitor reports server failure',async()=>{
 const oldFetch=globalThis.fetch,oldWarn=console.warn;
 try{console.warn=()=>{};globalThis.fetch=()=>Promise.resolve(new Response('true'));
 const response=await monitoredHandler('public-image',()=>{throw Error('database-secret-error');})(new Request('https://backend-fixture.invalid/functions/v1/public-image'));
 assert(response.status===503,'missing generic service failure');assert(!String(await response.text()).includes('database-secret'),'exception leaked');
 }finally{globalThis.fetch=oldFetch;console.warn=oldWarn;}
});

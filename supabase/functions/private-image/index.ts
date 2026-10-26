import { serveMonitored } from '../_shared/security_monitor.ts';
/** Authenticated original gateway. NEVER returns a signed/public storage URL.
 * Uses user-scoped RPC before and after the fetch. Admin client only retrieves
 * the exact authorized path. Secrets stay in the Edge environment, never iOS.
 */
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.57.4';
const headers={ 'Cache-Control':'private, no-store, max-age=0', 'Pragma':'no-cache', 'X-Content-Type-Options':'nosniff', 'Referrer-Policy':'no-referrer' };
const fail=(status:number)=>new Response(JSON.stringify({error:status===401?'authentication_required':'not_found'}),{status,headers:{...headers,'Content-Type':'application/json'}});
serveMonitored('private-image', async(req:Request)=>{
 const origin=req.headers.get('Origin');
 // Approved admin browser transport. Authentication and the exact-photo
 // authorization/recheck below still run for every GET, including operators.
 const allowedOrigins=['https://mefrion.vercel.app',...(Deno.env.get('MEFRION_BROWSER_ORIGINS')||'https://mefrion-support.toshiki1108.chatgpt.site,http://127.0.0.1:8781').split(',')].map(v=>v.trim());
 const cors:Record<string,string>=origin&&allowedOrigins.includes(origin)?{'Access-Control-Allow-Origin':origin,'Access-Control-Allow-Methods':'GET, OPTIONS','Access-Control-Allow-Headers':'authorization, apikey','Vary':'Origin'}:{};
 if(req.method==='OPTIONS')return new Response(null,{status:origin&&allowedOrigins.includes(origin)?204:403,headers:{...headers,...cors}});
 const respond=(response:Response)=>{for(const [key,value] of Object.entries(cors))response.headers.set(key,value);return response};

 if(req.method!=='GET')return new Response(null,{status:405,headers});
 const auth=req.headers.get('Authorization');
 if(!auth?.startsWith('Bearer '))return respond(fail(401));
 const photo=new URL(req.url).searchParams.get('photo');
 if(!photo||!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(photo))return respond(fail(404));
 const url=Deno.env.get('SUPABASE_URL')!;
 const user=createClient(url,Deno.env.get('SUPABASE_ANON_KEY')!,{global:{headers:{Authorization:auth}},auth:{persistSession:false,autoRefreshToken:false}});
 const {data:identity,error:authError}=await user.auth.getUser(auth.slice(7));
 if(authError||!identity.user||identity.user.is_anonymous)return respond(fail(401));
 const {data:record,error}=await user.rpc('mefrion_photo',{p_photo:photo});
 if(error||!record?.path)return respond(fail(404));
 const storage=createClient(url,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false,autoRefreshToken:false}});
 const imagePath=record.media_kind==='video'?record.preview_path:record.path;
 if(typeof imagePath!=='string')return respond(fail(404));
 const {data:blob,error:mediaError}=await storage.storage.from('family-originals').download(imagePath);
 if(mediaError||!blob)return respond(fail(404));
 const {data:recheck,error:revoked}=await user.rpc('mefrion_photo',{p_photo:photo});
 if(revoked||recheck?.path!==record.path||recheck?.preview_path!==record.preview_path)return respond(fail(404));
 return respond(new Response(blob,{status:200,headers:{...headers,'Content-Type':'image/jpeg'}}));
});

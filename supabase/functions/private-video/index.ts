import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.4";

const headers={"Cache-Control":"private, no-store, max-age=0","X-Content-Type-Options":"nosniff","Accept-Ranges":"none"};
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
Deno.serve(async(request:Request)=>{
  if(request.method!=="GET")return new Response(null,{status:405,headers});
  const photo=new URL(request.url).searchParams.get("photo");
  const token=request.headers.get("Authorization");
  if(!photo||!uuid.test(photo))return new Response(null,{status:404,headers});
  if(!token?.startsWith("Bearer "))return new Response(null,{status:401,headers});
  const base=Deno.env.get("SUPABASE_URL")!;
  const user=createClient(base,Deno.env.get("SUPABASE_ANON_KEY")!,{global:{headers:{Authorization:token}},auth:{persistSession:false,autoRefreshToken:false}});
  const {data:identity,error:authError}=await user.auth.getUser(token.slice(7));
  if(authError||!identity.user||identity.user.is_anonymous)return new Response(null,{status:401,headers});
  const {data:before,error}=await user.rpc("mefrion_photo",{p_photo:photo});
  if(error||before?.media_kind!=="video"||typeof before.path!=="string")return new Response(null,{status:404,headers});
  const server=createClient(base,Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,{auth:{persistSession:false}});
  const file=await server.storage.from("family-originals").download(before.path);
  if(file.error||!file.data||file.data.size>52428800)return new Response(null,{status:404,headers});
  if(new TextDecoder().decode(await file.data.slice(4,8).arrayBuffer())!=="ftyp")return new Response(null,{status:404,headers});
  const {data:after,error:revoked}=await user.rpc("mefrion_photo",{p_photo:photo});
  if(revoked||after?.path!==before.path)return new Response(null,{status:404,headers});
  return new Response(file.data,{headers:{...headers,"Content-Type":"video/mp4"}});
});

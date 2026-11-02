import { serveMonitored } from '../_shared/security_monitor.ts';
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.4";
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const escape=(value:unknown)=>String(value??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]!));
serveMonitored('shared-page', async(request:Request)=>{
 const base=Deno.env.get("SUPABASE_URL")!;
 const headers={"Content-Type":"text/html; charset=utf-8","Cache-Control":"private, no-store, max-age=0","X-Content-Type-Options":"nosniff","Referrer-Policy":"no-referrer","Content-Security-Policy":`default-src 'none'; style-src 'unsafe-inline'; img-src ${base}; frame-ancestors 'none'; base-uri 'none'; form-action 'none'`};
 if(request.method!=="GET")return new Response(null,{status:405,headers});
 const post=new URL(request.url).searchParams.get("post");
 const ended=()=>new Response('<!doctype html><html lang="ja"><meta charset="utf-8"><title>MEFRION</title><main><h1>この共有は終了しました</h1><p>掲載が取り消されたか、公開設定が変更されています。</p><strong>MEFRION</strong></main></html>',{status:404,headers});
 if(!post || !uuid.test(post))return ended();
 const viewer=createClient(base,Deno.env.get("SUPABASE_ANON_KEY")!,{auth:{persistSession:false}});
 const result=await viewer.rpc("mefrion_shared_projection",{p_post:post});
 if(result.error)return new Response('共有を読み込めません。時間をおいて再試行してください。',{status:503,headers});
 const value=result.data;if(!value || !Array.isArray(value.media) || !value.media.length)return ended();
 const url=(id:string)=>base+"/functions/v1/public-image?media="+encodeURIComponent(id);
 const pictures=value.media.map((m:{id:string;captured:string|null},i:number)=>{
  if(!uuid.test(m.id))throw Error("projection_invalid");
  const prefix=i===0?"first":"second",layout=value.layout??{};
  const zoom=Math.max(1,Math.min(4,Number(layout[prefix+"_zoom"]??1))),x=Math.max(0,Math.min(1,Number(layout[prefix+"_x"]??0.5))),y=Math.max(0,Math.min(1,Number(layout[prefix+"_y"]??0.5)));
  return `<figure><div class="photo"><img alt="公開を許可した写真" src="${escape(url(m.id))}" style="object-position:${x*100}% ${y*100}%;transform:scale(${zoom});transform-origin:${x*100}% ${y*100}%"></div><figcaption>${escape(m.captured??"日付不明")}</figcaption></figure>`;
 }).join("");
 const title=value.kind==="twins"?"そっくりな子との出会い":"思い出カード";
 const og=`<meta property="og:title" content="MEFRION · ${escape(title)}"><meta property="og:description" content="${escape(value.text??"")}"><meta property="og:image" content="${escape(url(value.media[0].id))}">`;
 const style='body{margin:0;background:#fffaf5;color:#29221f;font-family:system-ui}main{max-width:440px;margin:auto;padding:24px}article{min-height:620px;background:#fff4ed;border-radius:24px;padding:24px;box-sizing:border-box;text-align:center}h1{color:#fa6264}section{display:flex;gap:14px;margin:40px 0}figure{background:white;padding:8px;margin:0;flex:1;min-width:0;transform:rotate(-3deg)}figure+figure{transform:rotate(3deg)}.photo{overflow:hidden;aspect-ratio:2/3}img{width:100%;height:100%;object-fit:cover}figcaption{padding:10px 0;font-size:13px}.notice,footer{font-size:12px;color:#766c66}strong{display:block;color:#fa6264;margin:36px}';
 return new Response(`<!doctype html><html lang="ja"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>MEFRION · ${escape(title)}</title>${og}<style>${style}</style><main><article><h1>${escape(title)}</h1><p>${escape(value.name)}${value.candidate_name ? " · "+escape(value.candidate_name) : ""}</p><section>${pictures}</section><p>${escape(value.text)}</p><strong>MEFRION</strong></article><footer>MEFRION管理下の公開は取り消せます。共有先に保存されたコピーは連動しません。</footer></main></html>`,{headers});
});

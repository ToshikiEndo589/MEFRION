// Server-only encrypted object store. The decryption key is never installed here.
const backupHeaders={'Cache-Control':'no-store','X-Content-Type-Options':'nosniff','X-Robots-Tag':'noindex, nofollow'};
const backupReply=(status,value)=>new Response(JSON.stringify(value),{status,headers:{...backupHeaders,'Content-Type':'application/json'}});
const backupKey=/^production\/(objects\/[0-9a-f]{64}|snapshots\/[0-9a-f-]{36}|manifests\/[0-9a-f-]{36})\.bin$/;
async function backupHash(bytes){return [...new Uint8Array(await crypto.subtle.digest('SHA-256',bytes))].map(x=>x.toString(16).padStart(2,'0')).join('');}
async function backupHandler(request,env){
 const supplied=request.headers.get('x-mefrion-backup')||'',expected=env.MEFRION_BACKUP_TOKEN||'';
 if(expected.length<32||supplied.length<32)return backupReply(401,{error:'authentication_required'});
 const a=await backupHash(new TextEncoder().encode(supplied)),b=await backupHash(new TextEncoder().encode(expected));
 let diff=0;for(let i=0;i<a.length;i++)diff|=a.charCodeAt(i)^b.charCodeAt(i);
 if(diff)return backupReply(401,{error:'authentication_required'});
 if(!env.BUCKET)return backupReply(503,{error:'storage_not_configured'});
 const path=new URL(request.url).pathname;
 if(path==='/internal-backup/health'&&request.method==='GET')return backupReply(200,{ready:true,encrypted_only:true});
 if(path==='/internal-backup/check'&&request.method==='POST'){
  if(Number(request.headers.get('content-length'))>50000)return backupReply(413,{error:'size_limit'});
  let items;try{const text=await request.text();if(text.length>50000)throw Error();items=JSON.parse(text);}catch{return backupReply(400,{error:'invalid_inventory'});}
  if(!Array.isArray(items)||items.length>200||items.some(x=>!backupKey.test(x.key)||!/^[0-9a-f]{64}$/.test(x.sha)))return backupReply(400,{error:'invalid_inventory'});
  let valid=true;
  for(let i=0;i<items.length;i+=16)await Promise.all(items.slice(i,i+16).map(async x=>{const obj=await env.BUCKET.head(x.key);if(!obj||obj.customMetadata?.sha256!==x.sha)valid=false;}));
  return backupReply(valid?200:409,{verified:valid,count:items.length});
 }
 if(path==='/internal-backup/catalog'&&request.method==='GET'){
  const cursor=new URL(request.url).searchParams.get('cursor');
  if(cursor&&cursor.length>2000)return backupReply(400,{error:'invalid_cursor'});
  const result=await env.BUCKET.list({prefix:'production/manifests/',limit:1000,...(cursor?{cursor}:{})});
  return backupReply(200,{items:result.objects.filter(x=>backupKey.test(x.key)).map(x=>({key:x.key,uploaded:x.uploaded,size:x.size})),cursor:result.truncated?result.cursor:null});
 }
 const key=path.slice('/internal-backup/'.length);
 if(!backupKey.test(key))return backupReply(400,{error:'key_invalid'});
 if(request.method==='PUT'){
  if(Number(request.headers.get('content-length'))>53*1024*1024)return backupReply(413,{error:'size_limit'});
  const data=new Uint8Array(await request.arrayBuffer());
  if(data.length>53*1024*1024||data.length<36||new TextDecoder().decode(data.slice(0,8))!=='MFRBKP01')return backupReply(400,{error:'encrypted_envelope_required'});
  const sha=await backupHash(data);if(sha!==request.headers.get('x-content-sha256'))return backupReply(400,{error:'digest_mismatch'});
  const existing=await env.BUCKET.head(key);
  if(existing&&existing.customMetadata?.sha256!==sha)return backupReply(409,{error:'immutable_object'});
  if(!existing)await env.BUCKET.put(key,data,{httpMetadata:{contentType:'application/octet-stream'},customMetadata:{sha256:sha}});
  const verified=await env.BUCKET.head(key);
  if(!verified||verified.size!==data.length||verified.customMetadata?.sha256!==sha)return backupReply(503,{error:'verification_failed'});
  return backupReply(200,{stored:true,bytes:verified.size,sha256:sha});
 }
 if(request.method==='GET'||request.method==='HEAD'){
  const obj=request.method==='HEAD'?await env.BUCKET.head(key):await env.BUCKET.get(key);
  if(!obj)return backupReply(404,{error:'not_found'});
  return new Response(request.method==='HEAD'?null:obj.body,{headers:{...backupHeaders,'Content-Type':'application/octet-stream','Content-Length':String(obj.size),'x-content-sha256':obj.customMetadata?.sha256||''}});
 }
 if(request.method==='DELETE'){await env.BUCKET.delete(key);return backupReply(200,{deleted:!(await env.BUCKET.head(key))});}
 return backupReply(405,{error:'method_not_allowed'});
}

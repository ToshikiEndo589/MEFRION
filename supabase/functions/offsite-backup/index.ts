import { serveMonitored } from '../_shared/security_monitor.ts';
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.4";
const json=(status:number,value:unknown)=>new Response(JSON.stringify(value),{status,headers:{'Content-Type':'application/json','Cache-Control':'no-store'}});
const sha=async(bytes:Uint8Array)=>[...new Uint8Array(await crypto.subtle.digest('SHA-256',new Uint8Array(bytes).buffer))].map(x=>x.toString(16).padStart(2,'0')).join('');
export async function seal(bytes:Uint8Array,key:CryptoKey):Promise<Uint8Array<ArrayBuffer>>{
 const iv=crypto.getRandomValues(new Uint8Array(12));const prefix=new TextEncoder().encode('MFRBKP01');
 const cipher=new Uint8Array(await crypto.subtle.encrypt({name:'AES-GCM',iv,additionalData:prefix},key,new Uint8Array(bytes).buffer));
 const result=new Uint8Array(20+cipher.length);result.set(prefix);result.set(iv,8);result.set(cipher,20);return result;
}
serveMonitored('offsite-backup', async request=>{
 if(request.method!=='POST')return json(405,{error:'method_not_allowed'});
 const token=request.headers.get('x-mefrion-worker');if(!token||token.length<32)return json(401,{error:'authentication_required'});
 const client=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false}});
 const auth=await client.rpc('mefrion_cloud_worker_authorize',{p_token:token});if(auth.error||auth.data!==true)return json(401,{error:'authentication_required'});
 const rpc=async(name:string,params:object={})=>{const r=await client.rpc(name,params);if(r.error)throw Error('database_failed');return r.data;};
 let count=0;
 try{
  const config=await rpc('mefrion_offsite_configuration');
  if(config?.mefrion_offsite_url!=='https://mefrion-support.toshiki1108.chatgpt.site/internal-backup/'||!/^[0-9a-f]{64}$/.test(config?.mefrion_offsite_aes_key)||config?.mefrion_offsite_token?.length<32)throw Error('configuration_missing');
  const key=await crypto.subtle.importKey('raw',Uint8Array.from(config.mefrion_offsite_aes_key.match(/../g),x=>parseInt(x as string,16)),'AES-GCM',false,['encrypt']);
  const remote=async(path:string,init:RequestInit={})=>fetch(config.mefrion_offsite_url+path,{...init,headers:{'x-mefrion-backup':config.mefrion_offsite_token,...init.headers},signal:AbortSignal.timeout(45000)});
  for(let n=0;n<4;n++){
   const work=await rpc('mefrion_offsite_next');if(!work)break;
   try{
    if(work.kind==='prune_run'||work.kind==='prune_object'){
     for(const path of work.keys){const r=await remote(path,{method:'DELETE'});if(!r.ok||!(await r.json()).deleted)throw Error('retention_failed');}
     if(!await rpc('mefrion_offsite_complete',{p_kind:work.kind,p_id:work.id,p_lease:work.lease,p_success:true}))throw Error('completion_failed');count++;continue;
    }
    let bytes:Uint8Array;
    if(work.kind==='snapshot')bytes=Uint8Array.from(atob(work.snapshot.replace(/\s/g,'')),c=>c.charCodeAt(0));
    else if(work.kind==='manifest'){
     // Verify all referenced files are still available before sealing a manifest.
     const inventory=[{key:work.manifest.snapshot_key,cipher_sha:work.manifest.snapshot_sha},...work.manifest.objects];
     for(let i=0;i<inventory.length;i+=200){
      const r=await remote('check',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(inventory.slice(i,i+200).map(item=>({key:item.key,sha:item.cipher_sha})))});
      if(!r.ok||!(await r.json()).verified)throw Error('inventory_incomplete');
     }
     bytes=new TextEncoder().encode(JSON.stringify(work.manifest));
    }else{
     if(!['family-originals','public-derived'].includes(work.bucket)||work.bytes>50*1024*1024)throw Error('source_invalid');
     const r=await client.storage.from(work.bucket).download(work.path);if(r.error||!r.data||r.data.size!==work.bytes)throw Error('source_changed');bytes=new Uint8Array(await r.data.arrayBuffer());
    }
    const plainSHA=await sha(bytes);let sealed=await seal(bytes,key);let digest=await sha(sealed);
    // A retry keeps immutable data, rather than encrypting a second version.
    const exists=await remote(work.key,{method:'HEAD'});
    if(exists.ok){
     const old=await remote(work.key);if(!old.ok)throw Error('readback_failed');sealed=new Uint8Array(await old.arrayBuffer());digest=await sha(sealed);
     // Authenticate old ciphertext and its contents before reusing it.
     const decryptKey=await crypto.subtle.importKey('raw',Uint8Array.from(config.mefrion_offsite_aes_key.match(/../g),x=>parseInt(x as string,16)),'AES-GCM',false,['decrypt']);
     const plaintext=new Uint8Array(await crypto.subtle.decrypt({name:'AES-GCM',iv:sealed.slice(8,20),additionalData:sealed.slice(0,8)},decryptKey,sealed.slice(20)));
     if(await sha(plaintext)!==plainSHA)throw Error('immutable_conflict');
    }else{
     if(exists.status!==404)throw Error('destination_failed');
     const stored=await remote(work.key,{method:'PUT',body:sealed,headers:{'Content-Type':'application/octet-stream','x-content-sha256':digest}});if(!stored.ok)throw Error('upload_failed');
     const readback=await remote(work.key);if(!readback.ok||await sha(new Uint8Array(await readback.arrayBuffer()))!==digest)throw Error('readback_failed');
    }
    if(!await rpc('mefrion_offsite_complete',{p_kind:work.kind,p_id:work.id,p_lease:work.lease,p_success:true,p_plain_sha:plainSHA,p_cipher_sha:digest}))throw Error('completion_failed');count++;
   }catch{
    await rpc('mefrion_offsite_complete',{p_kind:work.kind,p_id:work.id,p_lease:work.lease,p_success:false});return json(503,{error:'offsite_transfer_failed',processed:count});
   }
  }
  return json(200,{processed:count,independent_destination:true});
 }catch{await client.rpc('mefrion_offsite_failure');return json(503,{error:'offsite_unavailable',processed:count});}
});

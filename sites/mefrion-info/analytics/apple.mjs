import {createPrivateKey,sign,createHash,timingSafeEqual} from 'node:crypto';
import {gunzipSync} from 'node:zlib';
const API='https://api.appstoreconnect.apple.com';
export const APP_ID='6825337314';
export function allowedDownload(value){try{const u=new URL(value);return u.protocol==='https:'&&!u.username&&!u.password&&!u.port&&(u.hostname.endsWith('.apple.com')||/^asp-[a-z0-9-]+\.s3\.[a-z0-9-]+\.amazonaws\.com$/.test(u.hostname))}catch{return false}}
export function authorized(header,secret){if(!secret||secret.length<32||typeof header!=='string')return false;const a=Buffer.from(header),b=Buffer.from('Bearer '+secret);return a.length===b.length&&timingSafeEqual(a,b)}
export function appleJWT(env,now=Date.now()){
 const head=Buffer.from(JSON.stringify({alg:'ES256',kid:env.ASC_KEY_ID,typ:'JWT'})).toString('base64url');
 const iat=Math.floor(now/1000);const body=Buffer.from(JSON.stringify({iss:env.ASC_ISSUER_ID,iat,exp:iat+300,aud:'appstoreconnect-v1'})).toString('base64url');
 const key=createPrivateKey(env.ASC_PRIVATE_KEY.replaceAll('\\n','\n'));return head+'.'+body+'.'+sign('sha256',Buffer.from(head+'.'+body),{key,dsaEncoding:'ieee-p1363'}).toString('base64url');
}
export function parseTSV(text){
 // Apple reports are tab separated; quoted tabs/newlines and doubled quotes are preserved.
 const rows=[];let row=[],cell='',quoted=false;for(let i=0;i<text.length;i++){const c=text[i];if(c==='"'){if(quoted&&text[i+1]==='"'){cell+='"';i++}else quoted=!quoted}else if(!quoted&&(c==='\t'||c==='\n')){row.push(cell.replace(/\r$/,''));cell='';if(c==='\n'){if(row.some(Boolean))rows.push(row);row=[]}}else cell+=c;}if(quoted)throw Error('schema');if(cell||row.length){row.push(cell.replace(/\r$/,''));rows.push(row)}return rows;
}
export function reportDays(text,kind,processingDate){
 const rows=parseTSV(text.replace(/^\uFEFF/,''));if(!rows.length)return [];const head=rows.shift();const idx=n=>head.indexOf(n);for(const n of ['Date','App Apple Identifier','Counts',kind==='downloads'?'Download Type':'Event'])if(idx(n)<0)throw Error('schema');
 const days=new Map();for(const row of rows){if(row[idx('App Apple Identifier')]!==APP_ID)continue;const day=row[idx('Date')],n=Number(row[idx('Counts')]);if(!/^\d{4}-\d{2}-\d{2}$/.test(day)||!Number.isSafeInteger(n)||n<0)throw Error('schema');
 let value=days.get(day);if(!value){value={day,kind,processed:processingDate,first:0,again:0,installs:0};days.set(day,value)}
 if(kind==='downloads'){const type=row[idx('Download Type')].toLowerCase();if(type==='first-time download')value.first+=n;else if(type==='redownload')value.again+=n;}
 else if(row[idx('Event')]==='Install')value.installs+=n;
 }return [...days.values()];
}
export function newestDays(batches){const chosen=new Map();for(const row of batches.flat()){const key=row.day+':'+row.kind,old=chosen.get(key);if(!old||row.processed>old.processed)chosen.set(key,{...row});else if(row.processed===old.processed){old.first+=row.first;old.again+=row.again;old.installs+=row.installs}}return [...chosen.values()];}
async function boundedBytes(response,max){if(!response.ok)throw Error('download');if(Number(response.headers.get('content-length'))>max)throw Error('size');let bytes=0;const chunks=[];for await(const part of response.body){bytes+=part.length;if(bytes>max)throw Error('size');chunks.push(part)}return Buffer.concat(chunks)}
export async function collectApple(env,fetcher=fetch){
 if(!env.ASC_KEY_ID||!env.ASC_ISSUER_ID||!env.ASC_PRIVATE_KEY)return {status:'not_configured',rows:[]};
 const jwt=appleJWT(env);let requests=0;const json=async path=>{if(++requests>160)throw Error('budget');const u=new URL(path,API);if(u.origin!==API)throw Error('origin');const r=await fetcher(u,{headers:{Authorization:'Bearer '+jwt},redirect:'error',signal:AbortSignal.timeout(8000)});if(r.status===401||r.status===403)throw Error('apple_auth');if(!r.ok)throw Error('apple_api');return JSON.parse((await boundedBytes(r,2_000_000)).toString())};
 const list=async path=>{let all=[],next=path;for(let page=0;next&&page<20;page++){const result=await json(next);all.push(...result.data||[]);next=result.links?.next;if(page===19&&next)throw Error('pagination')}return [...new Map(all.map(item=>[item.id,item])).values()]};
 const pending=await list('/v1/apps/'+APP_ID+'/analyticsReportRequests?limit=200');const ongoing=pending.filter(r=>r.attributes?.accessType==='ONGOING'&&!r.attributes?.stoppedDueToInactivity);if(!ongoing.length)return {status:'request_required',rows:[]};
 // Use one current request: old/snapshot requests would otherwise duplicate data.
 const request=ongoing[0];const reports=await list('/v1/analyticsReportRequests/'+encodeURIComponent(request.id)+'/reports?limit=200');const selected=[];
 for(const [kind,name] of [['downloads','App Store Downloads'],['installs','App Store Installations and Deletions']]){const standard=reports.find(r=>r.attributes?.name===name||r.attributes?.name===name+' Standard');if(standard)selected.push([kind,standard]);}
 if(!selected.length)return {status:'awaiting_reports',rows:[]};const batches=[];let segments=0;
 for(const [kind,report] of selected){const instances=(await list('/v1/analyticsReports/'+encodeURIComponent(report.id)+'/instances?filter%5Bgranularity%5D=DAILY&limit=200')).filter(i=>/^\d{4}-\d{2}-\d{2}$/.test(i.attributes?.processingDate||'')).sort((a,b)=>b.attributes.processingDate.localeCompare(a.attributes.processingDate)).slice(0,10);
 for(const instance of instances){const parts=await list('/v1/analyticsReportInstances/'+encodeURIComponent(instance.id)+'/segments?limit=200');if(!parts.length)continue;const instanceRows=[];
 for(const part of parts){if(++segments>50)throw Error('budget');const a=part.attributes;if(!allowedDownload(a?.url))throw Error('origin');const bytes=await boundedBytes(await fetcher(a.url,{redirect:'error',signal:AbortSignal.timeout(8000)}),2_000_000);if(a.sizeInBytes!=null&&bytes.length!==a.sizeInBytes)throw Error('integrity');if(!/^[a-f0-9]{32}([a-f0-9]{32})?$/i.test(a.checksum||''))throw Error('integrity');if(createHash(a.checksum.length===32?'md5':'sha256').update(bytes).digest('hex')!==a.checksum.toLowerCase())throw Error('integrity');const data=bytes[0]===31&&bytes[1]===139?gunzipSync(bytes,{maxOutputLength:10_000_000}):bytes;instanceRows.push(reportDays(data.toString('utf8'),kind,instance.attributes.processingDate));
 }batches.push(newestDays(instanceRows));
 }}const rows=newestDays(batches);return {status:rows.length?'ok':'awaiting_reports',rows};
}

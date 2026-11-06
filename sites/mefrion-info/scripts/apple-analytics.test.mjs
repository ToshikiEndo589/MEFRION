import test from 'node:test';
import assert from 'node:assert/strict';
import {generateKeyPairSync,createHash} from 'node:crypto';
import {gzipSync} from 'node:zlib';
import {APP_ID,allowedDownload,authorized,appleJWT,parseTSV,reportDays,newestDays,collectApple} from '../analytics/apple.mjs';
import handler from '../api/apple-sync.mjs';
const {privateKey}=generateKeyPairSync('ec',{namedCurve:'prime256v1'});
const env={ASC_KEY_ID:'TESTKEY',ASC_ISSUER_ID:'fixture',ASC_PRIVATE_KEY:privateKey.export({type:'pkcs8',format:'pem'}).toString()};
const text=(type,count=2)=>'Date\tApp Apple Identifier\tDownload Type\tCounts\n2026-11-04\t'+APP_ID+'\t'+type+'\t'+count+'\n';
test('Apple token is short-lived ES256 and scheduler denies missing or incorrect secrets',()=>{
 const t=appleJWT(env,1000000).split('.');assert.equal(Buffer.from(t[2],'base64url').length,64);const claims=JSON.parse(Buffer.from(t[1],'base64url'));assert.equal(claims.exp-claims.iat,300);assert.equal(claims.aud,'appstoreconnect-v1');
 assert.equal(authorized('Bearer '+'a'.repeat(64),'a'.repeat(64)),true);assert.equal(authorized('Bearer x','a'.repeat(64)),false);assert.equal(authorized(undefined,undefined),false);
});
test('tab parsing preserves quoted values and metric parsing rejects invalid schema',()=>{
 assert.deepEqual(parseTSV('a\tb\n"c\td"\t"e""f"\n'),[['a','b'],['c\td','e"f']]);
 const days=reportDays(text('First-time Download'),'downloads','2026-11-06');assert.equal(days[0].first,2);assert.equal(days[0].again,0);
 assert.equal(reportDays(text('Manual update'),'downloads','2026-11-06')[0].first,0);
 assert.throws(()=>reportDays('Date\tCounts\nx\t2','downloads','2026-11-06'),/schema/);
 assert.throws(()=>reportDays(text('Redownload',-1),'downloads','2026-11-06'),/schema/);
 assert.equal(reportDays(text('First-time Download').replace(APP_ID,'999'),'downloads','2026-11-06').length,0);
});
test('newer processing dates replace previous days rather than double-counting',()=>{
 const a=reportDays(text('First-time Download',3),'downloads','2026-11-05');const b=reportDays(text('First-time Download',5),'downloads','2026-11-06');
 assert.equal(newestDays([a,b])[0].first,5);assert.equal(newestDays([b,a])[0].first,5);assert.equal(newestDays([b,b])[0].first,10); // same-instance separate segments are additive.
});
test('Apple signed downloads are restricted to known TLS hosts',()=>{
 for(const u of ['http://127.0.0.1/a','https://evil.invalid/a','https://x.apple.com.evil.invalid','https://user:secret@x.apple.com','https://x.apple.com:8443/a'])assert.equal(allowedDownload(u),false,u);
 assert.equal(allowedDownload('https://asp-us-west-2.s3.us-west-2.amazonaws.com/report.gz'),true);
});
test('collector waits for reports and does not create admin requests',async()=>{
 const calls=[];const r=await collectApple(env,async(u,options)=>{calls.push([String(u),options]);return Response.json({data:[]})});assert.equal(r.status,'request_required');assert.equal(calls.length,1);assert.equal(calls[0][1].method,undefined);
 assert.equal((await collectApple({})).status,'not_configured');
});
test('collector verifies segments and never sends Apple bearer to storage hosts',async()=>{
 const bytes=gzipSync(text('First-time Download',4));let downloadAuth;
 const fetcher=async(u,o)=>{u=String(u);if(u.startsWith('https://asp-')){downloadAuth=o.headers;return new Response(bytes)}
 if(u.includes('/apps/'))return Response.json({data:[{id:'req',attributes:{accessType:'ONGOING'}}]});
 if(u.includes('/reports?'))return Response.json({data:[{id:'report',attributes:{name:'App Store Downloads Standard'}}]});
 if(u.includes('/instances?'))return Response.json({data:[{id:'instance',attributes:{processingDate:'2026-11-06'}}]});
 return Response.json({data:[{attributes:{url:'https://asp-us-west-2.s3.us-west-2.amazonaws.com/r.gz',sizeInBytes:bytes.length,checksum:createHash('md5').update(bytes).digest('hex')}}]});};
 const result=await collectApple(env,fetcher);assert.equal(result.status,'ok');assert.equal(result.rows[0].first,4);assert.equal(downloadAuth,undefined);
});
test('public cron URL cannot invoke Apple without production credentials',async()=>{
 const old=process.env.VERCEL_ENV;delete process.env.VERCEL_ENV;
 try{const res={setHeader(){},end(){}};await handler({method:'GET',headers:{}},res);assert.equal(res.statusCode,401)}finally{if(old!==undefined)process.env.VERCEL_ENV=old;}
});

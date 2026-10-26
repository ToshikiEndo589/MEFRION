import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import vm from 'node:vm';
import {classify,canonicalTarget} from '../security/classifier.mjs';
import {route} from '../api/site.mjs';
test('classifies suspicious probes without persisting sensitive inputs',()=>{
 for(const [path,query,kind]of [['/.env','token=secret@example.invalid','secret_probe'],['/%252e%252e%252fetc/passwd','','path_traversal'],['/','q=%3Cscript%3Esecret%3C/script%3E','injection_probe'],['/','q=UNION%20SELECT%20password','injection_probe']]){
  const result=classify({path,query,status:404});assert.equal(result.kind,kind);assert.match(result.target,/^\/\[/);assert.doesNotMatch(JSON.stringify(result),/secret@example|password|token=|script/);
 }
});
test('denials, limits, missing pages and errors remain distinct from attack suspicion',()=>{
 for(const [status,kind]of [[401,'auth_denied'],[403,'access_denied'],[429,'rate_limited'],[404,'not_found'],[405,'method_denied'],[503,'server_error']])assert.equal(classify({path:'/arbitrary-personal-path',status}).kind,kind);
 assert.equal(classify({path:'/privacy',status:200}),null);assert.equal(classify({path:'/not-secret',status:204}),null);
 assert.equal(canonicalTarget('/cloud-shared/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),'/cloud-shared/:id');
 assert.equal(canonicalTarget('/customer/email@example.invalid'),'/[unknown]');
 assert.equal(classify({path:'/',status:403,edge:'private-image'}).target,'/functions/private-image');
});
test('server classifier stays identical on Vercel and Supabase',async()=>{
 assert.equal(await readFile(new URL('../security/classifier.mjs',import.meta.url),'utf8'),await readFile(new URL('../../../supabase/functions/_shared/security_classifier.mjs',import.meta.url),'utf8'));
});
test('security assets and deep link have restrictive CSP and no indexing',async()=>{
 for(const path of ['/console/security','/console/security.js','/console/security.css']){
  const r=await route(new Request('https://mefrion.vercel.app'+path));assert.equal(r.status,200);assert.equal(r.headers.get('x-robots-tag'),'noindex, nofollow');assert.match(r.headers.get('content-security-policy'),/script-src 'self';/);
 }
 const html=await(await route(new Request('https://mefrion.vercel.app/console/security'))).text();assert.match(html,/data-console-panel="security"/);assert.match(html,/id="security-section" hidden/);assert.doesNotMatch(html,/service_role|eyJ[a-zA-Z0-9_-]{20}/);
});
test('CSV resists spreadsheet formula injection, quotes and newlines',async()=>{
 const source=await readFile(new URL('../console/security.js',import.meta.url),'utf8');
 const context=vm.createContext({document:{getElementById:()=>null},Number,Intl});vm.runInContext(source,context);
 const csv=vm.runInContext("securityCSV([{id:'=HYPERLINK(\"evil\")',target:'@SUM(A1)',country:'\"JP\\nline'}])",context);
 assert.match(csv,/"'=HYPERLINK\(""evil""\)"/);assert.match(csv,/"'@SUM\(A1\)"/);assert.match(csv,/""JP\nline/);assert.ok(csv.startsWith('\uFEFF'));
});
test('console avoids HTML injection and persistent bearer token storage',async()=>{
 const source=await readFile(new URL('../console/security.js',import.meta.url),'utf8');assert.doesNotMatch(source,/innerHTML|insertAdjacentHTML|localStorage|sessionStorage/);
});
test('asset build is reproducible and preserves auth gate',async()=>{
 const source=await readFile(new URL('../worker/index.js',import.meta.url),'utf8');const pages=JSON.parse(source.split('\n')[0].slice('const PAGES='.length,-1));
 assert.match(pages['/console/cloud.js'].body,/panel==='security'/);assert.match(pages['/console/cloud.js'].body,/clearSecurity/);assert.equal((pages['/console/'].body.match(/id="security-section"/g)||[]).length,1);
});

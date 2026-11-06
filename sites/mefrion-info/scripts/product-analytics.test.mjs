import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import vm from 'node:vm';
import test from 'node:test';
import {sharedArrival} from '../analytics/landing.mjs';

function fixture(){
 const nodes=new Map();
 function node(tag='div'){return {tag,children:[],handlers:{},textContent:'',value:'30',style:{},append(...v){this.children.push(...v)},replaceChildren(...v){this.children=v},addEventListener(k,v){this.handlers[k]=v},setAttribute(){},click(){this.handlers.click?.()}};}
 const document={getElementById(id){if(!nodes.has(id))nodes.set(id,node());return nodes.get(id)},createElement:node,createTextNode:text=>({textContent:text})};
 let csv;
 const context=vm.createContext({document,Intl,Date,Number,Math,Map,Blob,URL:{createObjectURL(blob){csv=blob;return 'blob:test'},revokeObjectURL(){}},setTimeout(){},generation:1,panel:'overview',perform:async f=>f()});
 return {nodes,document,context,csv:()=>csv};
}
const source=await readFile(new URL('../console/overview.js',import.meta.url),'utf8');
function allText(n){return [n.textContent,...n.children?.map(allText)||[]].join(' ')}
test('analytics rendering keeps untrusted versions inert and exports safe CSV',async()=>{
 const f=fixture();vm.runInContext(source,f.context);
 vm.runInContext(`productTable('table',['version'],[['<img src=x onerror=alert(1)>'],['  =1+1']]);`,f.context);
 const root=f.nodes.get('table');assert.match(allText(root),/<img src=x onerror=alert\(1\)>/);
 assert.equal(root.children[1].children[0].children[1].children[0].children[0].tag,'td');
 root.children[0].click();const csv=await f.csv().text();assert.match(csv,/"'  =1\+1"/);
 assert.match(csv,/<img src=x/); // text in a quoted cell, never executed as markup.
});
test('dashboard renders no-data states, null store values, quota warning and hourly zeros',async()=>{
 const f=fixture();const result={started_at:null,collection:{events_today:20000,daily_limit:20000,stored_events:25,storage_limit:300000},devices:{dau:0,wau:0,mau:0},registered:{total:0,dau:0,wau:0,mau:0},daily:[],hourly:[],events:[],retention:[],funnel:{first_open:0,registered_after_open:0,posted_after_registration:0},album:{devices:0,returning:0},content:{user_posts:0,user_posters:0,managed_posts:0},versions:[],store:[{day:'2026-11-06',first_downloads:null,redownloads:0,installations:null}]};
 f.context.rpc=async()=>result;vm.runInContext(source,f.context);await vm.runInContext('refreshProductAnalytics()',f.context);
 assert.match(allText(f.nodes.get('product-status')),/一部データが欠ける/);
 assert.equal(f.nodes.get('product-hourly').children.length,48);
 assert.match(allText(f.nodes.get('product-store')),/未取得/);
 assert.match(allText(f.nodes.get('product-daily')),/まだ計測データがありません/);
});
test('failed analytics request is visible without breaking the operator dashboard',async()=>{
 const f=fixture();f.context.rpc=async()=>{throw new Error('private error payload')};vm.runInContext(source,f.context);await vm.runInContext('refreshProductAnalytics()',f.context);
 assert.match(f.nodes.get('product-status').textContent,/取得できません/);assert.doesNotMatch(f.nodes.get('product-status').textContent,/private error/);
});
test('share arrivals use fixed Store URL, safe cookie, and never ingest bots or HEAD',async()=>{
 const original=globalThis.fetch;let calls=0;globalThis.fetch=async()=>{calls++;throw Error('unexpected')};
 try{for(const method of ['GET','HEAD','POST']){
 const res={headers:{},setHeader(k,v){this.headers[k]=v},end(){}};
 assert.equal(await sharedArrival({method,headers:{cookie:'mefrion_visit=../../secret','user-agent':'TestBot'}},res,new URL('https://site.invalid/open/x?redirect=https://evil.invalid')),true);
 assert.equal(res.statusCode,method==='POST'?405:302);
 if(method!=='POST'){assert.equal(res.headers.Location,'https://apps.apple.com/jp/app/id6825337314');assert.match(res.headers['Set-Cookie'],/HttpOnly; Secure; SameSite=Lax/);assert.doesNotMatch(res.headers['Set-Cookie'],/secret/);}
 }assert.equal(calls,0);
 assert.equal(await sharedArrival({}, {}, new URL('https://site.invalid/open/evil')),false);
 }finally{globalThis.fetch=original}
});

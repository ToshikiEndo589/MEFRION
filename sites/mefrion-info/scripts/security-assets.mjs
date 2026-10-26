import {readFile,writeFile} from 'node:fs/promises';
const root=new URL('../',import.meta.url),path=new URL('worker/index.js',root);
const source=await readFile(path,'utf8'),at=source.indexOf('\n');
const pages=JSON.parse(source.slice('const PAGES='.length,at).trim().replace(/;$/,''));
for(const name of ['security.js','security.css'])pages['/console/'+name]={type:name.endsWith('.js')?'application/javascript; charset=utf-8':'text/css; charset=utf-8',body:await readFile(new URL('console/'+name,root),'utf8')};
const fragment=await readFile(new URL('console/security-panel.html',root),'utf8');
let html=pages['/console/'].body;
if(!html.includes('src="/console/security.js"'))html=html.replace('<body>','<link rel="stylesheet" href="/console/security.css"><script src="/console/security.js" defer></script><body>');
if(!html.includes('id="security-nav"'))html=html.replace('<div id="session" hidden>','<div id="session" hidden><button id="security-nav" type="button">セキュリティ</button><button id="reports-nav" type="button">通報</button>');
const start=html.indexOf('<section id="security-section"');
if(start>=0){const end=html.indexOf('<!-- security-panel-end -->',start);if(end<0)throw Error('Missing security end marker');html=html.slice(0,start)+fragment+'<!-- security-panel-end -->'+html.slice(end+'<!-- security-panel-end -->'.length);}
else html=html.replace('<section id="confirmation"',fragment+'<!-- security-panel-end --><section id="confirmation"');
pages['/console/'].body=html;
pages['/console/security']={...pages['/console/'],body:html.replace('<body>','<body data-console-panel="security">').replace('<title>MEFRION クラウド運営管理</title>','<title>セキュリティ監視｜MEFRION</title>')};
await writeFile(path,'const PAGES='+JSON.stringify(pages)+';'+source.slice(at));

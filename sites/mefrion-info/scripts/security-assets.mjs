import {mkdir,readFile,writeFile} from 'node:fs/promises';
const root=new URL('../',import.meta.url),path=new URL('worker/index.js',root);
const source=await readFile(path,'utf8'),at=source.indexOf('\n');
const pages=JSON.parse(source.slice('const PAGES='.length,at).trim().replace(/;$/,''));
const replaceCopy=(path,oldText,newText)=>{
 const current=pages[path].body;
 if(newText && current.includes(newText))return;
 if(current.includes(oldText))pages[path].body=current.replace(oldText,newText);
 else if(newText)throw Error('Public copy changed unexpectedly: '+path);
};
replaceCopy('/index.html','MEFRIONは公開準備中です。このページは現在の開発・検証状況を説明するもので、App Storeでの一般提供開始をお知らせするものではありません。','MEFRIONの使い方と、写真やアカウント情報の取り扱いをご案内します。');
replaceCopy('/privacy.html','App Storeでの一般公開は準備中です。','');
replaceCopy('/terms.html','App Storeでの一般公開は準備中です。','');
replaceCopy('/terms.html','現行の提供方針は18歳以上、無料です。犬や猫を飼っていなくても登録できます。未成年者向け提供や有料機能を始める場合は、条件を別途案内します。','無料で利用でき、犬や猫を飼っていなくても登録できます。有料機能を始める場合は、条件を別途案内します。');
replaceCopy('/privacy.html','残るファイルと認証情報は削除処理で順次消去します。','残るファイルと認証情報は通常24時間以内に削除します。完了後、この端末でアプリを開いた時にお知らせします。24時間を超えた場合はお問い合わせください。');
replaceCopy('/privacy.html','公開投稿はほかの利用者から閲覧されます。','公開投稿の写真・動画と投稿文は公開前に運営が確認し、承認後にほかの利用者から閲覧されます。コメントも投稿前に不適切な内容を確認します。');
replaceCopy('/terms.html','問題のある投稿やアカウントはアプリから通報できます。','公開投稿の写真・動画と投稿文は公開前に運営が確認します。問題のある投稿やアカウントはアプリから通報できます。');
const reviewCopy='公開投稿の写真・動画と投稿文は公開前に運営が確認します。';
pages['/terms.html'].body=pages['/terms.html'].body.replaceAll(reviewCopy+reviewCopy,reviewCopy);
for(const path of ['/privacy.html','/terms.html'])replaceCopy(path,'2026年11月1日更新','2026年11月2日更新');
const analyticsCopy='<p>利用状況と品質の改善のため、アプリが生成するランダムな端末識別子、起動・機能の利用・処理の成否・所要時間・アプリバージョンを収集します。ログイン中はアカウントと関連付けます。写真・投稿文・パスワード・認証コードはこの利用分析へ送りません。識別子はサーバーでハッシュ化し、詳細記録は最大90日を目安に保持します。広告追跡には使用しません。</p>';
if(!pages['/privacy.html'].body.includes('ランダムな端末識別子'))pages['/privacy.html'].body=pages['/privacy.html'].body.replace('<h2>2. 取り扱う情報と使い道</h2>','<h2>2. 取り扱う情報と使い道</h2>'+analyticsCopy);
const sharingCopy='<p>共有リンクの到着数を調べるため、リンク先へ移動する際にブラウザごとのランダムな識別子をCookieへ最大30日保存し、到着した共有先の種類を記録します。Cookieの識別子はサーバーではハッシュ化します。この到着情報をアプリのインストールやアカウントと結び付けず、SNSへの投稿内容は収集しません。</p>';
if(!pages['/privacy.html'].body.includes('共有リンクの到着数'))pages['/privacy.html'].body=pages['/privacy.html'].body.replace(analyticsCopy,analyticsCopy+sharingCopy);

for(const name of ['security.js','security.css','content.js','overview.js','overview.css'])pages['/console/'+name]={type:name.endsWith('.js')?'application/javascript; charset=utf-8':'text/css; charset=utf-8',body:await readFile(new URL('console/'+name,root),'utf8')};
if(!pages['/console/cloud.js'].body.includes("if(typeof clearOverview==='function')clearOverview();"))
 pages['/console/cloud.js'].body=pages['/console/cloud.js'].body.replace("if(typeof clearSecurity==='function')clearSecurity();", "if(typeof clearSecurity==='function')clearSecurity();if(typeof clearOverview==='function')clearOverview();");
if(!pages['/console/cloud.js'].body.includes("let panel=document.body?.dataset?.consolePanel||'overview'"))
 pages['/console/cloud.js'].body=pages['/console/cloud.js'].body.replace("let panel=document.body?.dataset?.consolePanel||'reports'", "let panel=document.body?.dataset?.consolePanel||'overview'");
if(!pages['/console/cloud.js'].body.includes("if(panel==='overview'&&typeof refreshOverview==='function')return refreshOverview();"))
 pages['/console/cloud.js'].body=pages['/console/cloud.js'].body.replace("if(panel==='security'&&typeof refreshSecurity==='function')return refreshSecurity();", "if(panel==='overview'&&typeof refreshOverview==='function')return refreshOverview();if(panel==='security'&&typeof refreshSecurity==='function')return refreshSecurity();");
if(!pages['/console/cloud.js'].body.includes("if(typeof clearContent==='function')clearContent();"))
 pages['/console/cloud.js'].body=pages['/console/cloud.js'].body.replace("if(typeof clearSecurity==='function')clearSecurity();", "if(typeof clearSecurity==='function')clearSecurity();if(typeof clearContent==='function')clearContent();");
if(!pages['/console/cloud.js'].body.includes("if(panel==='content'&&typeof refreshContent==='function')return refreshContent();"))
 pages['/console/cloud.js'].body=pages['/console/cloud.js'].body.replace("if(panel==='security'&&typeof refreshSecurity==='function')return refreshSecurity();", "if(panel==='security'&&typeof refreshSecurity==='function')return refreshSecurity();if(panel==='content'&&typeof refreshContent==='function')return refreshContent();");
const fragment=await readFile(new URL('console/security-panel.html',root),'utf8');
const contentFragment=await readFile(new URL('console/content-panel.html',root),'utf8');
const overviewFragment=await readFile(new URL('console/overview-panel.html',root),'utf8');
let html=pages['/console/'].body;
if(!html.includes('src="/console/overview.js"'))html=html.replace('<body>','<link rel="stylesheet" href="/console/overview.css"><script src="/console/overview.js" defer></script><body>');
if(!html.includes('src="/console/security.js"'))html=html.replace('<body>','<link rel="stylesheet" href="/console/security.css"><script src="/console/security.js" defer></script><body>');
if(!html.includes('src="/console/content.js"'))html=html.replace('<body>','<script src="/console/content.js" defer></script><body>');
if(!html.includes('id="security-nav"'))html=html.replace('<div id="session" hidden>','<div id="session" hidden><button id="security-nav" type="button">セキュリティ</button><button id="reports-nav" type="button">通報</button>');
if(!html.includes('id="content-nav"'))html=html.replace('<button id="reports-nav" type="button">通報</button>','<button id="reports-nav" type="button">通報</button><button id="content-nav" type="button">投稿の確認</button>');
if(!html.includes('id="overview-nav"'))html=html.replace('<div id="session" hidden>','<div id="session" hidden><button id="overview-nav" type="button">ホーム</button>');
const start=html.indexOf('<section id="security-section"');
if(start>=0){const end=html.indexOf('<!-- security-panel-end -->',start);if(end<0)throw Error('Missing security end marker');html=html.slice(0,start)+fragment+'<!-- security-panel-end -->'+html.slice(end+'<!-- security-panel-end -->'.length);}
else html=html.replace('<section id="confirmation"',fragment+'<!-- security-panel-end --><section id="confirmation"');
const contentStart=html.indexOf('<section id="content-section"');
if(contentStart>=0){const end=html.indexOf('<!-- content-panel-end -->',contentStart);if(end<0)throw Error('Missing content end marker');html=html.slice(0,contentStart)+contentFragment+'<!-- content-panel-end -->'+html.slice(end+'<!-- content-panel-end -->'.length);}
else html=html.replace('<section id="confirmation"',contentFragment+'<!-- content-panel-end --><section id="confirmation"');
const overviewStart=html.indexOf('<section id="overview-section"');
if(overviewStart>=0){const end=html.indexOf('<!-- overview-panel-end -->',overviewStart);if(end<0)throw Error('Missing overview end marker');html=html.slice(0,overviewStart)+overviewFragment+'<!-- overview-panel-end -->'+html.slice(end+'<!-- overview-panel-end -->'.length);}
else html=html.replace('<section id="confirmation"',overviewFragment+'<!-- overview-panel-end --><section id="confirmation"');
pages['/console/'].body=html;
pages['/console/security']={...pages['/console/'],body:html.replace('<body>','<body data-console-panel="security">').replace('<title>MEFRION クラウド運営管理</title>','<title>セキュリティ監視｜MEFRION</title>')};
pages['/console/content']={...pages['/console/'],body:html.replace('<body>','<body data-console-panel="content">').replace('<title>MEFRION クラウド運営管理</title>','<title>公開前の投稿｜MEFRION</title>')};
await writeFile(path,'const PAGES='+JSON.stringify(pages)+';'+source.slice(at));
await mkdir(new URL('dist/',root),{recursive:true});
for(const name of ['index.html','privacy.html','terms.html'])await writeFile(new URL('dist/'+name,root),pages['/'+name].body);

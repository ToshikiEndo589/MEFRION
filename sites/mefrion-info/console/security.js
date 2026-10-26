'use strict';
const securityKinds={secret_probe:'秘密ファイル探索の疑い',path_traversal:'パス探索の疑い',injection_probe:'不正入力の疑い',auth_denied:'認証拒否',access_denied:'アクセス拒否',rate_limited:'回数制限',not_found:'404応答',method_denied:'未対応のメソッド',server_error:'サーバーエラー',profile_changed:'プロフィール変更',account_retirement:'退会の受付',operator_changed:'運営権限の変更',repeated_signals:'短時間の繰り返し検知'};
const securitySeverity={info:'情報',low:'低',medium:'中',high:'高',critical:'緊急'};
const securityOutcome={observed:'観測',denied:'拒否応答',limited:'回数制限',failed:'処理失敗',allowed:'許可'};
const securitySourceLabels={vercel:'Vercelサイト',app_audit:'アプリの監査記録','edge:security-collector':'ログ収集API','edge:private-image':'非公開画像API','edge:private-video':'非公開動画API','edge:public-image':'公開画像API','edge:public-video':'公開動画API','edge:shared-page':'共有ページAPI','edge:cloud-worker':'クラウド処理','edge:stock-worker':'運営投稿処理','edge:asset-ingest':'素材取り込み','edge:database-backup':'データベースバックアップ','edge:offsite-backup':'オフサイトバックアップ'};
let securityData=null,securityRows=[],securityCursor=null,securitySerial=0,securityTimer=null,securityView='overview';
const securityDrafts=new Map();
const sec=id=>document.getElementById(id);
const secNumber=n=>Number.isFinite(Number(n))?new Intl.NumberFormat('ja-JP').format(Number(n)):'—';
function secTime(value,short=false){const date=new Date(value);return Number.isFinite(date.getTime())?new Intl.DateTimeFormat('ja-JP',{timeZone:'Asia/Tokyo',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',...(short?{}:{second:'2-digit'})}).format(date):'—';}
function secNode(tag,text,className){const e=document.createElement(tag);if(text!==undefined)e.textContent=text;if(className)e.className=className;return e;}
function secBadge(value,kind='severity'){return secNode('span',kind==='severity'?(securitySeverity[value]||'情報'):value,'sec-badge '+(['info','low','medium','high','critical'].includes(value)?value:'neutral'));}
function secEmpty(parent,text='この期間の記録はありません。'){parent.replaceChildren(secNode('p',text,'sec-empty'));}
function secFilters(){return {p_hours:Number(sec('sec-hours').value),p_kind:sec('sec-kind').value||null,p_severity:sec('sec-severity').value||null,p_source:sec('sec-source').value||null,p_limit:50};}
function clearSecurity(){securitySerial++;securityDrafts.clear();securityData=null;securityRows=[];securityCursor=null;if(securityTimer)clearTimeout(securityTimer);securityTimer=null;const root=sec('security-section');if(root)root.hidden=true;for(const id of ['sec-events','sec-incidents','sec-sources','sec-coverage','sec-types','sec-targets','sec-chart','sec-detail-body'])sec(id)?.replaceChildren();sec('sec-detail')?.close();document.body.classList.remove('security-console');sec('main-heading').hidden=false;sec('cancel-login').hidden=false;}
function secSchedule(){if(securityTimer)clearTimeout(securityTimer);securityTimer=setTimeout(()=>{if(panel==='security'&&mfaComplete&&token&&!document.hidden&&sec('sec-auto').checked&&['overview','coverage'].includes(securityView)&&!sec('sec-detail').open&&!document.querySelector('#security-section textarea:focus'))perform(()=>refreshSecurity());else secSchedule();},30000);}
async function refreshSecurity(more=false){
 const serial=++securitySerial,stamp=generation;
 sec('security-section').hidden=false;document.body.classList.add('security-console');sec('main-heading').hidden=true;sec('cancel-login').hidden=true;
 sec('seed-section').hidden=true;sec('queue').hidden=true;sec('seed-refresh').hidden=true;sec('refresh').hidden=true;
 sec('server-health-refresh')?.closest('details')?.setAttribute('hidden','');
 sec('sec-connection').textContent='更新中';sec('sec-connection').className='sec-status-pill';
 const filters=secFilters();if(more&&securityCursor)Object.assign(filters,{p_before:securityCursor.occurred_at,p_before_id:securityCursor.id});
 try{
  const data=await request('/rest/v1/rpc/mefrion_security_dashboard',filters,token,false);
  if(serial!==securitySerial||stamp!==generation||!mfaComplete||panel!=='security')return;
  securityData=data;const incoming=(data.events||[]).slice(0,50);const next=(data.events||[]).length>50;
  securityRows=more?[...securityRows,...incoming.filter(row=>!securityRows.some(x=>x.id===row.id))]:incoming;
  securityCursor=next?incoming.at(-1):null;
  sec('sec-more').hidden=!securityCursor;sec('sec-message').textContent='';status('');
  renderSecurity(data);const recent=(data.coverage||[]).some(row=>Date.now()-new Date(row.last_seen).getTime()<900000);sec('sec-connection').textContent=recent?'最近の受信を確認':(data.coverage||[]).length?'最近の受信なし（通信がない場合も含む）':'記録元からの受信待ち';sec('sec-connection').className='sec-status-pill'+(recent?' live':'');
  secSchedule();
 }catch(error){
  if(serial!==securitySerial||stamp!==generation)return;
  sec('sec-connection').textContent='確認が必要';
  if(error.status===403){sec('sec-message').textContent='二段階認証は完了しています。セキュリティ画面を開く運営権限の有効化をお待ちください。';status(sec('sec-message').textContent);}
  else{sec('sec-message').textContent=error.name==='TimeoutError'?'更新に時間がかかっています。もう一度更新してください。':error instanceof TypeError?'通信できませんでした。接続を確認して更新してください。':error.message;}
  if(!securityData){for(const id of ['sec-signals','sec-suspected','sec-denied','sec-open'])sec(id).textContent='—';sec('sec-chart').textContent='取得できる記録がまだありません。';}
  secSchedule();
 }
}
function renderSecurity(data){
 const summary=data.summary||{};
 for(const [id,key]of [['sec-signals','signals'],['sec-suspected','suspected'],['sec-denied','denied']])sec(id).textContent=secNumber(summary[key]);
 sec('sec-open').textContent=secNumber(data.open_incidents);sec('sec-nav-incidents').textContent=secNumber(data.open_incidents);
 sec('sec-updated').textContent='最終更新 '+secTime(data.generated_at)+' JST';
 sec('sec-retention').textContent='収集開始 '+secTime(data.started_at)+' JST / 詳細30日・集計90日 / 集計からテストデータを除外（受信状態を除く）';
 renderSecurityChart(data.timeline||[],data.hours);
 renderSecurityBars(sec('sec-types'),data.types||[],row=>securityKinds[row.kind]||'その他');
 renderSecurityBars(sec('sec-targets'),data.targets||[],row=>row.target);
 const sources=sec('sec-sources');sources.replaceChildren();
 for(const row of data.sources||[]){const e=secNode('div',undefined,'sec-source-row');e.append(secNode('code',row.source_key),secNode('strong',secNumber(row.n)+'件'),secNode('time','最終 '+secTime(row.last_seen)));sources.append(e);}if(!sources.children.length)secEmpty(sources,'同じ接続元をまとめられる記録はまだありません。');
 renderSecurityEvents();renderSecurityIncidents(data.incidents||[]);renderSecurityCoverage(data);
 const limitations=sec('sec-limitations');limitations.replaceChildren();for(const text of data.limitations||[])limitations.append(secNode('li',text));
 const lost=(data.coverage||[]).reduce((n,r)=>n+Number(r.lost||0),0),omitted=(data.coverage||[]).reduce((n,r)=>n+Number(r.details_omitted||0),0);
 sec('sec-quality').textContent=lost||omitted?'報告された送信失敗 '+secNumber(lost)+'件 / 保存上限による詳細省略 '+secNumber(omitted)+'件。件数は収集できた記録の範囲です。':'記録の収集はベストエフォートです。到達前の遮断や、受信できなかった通信は件数に含みません。';
}
function renderSecurityBars(parent,rows,label){parent.replaceChildren();if(!rows.length){secEmpty(parent);return;}const max=Math.max(1,...rows.map(r=>Number(r.count)));for(const row of rows){const item=secNode('div',undefined,'sec-bar-row');item.append(secNode('span',label(row)),secNode('strong',secNumber(row.count)));const track=secNode('div',undefined,'sec-bar-track'),fill=secNode('div',undefined,'sec-bar-fill');fill.style.width=(Math.max(0,Number(row.count))/max*100)+'%';track.append(fill);item.append(track);parent.append(item);}}
function renderSecurityChart(rows,hours){
 const root=sec('sec-chart');root.replaceChildren();
 if(!rows.length){root.textContent='この期間に収集したシグナルはありません。';root.setAttribute('aria-label','記録0件。未収集の通信は含みません。');return;}
 const ns='http://www.w3.org/2000/svg',svg=document.createElementNS(ns,'svg');svg.setAttribute('viewBox','0 0 900 230');svg.setAttribute('aria-hidden','true');
 const make=(tag,attrs,text)=>{const e=document.createElementNS(ns,tag);for(const[k,v]of Object.entries(attrs))e.setAttribute(k,String(v));if(text!==undefined)e.textContent=text;svg.append(e);return e;};
 const interval=hours>168?86400000:3600000,end=Math.floor(Date.now()/interval)*interval,start=end-(hours>168?Math.ceil(hours/24)-1:hours-1)*interval;
 const lookup=new Map(rows.map(r=>[Math.floor(new Date(r.at).getTime()/interval)*interval,r]));const points=[];
 for(let t=start;t<=end;t+=interval)points.push({t,n:Number(lookup.get(t)?.signals||0),s:Number(lookup.get(t)?.suspected||0)});
 const maximum=Math.max(1,...points.map(p=>p.n)),x=i=>45+i/(Math.max(1,points.length-1))*840,y=n=>190-n/maximum*160;
 for(let i=0;i<=4;i++){const yy=190-i*40;make('line',{x1:45,x2:885,y1:yy,y2:yy,stroke:'#e7edf5','stroke-dasharray':'3 4'});make('text',{x:32,y:yy+4,'text-anchor':'end',fill:'#8291a7','font-size':10},secNumber(Math.round(maximum*i/4)));}
 make('polygon',{points:`45,190 ${points.map((p,i)=>x(i)+','+y(p.n)).join(' ')} 885,190`,fill:'#edf1ff'});
 make('polyline',{points:points.map((p,i)=>x(i)+','+y(p.n)).join(' '),fill:'none',stroke:'#5776dc','stroke-width':2.5});
 make('polyline',{points:points.map((p,i)=>x(i)+','+y(p.s)).join(' '),fill:'none',stroke:'#15b5a1','stroke-width':2});
 for(const i of [0,Math.floor((points.length-1)/3),Math.floor((points.length-1)*2/3),points.length-1]){const d=new Date(points[i].t);const label=new Intl.DateTimeFormat('ja-JP',{timeZone:'Asia/Tokyo',...(hours>24?{month:'2-digit',day:'2-digit'}:{hour:'2-digit',minute:'2-digit'})}).format(d);make('text',{x:x(i),y:219,'text-anchor':i===0?'start':i===points.length-1?'end':'middle',fill:'#8291a7','font-size':10},label);}
 root.append(svg);root.setAttribute('aria-label',rows.map(r=>secTime(r.at,true)+' 記録'+secNumber(r.signals)+'件・攻撃の疑い'+secNumber(r.suspected||0)+'件').join('。'));
}
function renderSecurityEvents(){const body=sec('sec-events');body.replaceChildren();for(const row of securityRows){const tr=secNode('tr');tr.append(secNode('td',secTime(row.occurred_at)),secNode('td',securityKinds[row.kind]||'その他'));const severity=secNode('td');severity.append(secBadge(row.severity));tr.append(severity);const target=secNode('td');target.append(secNode('code',row.target));tr.append(target,secNode('td',(securityOutcome[row.outcome]||'観測')+' · '+row.status));const detail=secNode('td'),button=secNode('button','詳細');button.type='button';button.addEventListener('click',()=>showSecurityDetail(row));detail.append(button);tr.append(detail);body.append(tr);}if(!securityRows.length){const tr=secNode('tr'),td=secNode('td','この条件の記録はありません。','sec-empty');td.colSpan=6;tr.append(td);body.append(tr);}sec('sec-event-count').textContent=secNumber(securityRows.length)+'件を表示 / フィルターはログ一覧に適用されます。';}
function showSecurityDetail(row){const dl=sec('sec-detail-body');dl.replaceChildren();for(const[key,value]of [['記録ID',row.id],['記録時刻',secTime(row.occurred_at)+' JST'],['種類',securityKinds[row.kind]||row.kind],['重要度',securitySeverity[row.severity]||'情報'],['応答',row.status+' / '+(securityOutcome[row.outcome]||'観測')],['対象',row.target],['記録元',securitySourceLabels[row.source]||row.source],['接続元ID',row.source_key==='unavailable'?'取得できず':row.source_key],['地域（参考）',row.country||'不明'],['照合用リクエストID',row.request_id||'なし']])dl.append(secNode('dt',key),secNode('dd',String(value)));sec('sec-detail').showModal();}
function renderSecurityIncidents(rows){const root=sec('sec-incidents');root.replaceChildren();for(const row of rows){const card=secNode('article',undefined,'sec-incident'),head=secNode('div',undefined,'sec-incident-head');head.append(secBadge(row.severity),secNode('h3',securityKinds[row.kind]||'繰り返し検知'));card.append(head,secNode('p',secNumber(row.events)+'件 / '+row.source_key+' / 更新 '+secTime(row.updated_at)),secNode('p','状態：'+({open:'未対応',acknowledged:'確認中',resolved:'対応済み'}[row.state]||row.state)));const note=secNode('textarea');note.value=securityDrafts.get(row.id)??row.note??'';note.maxLength=400;note.addEventListener('input',()=>securityDrafts.set(row.id,note.value));note.placeholder='対応メモ（秘密情報や個人情報は書かない）';note.setAttribute('aria-label','インシデントの対応メモ');card.append(note);const actions=secNode('div',undefined,'sec-incident-controls');for(const [state,label]of [['acknowledged','確認中にする'],['resolved','対応済みにする'],['open','未対応に戻す']]){const button=secNode('button',state===row.state?'メモを保存':label);button.type='button';button.addEventListener('click',()=>perform(async()=>{try{await request('/rest/v1/rpc/mefrion_security_incident_update',{p_id:row.id,p_state:state,p_version:row.version,p_note:note.value},token,false);securityDrafts.delete(row.id);await refreshSecurity();sec('sec-message').textContent='対応状態を保存しました。';}catch(error){sec('sec-message').textContent=error.status===409?'別の更新があります。更新ボタンで再取得してください。':error.message;}}));actions.append(button);}card.append(actions);root.append(card);}if(!rows.length)secEmpty(root,'確認対象のインシデントはありません。');}
function renderSecurityCoverage(data){const root=sec('sec-coverage');root.replaceChildren();const actual=new Map((data.coverage||[]).map(row=>[row.source,row]));for(const [name,label]of Object.entries(securitySourceLabels)){const row=actual.get(name),item=secNode('div',undefined,'sec-coverage-row'),text=secNode('div');text.append(secNode('strong',label));const last=row?'最終受信 '+secTime(row.last_seen)+' JST / シグナル '+secNumber(row.accepted)+'件（テスト含む）':'配備後の受信待ち。アクセスがない場合も受信待ちになります。';text.append(secNode('small',last));if(row?.lost)text.append(secNode('small','送信できなかった記録 '+secNumber(row.lost)+'件'));item.append(text,secBadge(!row?'受信待ち':Date.now()-new Date(row.last_seen).getTime()<900000?'最近の受信あり':'最近の受信なし','label'));root.append(item);}}
function securityCSV(rows){const cell=value=>{let s=String(value??'');if(/^[=+\-@\t\r]/.test(s))s="'"+s;return '"'+s.replace(/"/g,'""')+'"';};const fields=['id','occurred_at','source','kind','severity','outcome','status','target','source_key','country','request_id'];return '\uFEFF'+[fields.map(cell).join(','),...rows.map(row=>fields.map(k=>cell(row[k])).join(','))].join('\r\n');}
async function exportSecurity(){if(!mfaComplete||!token)throw Error('運営アカウントでログインしてください。');const stamp=generation,filters={...secFilters(),p_limit:100};const rows=[];for(let i=0;i<10;i++){const data=await request('/rest/v1/rpc/mefrion_security_dashboard',filters,token,false);if(stamp!==generation)return;const batch=(data.events||[]).slice(0,100);rows.push(...batch);if((data.events||[]).length<=100||!batch.length)break;filters.p_before=batch.at(-1).occurred_at;filters.p_before_id=batch.at(-1).id;}const blob=new Blob([securityCSV(rows)],{type:'text/csv;charset=utf-8'}),url=URL.createObjectURL(blob),link=secNode('a');link.href=url;link.download='MEFRION-security-'+new Date().toISOString().slice(0,10)+'.csv';link.click();setTimeout(()=>URL.revokeObjectURL(url),1000);sec('sec-message').textContent=secNumber(rows.length)+'件を書き出しました（最大1,000件）。';}
function secShowView(view){securityView=view;for(const el of document.querySelectorAll('[data-sec-panel]'))el.hidden=el.dataset.secPanel!==view;for(const button of document.querySelectorAll('[data-sec-view]'))button.classList.toggle('active',button.dataset.secView===view);}
if(document.getElementById('security-section')){
 for(const [value,label] of Object.entries(securitySourceLabels)){if(!Array.from(sec('sec-source').options).some(option=>option.value===value)){const option=secNode('option',label);option.value=value;sec('sec-source').append(option);}}
 sec('sec-refresh').addEventListener('click',()=>perform(()=>refreshSecurity()));sec('sec-more').addEventListener('click',()=>perform(()=>refreshSecurity(true)));sec('sec-export').addEventListener('click',()=>perform(exportSecurity));sec('sec-detail-close').addEventListener('click',()=>sec('sec-detail').close());
 for(const id of ['sec-hours','sec-kind','sec-severity','sec-source'])sec(id).addEventListener('change',()=>perform(()=>refreshSecurity()));
 for(const button of document.querySelectorAll('[data-sec-view]'))button.addEventListener('click',()=>secShowView(button.dataset.secView));
 sec('security-nav').addEventListener('click',()=>perform(async()=>{panel='security';await refreshSecurity();}));
 sec('reports-nav').addEventListener('click',()=>perform(async()=>{panel='reports';clearSecurity();sec('server-health-refresh')?.closest('details')?.removeAttribute('hidden');sec('seed-refresh').hidden=false;sec('refresh').hidden=false;await refresh();}));
}

'use strict';
const ops=id=>document.getElementById(id);
const opsNode=(tag,value)=>{const el=document.createElement(tag);if(value!==undefined)el.textContent=String(value);return el;};
const opsCount=value=>new Intl.NumberFormat('ja-JP').format(Number(value)||0);
const opsDate=value=>value?new Intl.DateTimeFormat('ja-JP',{timeZone:'Asia/Tokyo',month:'numeric',day:'numeric',hour:'2-digit',minute:'2-digit'}).format(new Date(value)):'—';
let opsCases=[],opsStamp=0,opsTimer=null,opsPreviousAttention=null;
function clearOverview(event){opsStamp++;if(opsTimer)clearTimeout(opsTimer);opsTimer=null;document.body.classList.remove('ops-console');document.title='MEFRION クラウド運営管理';ops('overview-section').hidden=true;ops('ops-search-results').replaceChildren();ops('ops-case-dialog')?.close();ops('ops-history-dialog')?.close();if(event?.currentTarget){for(const id of ['overview-nav','reports-nav','content-nav','security-nav','seed-refresh'])ops(id)?.classList.toggle('active',id===event.currentTarget.id);}}
function scheduleOverview(){if(opsTimer)clearTimeout(opsTimer);opsTimer=setTimeout(()=>{if(panel==='overview'&&mfaComplete&&token&&!document.hidden&&!busy&&!ops('ops-case-dialog').open&&!ops('ops-history-dialog').open&&!document.querySelector('#overview-section input:focus,#overview-section textarea:focus,#overview-section select:focus'))perform(refreshOverview);else scheduleOverview();},60000);}
function opsNav(){for(const id of ['overview-nav','reports-nav','content-nav','security-nav','seed-refresh'])ops(id)?.classList.toggle('active',id==='overview-nav');}
function opsMetric(label,value,hint){const card=opsNode('article');card.className='ops-metric';card.append(opsNode('span',label),opsNode('strong',opsCount(value)),opsNode('small',hint));return card;}
function opsLine(label,value){const row=opsNode('div');row.className='ops-statline';row.append(opsNode('span',label),opsNode('strong',value));return row;}
function opsAlert(title,detail,nav,urgent=false){const card=opsNode('div');card.className='ops-alert'+(urgent?' urgent':'');card.append(opsNode('strong',title),opsNode('p',detail));if(nav){const button=opsNode('button','確認する →');button.type='button';button.addEventListener('click',()=>ops(nav)?.click());card.append(button);}return card;}
async function refreshOverview(){
 if(!mfaComplete||!token)throw Error('運営アカウントで二段階認証を完了してください。');
 if(typeof clearSecurity==='function')clearSecurity();if(typeof clearContent==='function')clearContent();
 panel='overview';document.body.classList.add('ops-console');ops('overview-section').hidden=false;ops('queue').hidden=true;ops('seed-section').hidden=true;
 ops('main-heading').hidden=true;ops('refresh').hidden=true;ops('seed-refresh').hidden=false;
 ops('server-health-refresh')?.closest('details')?.removeAttribute('hidden');opsNav();
 const stamp=++opsStamp;ops('ops-message').textContent='更新中…';
 try{
  const [data,cases,delivery]=await Promise.all([rpc('operator_workspace'),rpc('operator_case_list'),rpc('operator_alert_status')]);
  if(stamp!==opsStamp||panel!=='overview')return;
  opsCases=cases;renderOverview(data);renderCases(cases);
  ops('ops-email-status').textContent=delivery.last_sent_at?'メール通知：最終送信 '+opsDate(delivery.last_sent_at):'メール通知：初回送信待ち';
  if(delivery.last_failure_at&&(!delivery.last_sent_at||new Date(delivery.last_failure_at)>new Date(delivery.last_sent_at)))ops('ops-email-status').textContent='メール通知：送信エラーを確認してください';
  ops('ops-message').textContent='';status('運営ホームを更新しました。');scheduleOverview();await refreshProductAnalytics();
 }catch(error){if(stamp===opsStamp)ops('ops-message').textContent=error.message;throw error;}
}
function renderOverview(data){
 const attention=Number(data.pending_reports)+Number(data.pending_posts)+Number(data.overdue_cases)+Number(data.failed_jobs);
 document.title=(attention>0?'● '+attention+'件 · ':'')+'MEFRION 運営管理';
 if(opsPreviousAttention!==null&&attention>opsPreviousAttention&&globalThis.Notification?.permission==='granted')new globalThis.Notification('MEFRIONの確認事項が増えました',{body:'運営ダッシュボードを開いて確認してください。'});
 opsPreviousAttention=attention;
 const metrics=ops('ops-metrics');metrics.replaceChildren(
  opsMetric('未対応の通報',data.pending_reports,'通報を確認'),
  opsMetric('公開前の投稿',data.pending_posts,'写真・動画の確認'),
  opsMetric('対応中の相談',data.open_cases,'メールの相談を記録'),
  opsMetric('直近24時間の登録',data.signups_24h,'新しく登録した人')
 );
 const alerts=ops('ops-alerts');alerts.replaceChildren();
 if(data.pending_reports>0)alerts.append(opsAlert('通報が '+opsCount(data.pending_reports)+' 件あります','内容を確認し、対応を記録してください。','reports-nav',true));
 if(data.pending_posts>0)alerts.append(opsAlert('公開待ち '+opsCount(data.pending_posts)+' 件','最も古い投稿：'+opsDate(data.pending_posts_oldest),'content-nav',true));
 if(data.overdue_cases>0)alerts.append(opsAlert('期限を過ぎた相談 '+opsCount(data.overdue_cases)+' 件','問い合わせ一覧で対応状況を確認してください。',null,true));
 if(data.failed_jobs>0)alerts.append(opsAlert('失敗した処理 '+opsCount(data.failed_jobs)+' 件','サーバー稼働状況を確認してください。',null,true));
 if(data.server_errors_24h>0)alerts.append(opsAlert('サーバーエラー '+opsCount(data.server_errors_24h)+' 件','直近24時間に記録したエラーです。','security-nav'));
 if(!alerts.children.length)alerts.append(opsAlert('いま急ぎの対応はありません','新しい通報や公開待ち投稿が入ると、ここに表示します。'));
 const activity=ops('ops-activity');activity.replaceChildren(
  opsLine('公開投稿（直近24時間）',opsCount(data.published_24h)),
  opsLine('公開中の投稿',opsCount(data.published_total)),
  opsLine('7日以内の登録者',opsCount(data.signups_7d)),
  opsLine('7日以内の登録者で初投稿済み',opsCount(data.new_users_first_post_7d)),
  opsLine('30日以内に別の日にも投稿した人',opsCount(data.returning_posters_30d)),
  opsLine('写真・動画の保存量',formatBytes(data.storage_bytes)),
  opsLine('データベース容量',formatBytes(data.database_bytes))
 );
 const actions=ops('ops-actions');actions.replaceChildren();
 for(const action of data.recent_actions||[]){const row=opsNode('div');row.className='ops-action';row.append(opsNode('span',action.category+' · '+action.action),opsNode('small',opsDate(action.at)));actions.append(row);}
 if(!actions.children.length)actions.append(opsNode('p','最近の対応記録はありません。'));
}
function formatBytes(bytes){const n=Number(bytes)||0;return n>=1073741824?(n/1073741824).toFixed(1)+' GB':n>=1048576?(n/1048576).toFixed(1)+' MB':opsCount(n)+' B';}
function renderCases(rows){
 const root=ops('ops-cases');root.replaceChildren();
 if(!rows.length){const p=opsNode('p','記録した問い合わせはまだありません。');p.className='ops-empty';root.append(p);return;}
 for(const row of rows){
  const item=opsNode('article');item.className='ops-case';
  const main=opsNode('div');main.className='ops-case-main';
  main.append(opsNode('strong',row.subject));
  const details=opsNode('p',(row.contact_email||'返信先なし')+' · '+opsDate(row.created_at));main.append(details);
  if(row.contact_email){const reply=opsNode('a','メールで返信 ↗');reply.href='mailto:'+encodeURIComponent(row.contact_email)+'?subject='+encodeURIComponent('Re: '+row.subject);reply.rel='noreferrer';main.append(reply);}
  if(row.detail)main.append(opsNode('p',row.detail));
  const badge=opsNode('span',row.state==='resolved'?'解決':row.state==='waiting'?'回答待ち':'対応中');badge.className='ops-chip'+(row.priority==='urgent'?' urgent':'');main.append(badge);
  if(row.due_at)main.append(opsNode('small',' 期限 '+opsDate(row.due_at)));
  main.append(opsNode('small',' · 担当 '+(row.assigned_email||'未割当')));
  const controls=opsNode('div');controls.className='ops-case-controls';
  const state=opsNode('select');state.setAttribute('aria-label',row.subject+' の状態');
  for(const [value,label] of [['open','対応中'],['waiting','回答待ち'],['resolved','解決']]){const option=opsNode('option',label);option.value=value;state.append(option);}state.value=row.state;
  const priority=opsNode('select');priority.setAttribute('aria-label',row.subject+' の優先度');
  for(const [value,label] of [['normal','通常'],['urgent','至急']]){const option=opsNode('option',label);option.value=value;priority.append(option);}priority.value=row.priority;
  const assignment=opsNode('select');assignment.setAttribute('aria-label',row.subject+' の担当');
  for(const [value,label] of [['unassigned','担当なし'],['mine','自分が担当']]){const option=opsNode('option',label);option.value=value;assignment.append(option);}assignment.value=row.mine?'mine':'unassigned';
  const due=opsNode('input');due.type='datetime-local';due.setAttribute('aria-label',row.subject+' の対応期限');if(row.due_at)due.value=new Date(new Date(row.due_at).getTime()-new Date().getTimezoneOffset()*60000).toISOString().slice(0,16);
  const note=opsNode('textarea');note.maxLength=2000;note.placeholder='解決時は対応内容を入力';note.value=row.resolution||'';
  const save=opsNode('button','保存');save.type='button';save.addEventListener('click',()=>perform(async()=>{
   await rpc('operator_case_update',{p_id:row.id,p_version:row.version,p_state:state.value,p_priority:priority.value,p_due_at:due.value?new Date(due.value).toISOString():null,p_resolution:note.value,p_assign_to_me:assignment.value==='mine'});
   await refreshOverview();status('問い合わせを更新しました。');
  }));if(row.assigned_to&&!row.mine){save.disabled=true;save.title='別の担当者が対応中です。';}
  controls.append(state,priority,assignment,due,note,save);item.append(main,controls);root.append(item);
 }
}
function renderPostResults(rows){
 const root=ops('ops-search-results');root.replaceChildren();
 if(!rows.length){const p=opsNode('p','該当する公開投稿はありません。');p.className='ops-empty';root.append(p);return;}
 for(const row of rows){const item=opsNode('article');item.className='ops-result';const main=opsNode('div');main.className='ops-result-main';
  main.append(opsNode('strong',row.pet_name+' · '+({published:'公開中',review:'確認待ち',stopped:'停止',processing:'処理中',pending:'準備中'}[row.state]||row.state)));
  main.append(opsNode('p',row.body||'本文なし'),opsNode('small',opsDate(row.created_at)+' · '+row.id+' · 通報 '+opsCount(row.reports)+' 件'));
  const button=opsNode('button','対応履歴');button.type='button';button.addEventListener('click',()=>perform(async()=>{
   const history=await rpc('operator_post_history',{p_post:row.id});showPostHistory(row,history);
  }));item.append(main,button);root.append(item);
 }
}
function showPostHistory(row,data){const root=ops('ops-history');root.replaceChildren();root.append(opsNode('p',row.pet_name+' · '+row.id));
 const review=data.review;if(review)root.append(opsNode('p','公開前確認：'+review.state+' / '+opsDate(review.decided_at)+' / '+review.reviewer+' / '+(review.note||'理由なし')));
 for(const report of data.reports||[])root.append(opsNode('p','通報：'+report.reason+' / '+report.state+' / '+opsDate(report.created_at)));
 for(const decision of data.decisions||[])root.append(opsNode('p','対応：'+decision.decision+' / '+opsDate(decision.created_at)+' / '+decision.reviewer+' / '+decision.note));
 if(!root.children.length)root.append(opsNode('p','対応履歴はありません。'));ops('ops-history-dialog').showModal();}
ops('overview-nav')?.addEventListener('click',()=>perform(refreshOverview));
ops('ops-refresh')?.addEventListener('click',()=>perform(refreshOverview));
ops('ops-search-form')?.addEventListener('submit',event=>{event.preventDefault();perform(async()=>{
 const query=ops('ops-search').value.trim();if(query.length<2)throw Error('2文字以上で検索してください。');
 ops('ops-search-results').textContent='検索中…';renderPostResults(await rpc('operator_post_search',{p_query:query,p_limit:30}));
});});
ops('ops-case-new')?.addEventListener('click',()=>ops('ops-case-dialog').showModal());
ops('ops-case-cancel')?.addEventListener('click',()=>ops('ops-case-dialog').close());
ops('ops-case-form')?.addEventListener('submit',event=>{event.preventDefault();const formElement=event.currentTarget;perform(async()=>{
 const form=new FormData(formElement),due=form.get('due');
 await rpc('operator_case_create',{p_subject:form.get('subject'),p_contact_email:form.get('email'),p_detail:form.get('detail'),p_priority:form.get('priority'),p_due_at:due?new Date(due).toISOString():null});
 ops('ops-case-dialog').close();formElement.reset();await refreshOverview();status('問い合わせを記録しました。');
});});
ops('ops-history-close')?.addEventListener('click',()=>ops('ops-history-dialog').close());
for(const id of ['reports-nav','security-nav','content-nav','seed-refresh'])ops(id)?.addEventListener('click',clearOverview,{capture:true});

function productTable(id,headers,rows){const root=ops(id);root.replaceChildren();if(!rows?.length){root.append(opsNode('p','まだ計測データがありません。'));return;}const wrap=opsNode('div');wrap.className='product-scroll';const table=opsNode('table');table.className='product-table';const download=opsNode('button','CSV');download.type='button';download.addEventListener('click',()=>{const cell=v=>'\"'+String(v??'').replace(/^[\s\u0000-\u001f]*[=+@-]/,"'$&").replaceAll('\"','\"\"')+'\"';const csv='\uFEFF'+[headers,...rows].map(row=>row.map(cell).join(',')).join('\r\n');const url=URL.createObjectURL(new Blob([csv],{type:'text/csv;charset=utf-8'}));const link=opsNode('a');link.href=url;link.download='MEFRION-'+id+'.csv';link.click();setTimeout(()=>URL.revokeObjectURL(url),1000);});root.append(download);const head=opsNode('tr');for(const h of headers)head.append(opsNode('th',h));const thead=opsNode('thead');thead.append(head);table.append(thead);const body=opsNode('tbody');for(const values of rows){const tr=opsNode('tr');for(const value of values)tr.append(opsNode('td',value??'未取得'));body.append(tr);}table.append(body);wrap.append(table);root.append(wrap);}
async function refreshProductAnalytics(){
 const stamp=generation;
 try{
 const data=await rpc('operator_product_analytics',{p_days:Number(ops('product-days').value)});
 if(stamp!==generation||panel!=='overview')return;
 ops('product-status').textContent=data.started_at?'計測開始 '+opsDate(data.started_at)+' / 集計は日本時間':'対応アプリからの初回データ待ち。過去の利用履歴は推定しません。';
 ops('product-summary').replaceChildren(opsMetric('DAU（端末）',data.devices.dau,'今日・ゲスト含む'),opsMetric('WAU（端末）',data.devices.wau,'直近7日'),opsMetric('MAU（端末）',data.devices.mau,'直近30日'),opsMetric('現在の登録者',data.registered.total,'メール確認済み・ゲスト等を除く'));
 const daily=data.daily||[];productTable('product-daily',['日付','利用端末','登録者の利用','起動セッション','初回起動','登録確認済み人数'],daily.map(r=>[r.day,r.devices,r.members,r.sessions,r.first_opens,r.new_accounts]));
 const c=data.collection;if(c){const warning=c.events_today>=c.daily_limit||c.stored_events>=c.storage_limit;ops('product-status').append(document.createTextNode(' / 直近24時間 '+opsCount(c.events_today)+'イベント・保存 '+opsCount(c.stored_events)+'件'+(warning?'：計測上限のため一部データが欠ける可能性があります。':' / 生イベント90日保存')));}
 const chart=ops('product-hourly');chart.replaceChildren();const lookup=new Map((data.hourly||[]).map(r=>[r.hour.slice(0,13),r]));const hours=Array.from({length:48},(_,i)=>{const key=new Date(Date.now()+9*3600000-(47-i)*3600000).toISOString().slice(0,13);return lookup.get(key)||{hour:key+':00',devices:0,sessions:0};});const maximum=Math.max(1,...hours.map(r=>r.devices));for(const row of hours){const bar=opsNode('div');bar.style.height=Math.max(2,row.devices/maximum*120)+'px';bar.title=row.hour+' / '+row.devices+'端末 / '+row.sessions+'起動';bar.setAttribute('aria-label',bar.title);chart.append(bar);}if(!hours.length)chart.textContent='時間別の利用データ待ち';
 productTable('product-retention',['初回観測から','対象端末','再利用端末','継続率'],(data.retention||[]).map(r=>[r.day+'日後',r.eligible,r.returned,r.eligible?(100*r.returned/r.eligible).toFixed(1)+'%':'対象期間待ち']));
 productTable('product-funnel',['初回起動した端末','起動後に登録確認','登録後に投稿受付'],[[data.funnel.first_open,data.funnel.registered_after_open,data.funnel.posted_after_registration]]);
 productTable('product-hour-table',['時刻(JST)','アプリ利用端末','起動回数','計測イベント数','共有リンクの到着'],hours.map(r=>[r.hour,r.devices,r.sessions,r.events||0,r.share_visits||0]));
 const labels={first_open:'初回観測した起動',session:'起動セッション',active:'利用中',tab:'タブ表示',signup_start:'登録開始',signup_success:'メール登録確認',post_start:'投稿送信開始',post_success:'投稿受付成功',post_failure:'投稿受付失敗',album_open:'アルバム表示',album_save:'アルバム保存',twins_start:'そっくり検索開始',twins_success:'検索結果取得',twins_failure:'検索失敗',share_visit:'共有リンクからApp Storeへ移動',share_open:'共有先を開く',share_complete:'共有完了',image_ready:'画像準備完了',image_failure:'画像準備失敗',video_ready:'動画準備完了',video_failure:'動画準備失敗',request_success:'通信成功',request_failure:'通信失敗'};
 const events=data.events||[];productTable('product-events',['操作','区分','回数','端末数'],events.map(r=>[labels[r.name]||r.name,r.detail||'—',r.n,r.devices]));
 const rateRows=[];for(const [success,failure,label] of [['twins_success','twins_failure','そっくり検索'],['post_success','post_failure','投稿受付'],['image_ready','image_failure','画像準備'],['video_ready','video_failure','動画準備']]){const ok=events.filter(r=>r.name===success).reduce((a,r)=>a+Number(r.n),0),bad=events.filter(r=>r.name===failure).reduce((a,r)=>a+Number(r.n),0);rateRows.push([label,ok,bad,ok+bad?(100*ok/(ok+bad)).toFixed(1)+'%':'未計測']);}productTable('product-rates',['処理','成功','失敗','成功率'],rateRows);
 productTable('product-quality',['処理','区分','件数','中央値(ms)','95%(ms)'],events.filter(r=>r.p50_ms!==null).map(r=>[labels[r.name]||r.name,r.detail||'—',r.n,Math.round(r.p50_ms),Math.round(r.p95_ms)]));
 productTable('product-content',['一般投稿','一般投稿者','運営投稿'],[[data.content.user_posts,data.content.user_posters,data.content.managed_posts]]);
 productTable('product-versions',['バージョン','端末数','失敗イベント'],(data.versions||[]).map(r=>[r.app_version,r.devices,r.failures]));
 productTable('product-store',['日付','初回DL','再DL','インストール'],(data.store||[]).map(r=>[r.day,r.first_downloads,r.redownloads,r.installations]));
 try{const apple=await rpc('operator_apple_metrics',{p_days:Number(ops('product-days').value)});if(stamp!==generation||panel!=='overview')return;const states={not_configured:'Apple接続設定待ち',request_required:'Appleで継続レポートの生成設定が必要',awaiting_reports:'Appleのレポート生成待ち',ok:'自動連携中',apple_auth:'Appleの権限・キーを確認してください'};ops('product-apple-status').textContent=(states[apple.status]||'同期エラー・再試行待ち')+' / 最終確認 '+opsDate(apple.last_attempt)+' / 最終取得 '+opsDate(apple.last_success);productTable('product-apple',['日付（Apple）','初回DL','再DL','インストール（同意利用者）','DL処理日','インストール処理日'],(apple.days||[]).map(r=>[r.day,r.first_downloads,r.redownloads,r.installations,r.download_processed,r.install_processed]));}catch{ops('product-apple-status').textContent='Apple自動連携の状態を取得できません。';}
 ops('product-content').append(opsLine('アルバム利用端末',opsCount(data.album.devices)),opsLine('別の日にもアルバムを見た端末',opsCount(data.album.returning)));
 ops('product-summary').append(opsMetric('登録者DAU',data.registered.dau,'今日・アカウント単位'),opsMetric('登録者WAU',data.registered.wau,'直近7日'),opsMetric('登録者MAU',data.registered.mau,'直近30日'));
 }catch{ops('product-status').textContent='利用分析を取得できません。接続と本番への配備状況を確認してください。';}
}
ops('product-days')?.addEventListener('change',()=>perform(refreshProductAnalytics));
ops('product-store-form')?.addEventListener('submit',event=>{event.preventDefault();const f=new FormData(event.currentTarget);perform(async()=>{const number=k=>f.get(k)===''?null:Number(f.get(k));await rpc('operator_store_metric',{p_day:f.get('day'),p_first:number('first'),p_again:number('again'),p_installs:number('installs')});await refreshProductAnalytics();});});

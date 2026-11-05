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
  ops('ops-message').textContent='';status('運営ホームを更新しました。');scheduleOverview();
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

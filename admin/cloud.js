'use strict';
const $=id=>document.getElementById(id);
let config,token,factor,expires=0,busy=false,generation=0,pendingReview=null;
const status=message=>{$('status').textContent=message;};
async function request(path,body,auth=token,clearOnForbidden=true){
 const headers={apikey:config.anon_key,'Content-Type':'application/json'};if(auth)headers.Authorization='Bearer '+auth;
 const response=await fetch(config.url+path,{method:body===undefined?'GET':'POST',headers,body:body===undefined?undefined:JSON.stringify(body),cache:'no-store',credentials:'omit'});
 if((response.status===401 || (response.status===403 && clearOnForbidden)) && auth && auth===token)clear();
 if(!response.ok)throw Error(response.status===401?'ログインが切れました。再度ログインしてください。':response.status===403?'運営権限とMFA認証を確認してください。':'操作できません。入力内容と接続を確認してください。');
 return response.status===204?null:response.json();
}
const rpc=(name,body={})=>request('/rest/v1/rpc/mefrion_'+name,body);
document.getElementById('server-health-refresh')?.addEventListener('click',()=>perform(async()=>{
 const result=await rpc('operator_cloud_health');
 const output=document.getElementById('server-health-output');
 if(output)output.textContent=JSON.stringify(result,null,2);
 status('サーバーの稼働状況を取得しました。');
}));
function clear(){$('main-heading').textContent='運営管理';if(typeof clearSeed==="function")clearSeed();generation++;token=null;factor=null;expires=0;$('queue').replaceChildren();$('queue').hidden=false;$('confirmation').hidden=true;pendingReview=null;$('password').value='';$('code').value='';$('session').hidden=true;$('refresh').hidden=false;$('mfa').hidden=true;$('enroll').hidden=true;$('enroll-instructions').hidden=true;$('enroll-secret').textContent='';$('start-enroll').hidden=false;$('login').hidden=false;}
async function perform(operation){if(busy)return;busy=true;for(const button of document.querySelectorAll('button'))button.disabled=true;try{await operation();}catch(error){status(error.message);}finally{busy=false;for(const button of document.querySelectorAll('button'))button.disabled=false;}}
function node(tag,text){const result=document.createElement(tag);if(text!==undefined)result.textContent=text;return result;}
async function refresh(){
 $('main-heading').textContent='通報を確認する';
 $('seed-section').hidden=true;$('queue').hidden=false;$('queue').replaceChildren();if(!token || Date.now()/1000>=expires){clear();throw Error('ログインが切れました。再度ログインしてください。');}
 const stamp=generation;const rows=await rpc('operator_queue');if(stamp!==generation)return;
 for(const report of rows){
  const card=node('article');card.className='card';card.append(node('h2',report.comment_id?'コメントの通報':'Pet・投稿の通報'),node('p',report.reason),node('p',report.note),node('p',report.snapshot.body||report.snapshot.name||''));
  const history=node('p',`対応履歴 ${report.reviews.length}件・異議 ${report.appeals.length}件`);card.append(history);
  const assigned=report.assignment||{version:0,mine:false,assigned:false};card.append(node('p',assigned.assigned?(assigned.mine?'担当：あなた':'担当：別の担当者'):'担当：未割当'));const claim=node('button',assigned.mine?'担当を解除する':'この通報を担当する');claim.hidden=assigned.assigned&&!assigned.mine;claim.addEventListener('click',()=>perform(async()=>{await rpc('operator_claim',{p_report:report.id,p_version:assigned.version,p_claim:!assigned.mine});await refresh();}));card.append(claim);
  for(const appeal of report.appeals)card.append(node('p','異議内容：'+appeal.note));
  const select=node('select');select.setAttribute('aria-label','対応内容');
  for(const [value,label] of [['dismiss','確認終了'],[report.comment_id?'hide_comment':'hide_post',report.comment_id?'コメントを非表示':'投稿を非表示'],['suspend_account','相手の全Pet・公開活動を停止'],['restore_account','公開活動の停止を解除']]){const option=node('option',label);option.value=value;select.append(option);}
  const note=node('textarea');note.maxLength=1000;note.placeholder='内部の判断理由（必須）';note.setAttribute('aria-label','判断理由');
  const button=node('button','対応を記録');let requestKey=crypto.randomUUID();const changed=()=>{requestKey=crypto.randomUUID();};note.addEventListener('input',changed);select.addEventListener('change',changed);
  button.addEventListener('click',()=>perform(async()=>{
   if(!note.value.trim())throw Error('判断理由を入力してください。');
   pendingReview={p_report:report.id,p_decision:select.value,p_note:note.value,p_request_key:requestKey};
   $('confirm-target').textContent=(report.comment_id?'コメントの通報':'Pet・投稿の通報')+'：'+select.selectedOptions[0].textContent;
   $('confirm-reason').textContent='内部の判断理由：'+note.value;$('confirmation').hidden=false;$('queue').hidden=true;
  }));select.hidden=note.hidden=button.hidden=assigned.assigned&&!assigned.mine;card.append(select,note,button);$('queue').append(card);
 }
 status(`運営権限とMFAを確認しました。通報 ${rows.length}件。`);
}
$('login').addEventListener('submit',event=>{event.preventDefault();perform(async()=>{
 const credentials={email:$('email').value,password:$('password').value};clear();const stamp=generation;const configPath=document.querySelector('meta[name="mefrion-config"]')?.content||'/v1/development/cloud-public-config';config=await (await fetch(configPath,{cache:'no-store'})).json();
 const result=await request('/auth/v1/token?grant_type=password',credentials,null);$('password').value='';
 if(stamp!==generation)return;token=result.access_token;expires=Date.now()/1000+result.expires_in;
 const user=await request('/auth/v1/user');const verified=(user.factors||[]).filter(item=>item.factor_type==='totp' && item.status==='verified');
 if(!verified.length){$('login').hidden=true;$('enroll').hidden=false;status('本人が認証アプリを登録してください。権限は別途承認が必要です。');return;}
 factor=verified[0].id;$('login').hidden=true;$('mfa').hidden=false;status('認証アプリのコードを入力してください。');
});});
$('start-enroll').addEventListener('click',()=>perform(async()=>{
 const stamp=generation;const result=await request('/auth/v1/factors',{factor_type:'totp',friendly_name:'MEFRION operator'});if(stamp!==generation)return;
 factor=result.id;$('enroll-secret').textContent=result.totp.secret;$('enroll-instructions').hidden=false;$('start-enroll').hidden=true;$('mfa').hidden=false;status('設定キーを認証アプリへ登録し、コードを入力してください。');
}));
$('mfa').addEventListener('submit',event=>{event.preventDefault();perform(async()=>{
 const stamp=generation;const challenge=await request('/auth/v1/factors/'+factor+'/challenge',{});
 const result=await request('/auth/v1/factors/'+factor+'/verify',{challenge_id:challenge.id,code:$('code').value});$('code').value='';if(stamp!==generation)return;
 token=result.access_token;expires=Date.now()/1000+result.expires_in;$('enroll').hidden=true;$('enroll-secret').textContent='';$('mfa').hidden=true;$('session').hidden=false;
 let seedOnly=false;try{const permissions=await request('/rest/v1/rpc/mefrion_seed_permissions',{},token,false);seedOnly=(permissions.edit||permissions.approve)&&!permissions.publish;}catch(error){}
 $('refresh').hidden=seedOnly;
 if(seedOnly){await refreshSeed();status('運営権限とMFAを確認しました。担当範囲の素材・下書きを管理できます。');}else await refresh();
});});
$('confirm-review').addEventListener('click',()=>perform(async()=>{
 if(!pendingReview)return;const payload=pendingReview;const stamp=generation;await rpc('operator_review',payload);if(stamp!==generation)return;
 pendingReview=null;$('confirmation').hidden=true;$('queue').hidden=false;await refresh();status('対応を記録しました。');
}));
$('cancel-review').addEventListener('click',()=>{pendingReview=null;$('confirmation').hidden=true;$('queue').hidden=false;status('対応を取り消しました。');});
$('cancel-login').addEventListener('click',()=>{clear();status('ログインを取り消しました。');});
$('refresh').addEventListener('click',()=>perform(refresh));$('logout').addEventListener('click',()=>perform(async()=>{const previous=token;clear();if(previous)await request('/auth/v1/logout',{},previous);status('ログアウトしました。');}));
window.addEventListener('pagehide',clear);document.addEventListener('visibilitychange',()=>{if(document.hidden){$('enroll-secret').textContent='';$('queue').replaceChildren();if(typeof clearSeed==='function')clearSeed();pendingReview=null;$('confirmation').hidden=true;$('confirm-target').textContent='';$('confirm-reason').textContent='';}else if(token && !busy)perform(async()=>{const permissions=await request('/rest/v1/rpc/mefrion_seed_permissions',{},token,false);if((permissions.edit||permissions.approve)&&!permissions.publish){$('refresh').hidden=true;await refreshSeed();}else await refresh();});});

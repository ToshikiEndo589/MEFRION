'use strict';
const content=id=>document.getElementById(id);
let contentUrls=[];
function clearContent(){
 for(const url of contentUrls)URL.revokeObjectURL(url);
 contentUrls=[];
 content('content-list')?.replaceChildren();
 if(content('content-section'))content('content-section').hidden=true;
}
async function contentMedia(id){
 const response=await fetch(config.url+'/functions/v1/review-media?media='+encodeURIComponent(id),{
  headers:{apikey:config.anon_key,Authorization:'Bearer '+token},cache:'no-store',credentials:'omit',signal:AbortSignal.timeout(60000)
 });
 if(!response.ok)throw Error('メディアを読み込めませんでした。運営権限と公開前の状態を確認してください。');
 const url=URL.createObjectURL(await response.blob());contentUrls.push(url);return url;
}
async function refreshContent(){
 if(!mfaComplete||!token)throw Error('運営アカウントで二段階認証を完了してください。');
 clearContent();
 content('content-section').hidden=false;
 content('queue').hidden=true;content('seed-section').hidden=true;
 content('refresh').hidden=true;content('seed-refresh').hidden=true;
 content('main-heading').textContent='公開前の投稿';
 const stamp=generation,rows=await rpc('content_review_queue');
 if(stamp!==generation||panel!=='content')return;
 const list=content('content-list');
 if(!rows.length){list.textContent='確認待ちの投稿はありません。';content('content-message').textContent='確認待ち 0 件';return;}
 content('content-message').textContent='確認待ち '+rows.length+' 件';
 for(const row of rows){
  const card=document.createElement('article');card.className='content-card';
  const title=node('h3',row.pet_name||'うちの子'),date=node('small',new Date(row.created_at).toLocaleString('ja-JP'));
  const body=node('p',row.body||'本文なし'),mediaGrid=node('div');mediaGrid.className='content-media';
  const viewed=new Set();
  for(const media of row.media||[]){
   const item=node('div');item.className='content-media-item';
   const button=node('button',media.kind==='video'?'動画を確認':'写真を確認');button.type='button';
   button.addEventListener('click',()=>perform(async()=>{
    const url=await contentMedia(media.id),display=document.createElement(media.kind==='video'?'video':'img');
    display.src=url;
    if(media.kind==='video'){display.controls=true;display.playsInline=true;display.preload='metadata';}
    else display.alt='公開前の写真';
    item.replaceChildren(display);viewed.add(media.id);
   }));item.append(button);mediaGrid.append(item);
  }
  const hint=node('p','写真・動画 '+(row.media||[]).length+' 件を確認してください。');hint.className='content-muted';
  const note=document.createElement('textarea');note.maxLength=500;note.placeholder='判断理由（運営記録・必須）';note.setAttribute('aria-label','判断理由');
  const actions=node('div');actions.className='content-actions';
  for(const [approve,label,style] of [[true,'確認して公開','content-approve'],[false,'公開しない','content-reject']]){
   const button=node('button',label);button.type='button';button.className=style;
   button.addEventListener('click',()=>perform(async()=>{
    if(!note.value.trim())throw Error('判断理由を入力してください。');
    if(approve&&viewed.size!==(row.media||[]).length)throw Error('すべての写真・動画を確認してください。');
    const result=await rpc('content_review_decide',{p_post:row.id,p_approve:approve,p_note:note.value});
    await refreshContent();status(result.state==='approved'?'投稿を公開しました。':'投稿を非公開にしました。');
   }));actions.append(button);
  }
  card.append(title,date,body,mediaGrid,hint,note,actions);list.append(card);
 }
}
content('content-nav')?.addEventListener('click',()=>perform(async()=>{
 panel='content';if(typeof clearSecurity==='function')clearSecurity();await refreshContent();
}));
content('content-refresh')?.addEventListener('click',()=>perform(refreshContent));
for(const id of ['reports-nav','security-nav'])content(id)?.addEventListener('click',clearContent,{capture:true});

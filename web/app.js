const el = id => document.getElementById(id);
let photos = [], chosen = [], pendingPhoto = null;
const status = text => { el('status').textContent = text; };
async function api(path, body, token = 'local-owner') {
  const response = await fetch(path, {method:body?'POST':'GET', headers:{'Content-Type':'application/json',...(token?{Authorization:`Bearer ${token}`}:{})},...(body?{body:JSON.stringify(body)}:{})});
  const result = await response.json();
  if (!response.ok) throw new Error(result.error);
  return result;
}
const textNode = (tag,text) => {const n=document.createElement(tag);n.textContent=text;return n;};
function picture(asset) {const im=document.createElement('img');im.src=`/assets/${asset}.png`;im.alt='犬猫を描いた開発用イラスト';return im;}
function card(p) {const n=document.createElement('article');n.className='card';n.append(textNode('h3',p.name),picture(p.asset),textNode('p',p.body||'開発用イラスト'));return n;}
async function album() {
  const id=el('pet-list').value; chosen=[];el('album-photos').replaceChildren();
  if (!id) return;
  photos=(await api(`/v1/albums/${id}`)).photos;
  for(const p of photos){
    const n=document.createElement('article');n.className='card';n.append(picture(p.asset),textNode('p',p.captured||'日付不明'));
    const label=document.createElement('label'),check=document.createElement('input');check.type='checkbox';check.setAttribute('aria-label','比較に選択');
    check.onchange=()=>{if(check.checked && chosen.length>=2){check.checked=false;status('比較は2枚までです。');return;}chosen=check.checked?[...chosen,p.id]:chosen.filter(id=>id!==p.id);};
    label.append(check,document.createTextNode('比較に選択'));n.append(label);el('album-photos').append(n);
  }
}
async function loadPets() {
  const before=el('pet-list').value, pets=(await api('/v1/pets')).pets;
  el('pet-list').replaceChildren();
  for(const p of pets){const opt=textNode('option',`${p.name} · 家族内のみ`);opt.value=p.id;el('pet-list').append(opt);}
  if(pets.some(p=>p.id===before))el('pet-list').value=before;
  await album();
}
for(const button of document.querySelectorAll('[data-tab]'))button.onclick=()=>{for(const id of ['home','twins','album'])el(id).hidden=id!==button.dataset.tab;};
el('pet-list').onchange=()=>album().catch(e=>status(e.message));
el('pet-form').onsubmit=async e=>{e.preventDefault();try{const p=await api('/v1/pets',{name:el('pet-name').value,species:el('pet-species').value});await loadPets();el('pet-list').value=p.id;await album();status('写真0枚・非公開でPetを作成しました。');}catch(e){status(e.message);}};
el('photo-form').onsubmit=async e=>{
  e.preventDefault();if(!el('pet-list').value){status('先にPetを作成してください。選択は保持しています。');return;}
  // Retain the request identity after transport failure; changed input creates a new operation.
  const fields={asset:el('asset-list').value,captured:el('captured').value||null,allow_duplicate:el('duplicate').checked};
  const signature=JSON.stringify({pet:el('pet-list').value,...fields});
  if(!pendingPhoto || pendingPhoto.signature!==signature)pendingPhoto={signature,key:crypto.randomUUID()};
  try{const r=await api('/v1/photos',{pet_id:el('pet-list').value,items:[{...fields,request_key:pendingPhoto.key}]});status(JSON.stringify(r.results));if(r.results[0].status!=='failed')pendingPhoto=null;await album();}catch(e){status(`未保存。再試行できます：${e.message}`);}
};
el('compare').onclick=async()=>{try{
  await api('/v1/cards',{pet_id:el('pet-list').value,photo_ids:chosen});const box=document.createElement('div');box.className='comparison';box.append(textNode('h3','あの頃と今'));
  for(const id of chosen){const p=photos.find(p=>p.id===id);box.append(picture(p.asset),textNode('p',p.captured||'日付不明'));}
  box.append(textNode('strong','MEFRION'),textNode('small','家族内のみ'));el('comparison').replaceChildren(box);status('2枚比較を非公開で保存しました。');
}catch(e){status(e.message);}};
el('twins-form').onsubmit=async e=>{e.preventDefault();try{
  const r=await api('/v1/demo/twins',{species:el('twins-species').value,scenario:el('scenario').value},null);el('twins-result').replaceChildren();
  if(r.status==='results'){
    const grid=document.createElement('div');grid.className='grid';r.candidates.forEach((p,i)=>{const n=card(p);n.prepend(textNode('p',i===0?'主候補':'補助候補'));grid.append(n);});el('twins-result').append(grid);
    for(const [label,choice]of[['似てる','similar'],['ちょっと違う','different']]){const b=textNode('button',label);b.onclick=async()=>{try{await api('/v1/demo/feedback',{choice},null);status('fixture評価を記録しました。実検索品質ではありません。');for(const button of el('twins-result').querySelectorAll('button'))button.disabled=true;}catch(e){status(e.message);}};el('twins-result').append(b);}
  }else el('twins-result').append(textNode('p',{insufficient:'候補不足です。件数は水増ししません。',poor_photo:'明るく顔が大きく写る写真を選んでください。',failure:'処理失敗です。同じ入力で再試行できます。'}[r.status]));
  status(`${r.mode} / 外部費用0円`);
}catch(e){status(e.message);}};
(async()=>{try{
  const {posts}=await api('/v1/demo/feed',undefined,null);for(const p of posts)el('feed').append(card(p));
  for(let i=0;i<10;i++){const o=textNode('option',`テストイラスト ${i+1}`);o.value=`pet-${i}`;el('asset-list').append(o);}
  await loadPets();status('ローカルMock APIに接続しました。');
}catch(e){status(e.message);}})();

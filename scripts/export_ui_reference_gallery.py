"""Build a local review page from actual XCTest screenshot attachments."""
import html,json,re
from pathlib import Path
root=Path(__file__).resolve().parent.parent
source=root/'docs/evidence/ios-ui-ten-final-screens'
summary=json.loads((root/'docs/evidence/ios-ui-ten-final-summary.json').read_text())
retry=json.loads((root/'docs/evidence/ios-ui-ten-scroll-retry-summary.json').read_text())
assert summary['passedTests']==25 and summary['failedTests']==1 and summary['skippedTests']==0
assert retry['result']=='Passed' and retry['passedTests']==1 and retry['failedTests']==0 and retry['skippedTests']==0
attachments=[a for group in json.loads((source/'manifest.json').read_text()) for a in group['attachments']]
records=[]
for a in attachments:
 name=a['suggestedHumanReadableName']
 if not name.startswith('UI-Reference-'):continue
 route=name[len('UI-Reference-'):].split('_')[0]
 filename=a['exportedFileName'];assert re.fullmatch(r'[A-F0-9-]+\.png',filename)
 assert not a['isAssociatedWithFailure'] and (source/filename).is_file()
 records.append({'route':route,'file':filename,'group':route[:2]})
assert len(records)==30 and {r['group'] for r in records}=={f'{n:02}' for n in range(1,11)}
titles=['導入・認証・招待','ホーム・投稿詳細','Pet作成・編集・公開設定','成長アルバム・写真追加・記念日','家族招待・メンバー・記録','振り返り・思い出カード','投稿・確認・コメント','そっくり・切り抜き・結果・履歴','検索・通知','マイページ・設定']
buttons='<button data-filter="all" aria-pressed="true">すべて</button>'+''.join(f'<button data-filter="{n:02}" aria-pressed="false">{n:02}</button>' for n in range(1,11))
sections=[]
for group in [f'{n:02}' for n in range(1,11)]:
 cards=[]
 for r in sorted((r for r in records if r['group']==group),key=lambda r:r['route']):
  path='ios-ui-ten-final-screens/'+r['file'];label=html.escape(r['route'])
  cards.append(f'<figure><a href="{path}"><img loading="lazy" src="{path}" alt="MEFRION {label} のSimulator画面"></a><figcaption>{label}</figcaption></figure>')
 sections.append(f'<section data-group="{group}"><h2>{group} {html.escape(titles[int(group)-1])}</h2><div class="grid">'+''.join(cards)+'</div></section>')
page='''<!doctype html><html lang="ja"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>MEFRION UI 10枚の確認</title><style>
*{box-sizing:border-box}body{margin:0;background:#fffcf8;color:#292625;font-family:-apple-system,BlinkMacSystemFont,sans-serif}header,main{max-width:1250px;margin:auto;padding:24px}h1{color:#d53844}p{line-height:1.7}nav{display:flex;gap:8px;flex-wrap:wrap}button{border:1px solid #ddd;background:white;border-radius:24px;min-height:44px;padding:0 18px;cursor:pointer}button[aria-pressed=true]{background:#d53844;color:white;border-color:#d53844}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(240px,1fr));gap:18px}figure{margin:0;padding:14px;background:white;border:1px solid #eee;border-radius:18px}img{display:block;width:100%;height:440px;object-fit:contain}figcaption{padding-top:12px;text-align:center;font-size:14px}[hidden]{display:none}h2{margin-top:36px;font-size:22px}a:focus-visible,button:focus-visible{outline:3px solid #292625;outline-offset:4px}
</style><header><h1>MEFRION · UI 10枚の確認</h1><p>ホームは左が「おすすめ」で初期表示、右が「フォロー中」。下の画面は実際にSimulatorで描画して取得した30の画面・状態です。写真は所有デモ、クラウドの画面プレビューでは操作を実行しません。</p><p>実機・全機能の完成を示すものではありません。未接続の認証・通知・削除などは画面で状態を示します。画像を押すと全体を表示できます。</p><nav aria-label="参考画像の番号">'''+buttons+'</nav></header><main>'+''.join(sections)+'''</main><script>for(const button of document.querySelectorAll('button[data-filter]')){button.addEventListener('click',()=>{const filter=button.dataset.filter;for(const other of document.querySelectorAll('button[data-filter]'))other.setAttribute('aria-pressed',String(other===button));for(const section of document.querySelectorAll('section[data-group]'))section.hidden=filter!=='all'&&section.dataset.group!==filter;});}</script></html>'''
(root/'docs/evidence/UI-TEN-REVIEW.html').write_text(page)
(root/'docs/evidence/ui-ten-screen-index.json').write_text(json.dumps(sorted(records,key=lambda r:r['route']),ensure_ascii=False,indent=2))
print('Review page generated from 30 actual screenshot attachments across 10 groups.')

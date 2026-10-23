import SwiftUI

struct CloudProfileEditor:View {
    let pet:CloudPet
    @ObservedObject var client:CloudFamilyClient
    @State private var name=""
    @State private var breed=""
    @State private var intro=""
    @State private var sex="unknown"
    @State private var birthday=""
    @State private var arrival=""
    @State private var age=""
    @State private var temperament=""
    @State private var life="living"
    @State private var icon=""
    @State private var cover=""
    @State private var fields:Set<String>=[]
    @State private var saved=false
    @State private var twinPhoto=""
    @State private var twinConfirmed=false
    @State private var twinKey=UUID()
    @State private var twinMessage:String?
    private let labels=[("breed","種類"),("introduction","紹介"),("sex","性別"),("birthday","誕生日"),("arrival","お迎え日"),("age_basis","年齢の根拠"),("temperament","性格"),("life_status","状態")]
    var body:some View {
        Form {
            Section("Petのプロフィール") {
                if let image=client.images[cover] {PhotoHero(image:image,height:180)}
                TextField("なまえ",text:$name).accessibilityIdentifier("cloud-profile-name")
                BreedAutocompleteField(species:pet.species,text:$breed,identifier:"cloud-profile-breed")
                Picker("性別",selection:$sex) {Text("不明").tag("unknown");Text("男の子").tag("male");Text("女の子").tag("female")}
                TextField("誕生日（年/月/日・空欄は不明）",text:$birthday)
                TextField("お迎え日（年/月/日・空欄は不明）",text:$arrival)
                TextField("年齢の根拠・推定",text:$age)
                TextField("性格",text:$temperament)
                TextField("紹介文",text:$intro,axis:.vertical)
                Picker("Petの状態",selection:$life) {Text("通常").tag("living");Text("シニア").tag("senior");Text("亡くなった子").tag("deceased")}
                Text("シニア・亡くなった子の写真もアルバムに残せます。通知はPet単位で休止できます。").font(.caption)
            }
            Section("家族内プロフィールの写真") {
                Picker("アイコン",selection:$icon) {Text("未設定").tag("");ForEach(client.photos) {Text($0.title.isEmpty ? ($0.captured ?? "日付不明")+" "+String($0.id.prefix(6)) : $0.title).tag($0.id)}}
                Picker("カバー",selection:$cover) {Text("未設定").tag("");ForEach(client.photos) {Text($0.title.isEmpty ? ($0.captured ?? "日付不明")+" "+String($0.id.prefix(6)) : $0.title).tag($0.id)}}
                Text("ここで選んだ家族写真は公開されません。公開画像は用途同意を経た投稿から表示します。").font(.caption)
            }
            Section("公開プロフィールへ表示する項目") {
                Text("名前と犬・猫の区分は公開プロフィールを有効にした場合に表示します。家族アルバムは非公開です。").font(.caption)
                ForEach(labels,id:\.0) {field,label in Toggle(label,isOn:Binding(get:{fields.contains(field)},set:{if $0 {fields.insert(field)} else {fields.remove(field)}}))}
            }
            Section("Twins候補への参加") {
                Picker("掲載する写真",selection:$twinPhoto) {Text("選択してください").tag("");ForEach(client.photos) {Text($0.title.isEmpty ? ($0.captured ?? "日付不明") : $0.title).tag($0.id)}}
                Toggle("公開プロフィールとTwins掲載への別同意を確認した",isOn:$twinConfirmed)
                Text("他の提供者の写真は、その方のTwins用途同意が必要です。ご自身の写真は、この操作でTwins用途同意を記録します。SNS・外部共有の同意は追加しません。").font(.caption)
                Button("この写真でTwinsに参加") {Task {await client.perform {if client.photos.first(where:{$0.id==twinPhoto})?.mine==true {try await client.consent(photo:twinPhoto,purpose:"twins",allowed:true)};try await client.setPublicProfile(pet:pet.id,enabled:true,explicit:true);let result=try await client.enrollTwins(pet:pet.id,photo:twinPhoto,key:twinKey);twinMessage=result.state=="pending" ? "参加を受け付けました。派生処理後に候補になります。" : "参加状態を確認しました。"}}}.disabled(!twinConfirmed || twinPhoto.isEmpty || client.busy)
                if let twinMessage {Text(twinMessage).font(.caption)}
                Button("このPetのTwins掲載を取り消す",role:.destructive) {twinConfirmed=false;Task {await client.perform {try await client.withdrawTwins(pet:pet.id)}}}.disabled(client.busy)
            }
            Button("プロフィールを保存") {Task {await client.perform {
                var details=["sex":sex,"age_basis":age,"temperament":temperament,"life_status":life]
                if !birthday.isEmpty {details["birthday"]=birthday};if !arrival.isEmpty {details["arrival"]=arrival};if !icon.isEmpty {details["icon_photo"]=icon};if !cover.isEmpty {details["cover_photo"]=cover}
                let selectedBreed=PetBreedCatalog.canonical(breed,species:pet.species) ?? breed.trimmingCharacters(in:.whitespacesAndNewlines)
                try await client.updatePet(pet,name:name,breed:selectedBreed,introduction:intro,details:details,publicFields:fields.sorted());saved=true
            }}}.disabled(client.busy || name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty).accessibilityIdentifier("cloud-profile-save")
            if saved {Text("保存しました").accessibilityIdentifier("cloud-profile-saved")}
            if let error=client.error {Text(error).foregroundStyle(.red)}
        }.scrollContentBackground(.hidden).background(Theme.background).navigationTitle("プロフィールを編集").protectWhenInactive()
        .onChange(of:twinPhoto) {_,_ in twinKey=UUID();twinConfirmed=false}
        .task {
            name=pet.name;breed=pet.breed;intro=pet.introduction
            let d=pet.details ?? [:];sex=d["sex"] ?? "unknown";birthday=d["birthday"] ?? "";arrival=d["arrival"] ?? "";age=d["age_basis"] ?? "";temperament=d["temperament"] ?? "";life=d["life_status"] ?? "living";icon=d["icon_photo"] ?? "";cover=d["cover_photo"] ?? "";fields=Set(pet.public_fields ?? ["breed","introduction"])
            await client.perform {try await client.loadAlbum(pet:pet.id)}
        }
    }
}

enum PetBreedCatalog {
    private static let dogs="柴犬|秋田犬|北海道犬|甲斐犬|紀州犬|四国犬|日本スピッツ|トイ・プードル|ミニチュア・プードル|スタンダード・プードル|チワワ|ポメラニアン|ミニチュア・ダックスフンド|カニーンヘン・ダックスフンド|ダックスフンド|ミニチュア・シュナウザー|マルチーズ|フレンチ・ブルドッグ|ブルドッグ|ヨークシャー・テリア|ビション・フリーゼ|シー・ズー|ゴールデン・レトリーバー|ラブラドール・レトリーバー|パグ|ウェルシュ・コーギー・ペンブローク|ボーダー・コリー|ペキニーズ|ジャック・ラッセル・テリア|パピヨン|キャバリア・キング・チャールズ・スパニエル|ビーグル|シベリアン・ハスキー|サモエド|シェットランド・シープドッグ|コーイケルホンディエ|イタリアン・グレーハウンド|ボストン・テリア|ミニチュア・ピンシャー|ドーベルマン|ジャーマン・シェパード・ドッグ|バーニーズ・マウンテン・ドッグ|ボクサー|ロットワイラー|ダルメシアン|グレート・ピレニーズ|セント・バーナード|アメリカン・コッカー・スパニエル|イングリッシュ・コッカー・スパニエル|ミックス犬".components(separatedBy:"|")
    private static let cats="アビシニアン|アメリカン・カール|アメリカン・ショートヘア|アメリカン・ボブテイル|エキゾチック・ショートヘア|エジプシャン・マウ|オシキャット|オリエンタル・ショートヘア|コーニッシュ・レックス|サイベリアン|シャム|シャルトリュー|シンガプーラ|スコティッシュ・フォールド|スノーシュー|スフィンクス|セルカーク・レックス|ソマリ|ターキッシュ・アンゴラ|デボン・レックス|トンキニーズ|ノルウェージャン・フォレスト・キャット|バーマン|バーミーズ|バリニーズ|ヒマラヤン|ブリティッシュ・ショートヘア|ブリティッシュ・ロングヘア|ベンガル|ペルシャ|ボンベイ|マンチカン|ミヌエット|メイン・クーン|ラグドール|ラガマフィン|ロシアン・ブルー|日本猫|ミックス猫".components(separatedBy:"|")
    private static let aliases:[String:String]=[
        "しば":"柴犬","柴":"柴犬","といぷー":"トイ・プードル","トイプー":"トイ・プードル",
        "ミニチュアダックス":"ミニチュア・ダックスフンド","コーギー":"ウェルシュ・コーギー・ペンブローク",
        "ゴールデン":"ゴールデン・レトリーバー","ラブラドール":"ラブラドール・レトリーバー",
        "スコティッシュ":"スコティッシュ・フォールド","アメショ":"アメリカン・ショートヘア",
        "ノルウェージャン":"ノルウェージャン・フォレスト・キャット","ブリショ":"ブリティッシュ・ショートヘア",
        "メイクーン":"メイン・クーン","雑種":"ミックス犬","キジトラ":"日本猫"
    ]
    static func names(for species:String)->[String] {species=="cat" ? cats : dogs}
    private static func key(_ value:String)->String {
        let katakana=value.applyingTransform(.hiraganaToKatakana,reverse:false) ?? value
        return katakana.lowercased().filter{!$0.isWhitespace && !"・ー-・･".contains($0)}
    }
    static func canonical(_ value:String,species:String)->String? {
        let query=key(value)
        guard !query.isEmpty else {return nil}
        if query==key("ミックス") || query==key("雑種") {return species=="cat" ? "ミックス猫" : "ミックス犬"}
        let mapped=aliases.first{$0.key == value || key($0.key)==query}?.value
        return names(for:species).first{key($0)==key(mapped ?? value)}
    }
    static func suggestions(for value:String,species:String)->[String] {
        let names=names(for:species),query=key(value)
        guard !query.isEmpty else {return Array(names.prefix(6))}
        if query==key("ミックス") || query==key("雑種") {return [species=="cat" ? "ミックス猫" : "ミックス犬"]}
        let aliasTargets=aliases.filter{key($0.key).contains(query)}.map(\.value)
        let prefixMatches=names.filter{key($0).hasPrefix(query) || aliasTargets.contains($0)}
        let otherMatches=names.filter{key($0).contains(query) && !prefixMatches.contains($0)}
        return Array((prefixMatches+otherMatches).prefix(6))
    }
}

struct BreedAutocompleteField:View {
    let species:String
    @Binding var text:String
    let identifier:String
    @FocusState private var focused:Bool
    @State private var showingSuggestions=false
    var body:some View {
        VStack(alignment:.leading,spacing:7) {
            TextField(species=="cat" ? "猫種" : "犬種",text:$text)
                .focused($focused).accessibilityIdentifier(identifier)
                .onSubmit {normalize();showingSuggestions=false;focused=false}
                .onChange(of:focused) {_,isFocused in
                    if isFocused {showingSuggestions=true}
                    else {
                        Task { @MainActor in
                            try? await Task.sleep(for:.seconds(1))
                            if !focused {normalize();showingSuggestions=false}
                        }
                    }
                }
            if showingSuggestions {
                let matches=PetBreedCatalog.suggestions(for:text,species:species)
                if !matches.isEmpty {
                    ForEach(matches,id:\.self) {name in
                        Button {text=name;showingSuggestions=false;focused=false} label: {
                            HStack {Image(systemName:"pawprint.fill").font(.caption);Text(name);Spacer();Image(systemName:"checkmark.circle").font(.caption)}
                                .foregroundStyle(Theme.actionText).frame(minHeight:38)
                        }.buttonStyle(.borderless).accessibilityIdentifier("breed-suggestion-"+name)
                    }
                } else {
                    Text("候補にない場合は、そのまま入力できます ♡")
                        .font(.caption).foregroundStyle(Theme.secondaryText)
                }
            }
        }
    }
    private func normalize() {if let canonical=PetBreedCatalog.canonical(text,species:species) {text=canonical}}
}

struct CloudPhotoEditor:View {
    let photo:CloudPhoto;let pet:String
    @ObservedObject var client:CloudFamilyClient
    @State private var captured=""
    @State private var title=""
    @State private var kind=""
    @State private var note=""
    @State private var saved=false
    var body:some View {
        Form {
            if let image=client.images[photo.id] {PhotoHero(image:image,height:220)}
            TextField("撮影日・空欄は不明",text:$captured)
            TextField("タイトル",text:$title)
            Picker("節目",selection:$kind) {Text("なし").tag("");ForEach(CloudEventsView.kinds,id:\.0) {Text($0.1).tag($0.0)}}
            TextField("メモ（200字まで）",text:$note,axis:.vertical)
            Button("写真の情報を保存") {Task {await client.perform {try await client.editPhoto(photo,pet:pet,captured:captured.isEmpty ? nil : captured,title:title,kind:kind.isEmpty ? nil : kind,note:note);saved=true}}}
            if saved {Text("保存しました")};if let error=client.error {Text(error).foregroundStyle(.red)}
        }.navigationTitle("写真・節目を編集").protectWhenInactive().task {captured=photo.captured ?? "";title=photo.title;kind=photo.event_kind ?? "";note=photo.note ?? ""}
    }
}

struct CloudEventsView:View {
    static let kinds=[("birthday","誕生日"),("anniversary","うちの子記念日"),("arrival","お迎えした日"),("hospital","通院"),("other","その他")]
    let pet:CloudPet
    @ObservedObject var client:CloudFamilyClient
    @State private var events:[CloudEvent]=[]
    @State private var captured=""
    @State private var title=""
    @State private var kind="birthday"
    @State private var note=""
    @State private var key=UUID()
    @State private var frequency="off"
    @State private var milestones=false
    @State private var pause=false
    @State private var pausedUntil=Date().addingTimeInterval(86400*7)
    @State private var deleting:String?
    @State private var editing:CloudEvent?
    var body:some View {
        Form {
            Section("節目を残す") {
                Picker("種類",selection:$kind) {ForEach(Self.kinds,id:\.0) {Text($0.1).tag($0.0)}}
                TextField("日付・空欄は不明",text:$captured)
                TextField("タイトル（30字まで）",text:$title).accessibilityIdentifier("cloud-event-title")
                TextField("メモ（200字まで）",text:$note,axis:.vertical)
                Button("節目を保存") {let requestKey=key;Task {await client.perform {try await client.saveEvent(pet:pet.id,key:requestKey,captured:captured.isEmpty ? nil : captured,title:title,kind:kind,note:note);events=try await client.events(pet:pet.id);title="";note="";key=UUID()}}}.disabled(client.busy || title.isEmpty).accessibilityIdentifier("cloud-event-save")
            }
            Section("家族だけの節目") {ForEach(events) {event in VStack(alignment:.leading) {Text(event.title).font(.headline);Text(event.captured ?? "日付不明");Text(event.note);if event.mine {Button("この節目を編集") {editing=event};Button("この節目を削除",role:.destructive) {deleting=event.id}}}}}
            Section("このPetの通知") {
                Picker("家族の新着",selection:$frequency) {Text("オフ").tag("off");Text("すぐに").tag("immediate");Text("まとめて").tag("batched")}
                Toggle("節目のお知らせを希望する",isOn:$milestones)
                Toggle("通知を休止する",isOn:$pause)
                if pause {DatePicker("休止終了",selection:$pausedUntil,in:Date()...Date().addingTimeInterval(86400*365),displayedComponents:.date)}
                Button("通知設定を保存") {Task {await client.perform {try await client.savePetNotifications(pet:pet.id,frequency:frequency,milestones:milestones,paused:pause ? ISO8601DateFormatter().string(from:pausedUntil) : nil)}}}
                Text("通知をオフにしてもアルバムを利用できます。Push配信の接続確認は別途必要です。").font(.caption)
            }
            if let error=client.error {Text(error).foregroundStyle(.red)}
        }.navigationTitle("節目・通知休止").protectWhenInactive()
        .task {await client.performRefresh {events=try await client.events(pet:pet.id);let settings=try await client.petNotifications(pet:pet.id);frequency=settings.frequency;milestones=settings.milestones;pause=settings.paused_until != nil;if let date=settings.paused_until.flatMap({ISO8601DateFormatter().date(from:$0)}) {pausedUntil=date}}}
        .onChange(of:captured) {_,_ in key=UUID()}.onChange(of:title) {_,_ in key=UUID()}.onChange(of:kind) {_,_ in key=UUID()}.onChange(of:note) {_,_ in key=UUID()}
        .sheet(item:$editing,onDismiss:{Task {await client.perform {events=try await client.events(pet:pet.id)}}}) {event in NavigationStack {CloudMilestoneEditor(event:event,client:client)}}
        .confirmationDialog("この節目を削除しますか？",isPresented:Binding(get:{deleting != nil},set:{if !$0 {deleting=nil}})) {Button("削除",role:.destructive) {if let id=deleting {Task {await client.perform {try await client.deleteEvent(id);events=try await client.events(pet:pet.id)}}};deleting=nil}}
    }
}

struct CloudMilestoneEditor:View {
    let event:CloudEvent
    @ObservedObject var client:CloudFamilyClient
    @Environment(\.dismiss) private var dismiss
    @State private var title=""
    @State private var note=""
    @State private var captured=""
    @State private var kind="other"
    var body:some View {Form {TextField("タイトル",text:$title);TextField("日付・空欄は不明",text:$captured);Picker("種類",selection:$kind) {ForEach(CloudEventsView.kinds,id:\.0) {Text($0.1).tag($0.0)}};TextField("メモ",text:$note,axis:.vertical);Button("変更を保存") {Task {await client.perform {try await client.editEvent(event.id,captured:captured.isEmpty ? nil : captured,title:title,kind:kind,note:note);dismiss()}}}.disabled(client.busy || title.isEmpty || title.count>30 || note.count>200);if let error=client.error {Text(error).foregroundStyle(.red)}}.navigationTitle("節目を編集").toolbar {ToolbarItem(placement:.cancellationAction) {Button("キャンセル") {dismiss()}}}.protectWhenInactive().task {title=event.title;note=event.note;captured=event.captured ?? "";kind=event.kind}}
}

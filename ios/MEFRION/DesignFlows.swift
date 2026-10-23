import SwiftUI
import AVFoundation
import AVKit
import CoreTransferable
import UniformTypeIdentifiers
import CoreImage.CIFilterBuiltins
import PhotosUI

struct PhotoHero:View {
    var image:UIImage?
    var asset:String?=nil
    var height:CGFloat=210
    var body:some View {
        Group {
            if let image {Image(uiImage:image).resizable().scaledToFill()}
            else if let asset {Image(asset).resizable().scaledToFill()}
            else {ZStack {Theme.accent.opacity(0.07);Image(systemName:"pawprint.fill").font(.system(size:56)).foregroundStyle(Theme.accent.opacity(0.35))}}
        }.frame(height:height).clipped().clipShape(RoundedRectangle(cornerRadius:16))
    }
}

struct WelcomeFlowView:View {
    @ObservedObject private var cloud=CloudFamilyClient.shared
    let onStart:()->Void
    @State private var step=0
    init(initialStep:Int=0,onStart:@escaping ()->Void) {self.onStart=onStart;_step=State(initialValue:initialStep)}
    var body:some View {
        NavigationStack {
            ScrollView {VStack(spacing:24) {
                if step==0 {
                    PhotoHero(asset:"pet-0",height:340).overlay(alignment:.topLeading) {
                        Text("きみの毎日を、\n大切な思い出に。").font(.title2.bold()).padding(20)
                    }
                    BrandWordmark().scaleEffect(1.25).padding(.vertical,12)
                    Text("かわいい犬猫を見つけたり、\nうちの子の毎日を残したり。").multilineTextAlignment(.center).font(.subheadline)
                    Button("はじめる") {step=1}.buttonStyle(CoralButtonStyle()).accessibilityIdentifier("welcome-start")
                    HStack {Circle().fill(Theme.accent);Circle().fill(Theme.accent.opacity(0.15));Circle().fill(Theme.accent.opacity(0.15))}.frame(width:45,height:7)
                } else {
                    BrandWordmark().padding(.top,20)
                    HStack(spacing:8) {PhotoHero(asset:"pet-2",height:180);PhotoHero(asset:"pet-1",height:180)}
                    Text("ようこそ、MEFRIONへ").font(.title2.bold())
                    Text("見るだけでも大歓迎。\n犬猫の登録はあとからできます。").multilineTextAlignment(.center).font(.subheadline).foregroundStyle(.secondary)
                    VStack(spacing:12) {
                        NavigationLink {EmailAccountView(client:cloud,initialMode:"signup")} label: {Label("メールで新規登録",systemImage:"envelope").frame(maxWidth:.infinity).frame(minHeight:44)}.buttonStyle(CoralButtonStyle()).accessibilityIdentifier("welcome-email-signup")
                        NavigationLink {EmailAccountView(client:cloud)} label: {Text("メールでログイン").frame(maxWidth:.infinity).frame(minHeight:44).background(.white).clipShape(Capsule())}.accessibilityIdentifier("welcome-email")
                        Button("ゲストで始める",action:onStart).buttonStyle(CoralButtonStyle()).accessibilityIdentifier("welcome-guest")
                        Text("ゲストの記録は端末内に非公開で保存します。家族共有にはログインが必要です。").font(.caption).foregroundStyle(.secondary)
                        NavigationLink("利用規約・プライバシーについて") {PrivacyInformationView()}.font(.caption)
                    }
                }
            }.padding(24)}.background(Theme.background).foregroundStyle(Theme.text).navigationBarTitleDisplayMode(.inline)
                .toolbar {if step==1 {ToolbarItem(placement:.topBarLeading) {Button("戻る") {step=0}}}}
        }.onChange(of:cloud.busy) {_,busy in if !busy && cloud.authenticated {onStart()}}
    }
}

struct PublicSearchView:View {
    @StateObject private var client=SocialClient()
    @Environment(\.dismiss) private var dismiss
    @State private var query=""
    @State private var category="all"
    @State private var searching=false
    private var results:[FeedPost] {client.posts.filter {(category=="all" || $0.species==category) && (query.isEmpty || $0.name.localizedStandardContains(query) || $0.body.localizedStandardContains(query))}}
    var body:some View {
        ScrollView {VStack(alignment:.leading,spacing:20) {
            HStack {Image(systemName:"magnifyingglass");TextField("ペットの名前・キーワード",text:$query).submitLabel(.search).onSubmit {searching=true}.accessibilityIdentifier("public-search-input")}
                .padding(14).background(Theme.accent.opacity(0.06)).clipShape(Capsule())
            HStack(spacing:10) {categoryButton("すべて","all");categoryButton("犬","dog");categoryButton("猫","cat")}
            if !searching && query.isEmpty {
                Text("ペットを探す").font(.headline)
                HStack {Button("犬の投稿") {category="dog";searching=true};Button("猫の投稿") {category="cat";searching=true}}.buttonStyle(.bordered)
                Text("おすすめのペット").font(.headline)
            } else {Text(query.isEmpty ? "検索結果" : "「\(query)」の検索結果").font(.headline)}
            if client.loading {ProgressView()}
            if let error=client.error {Text(error).font(.footnote).foregroundStyle(.red)}
            LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:12) {
                ForEach(results) {post in VStack(alignment:.leading,spacing:5) {
                    DiscoveryTile(accessibilityPrefix:"search-open-",post:post,client:client)
                    NavigationLink {PublicPetView(post:post,client:client)} label: {HStack {Image(post.asset).resizable().scaledToFill().frame(width:28,height:28).clipShape(Circle());VStack(alignment:.leading) {Text(post.name).font(.caption.bold());Text(post.species=="dog" ? "犬" : "猫").font(.caption2).foregroundStyle(.secondary)}}}
                }}
            }
            if results.isEmpty && !client.loading && client.error==nil {ContentUnavailableView("見つかりませんでした",systemImage:"magnifyingglass",description:Text("名前やキーワードを変えてみてください。"))}
            Text("公開Petの投稿のみを対象にします。家族アルバムと人間の私的プロフィールは検索しません。").font(.caption).foregroundStyle(.secondary)
        }.padding(16)}.background(Theme.background).navigationTitle("検索").navigationBarTitleDisplayMode(.inline)
            .toolbar {ToolbarItem(placement:.cancellationAction) {Button("閉じる") {dismiss()}}}.task {await client.load()}
    }
    private func categoryButton(_ title:String,_ value:String)->some View {
        Button {category=value} label: {Text(title).font(.caption.bold()).padding(.horizontal,18).frame(minHeight:36).background(category==value ? Theme.accent.opacity(0.15) : .white).clipShape(Capsule())}
    }
}

struct NotificationHubView:View {
    @ObservedObject private var cloud=CloudFamilyClient.shared
    @Environment(\.dismiss) private var dismiss
    @State private var filter="すべて"
    var body:some View {
        Group {
            if cloud.authenticated {CloudSocialNotificationsView(client:cloud)}
            else {ScrollView {VStack(alignment:.leading,spacing:24) {
                ScrollView(.horizontal,showsIndicators:false) {HStack {ForEach(["すべて","いいね","コメント","フォロー","Twins"],id:\.self) {name in Button {filter=name} label: {Text(name).font(.caption).padding(.horizontal,14).frame(minHeight:34).background(filter==name ? Theme.accent.opacity(0.15) : .white).clipShape(Capsule())}}}}
                ContentUnavailableView("新しいお知らせはありません",systemImage:"bell",description:Text("クラウドにログインすると、実際のいいねやコメントを確認できます。"))
                NavigationLink {CloudFamilyView()} label: {Label("ログイン",systemImage:"person").frame(maxWidth:.infinity)}.buttonStyle(CoralButtonStyle())
                Text("通知設定").font(.headline)
                ForEach([("いいね","heart"),("コメント","bubble.right"),("フォロー","person"),("Twins関連","pawprint")],id:\.0) {title,icon in HStack {Label(title,systemImage:icon);Spacer();Text("ログイン後に設定").font(.caption).foregroundStyle(.secondary)}.padding(14).background(.white).clipShape(RoundedRectangle(cornerRadius:12))}
                Text("プッシュ通知は接続準備中です。").font(.caption).foregroundStyle(.secondary)
            }.padding(16)}.background(Theme.background)}
        }.navigationTitle("通知").navigationBarTitleDisplayMode(.inline).toolbar {ToolbarItem(placement:.cancellationAction) {Button("閉じる") {dismiss()}}}
    }
}

struct LocalPetProfileView:View {
    let petID:UUID
    @EnvironmentObject var store:PrototypeStore
    @State private var editing=false
    private var pet:PetRecord? {store.pets.first{$0.id==petID}}
    var body:some View {
        ScrollView {if let pet {VStack(alignment:.leading,spacing:18) {
            PhotoHero(image:store.album(petID).first(where:{$0.id==pet.coverPhotoID})?.image ?? store.album(petID).first?.image)
            HStack {
                petIcon(pet).font(.system(size:32)).foregroundStyle(Theme.accent).frame(width:76,height:76).background(Theme.background).clipShape(Circle()).overlay(Circle().stroke(.white,lineWidth:4)).padding(.top,-45)
                Spacer();Button("プロフィールを編集") {editing=true}.buttonStyle(CoralButtonStyle()).accessibilityIdentifier("edit-pet-profile")
            }
            Text(pet.name).font(.title2.bold());Text(pet.breed.isEmpty ? pet.species.title : pet.breed).font(.caption).foregroundStyle(.secondary)
            if !pet.introduction.isEmpty {Text(pet.introduction).font(.subheadline)}
            Label("家族内のみ・非公開",systemImage:"lock").font(.caption).foregroundStyle(.secondary)
            NavigationLink {AlbumView(petID:petID)} label: {Label("成長アルバム · \(store.album(petID).count)枚",systemImage:"book.closed").frame(maxWidth:.infinity,alignment:.leading).padding(16).background(.white).clipShape(RoundedRectangle(cornerRadius:14))}
            NavigationLink("公開設定・Twinsについて") {PrivacyInformationView()}
            LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible()),GridItem(.flexible())],spacing:6) {ForEach(store.album(petID)) {photo in NavigationLink {PhotoEditor(photoID:photo.id)} label: {Image(uiImage:photo.image).resizable().scaledToFill().frame(height:105).clipped().clipShape(RoundedRectangle(cornerRadius:8))}}}
        }.padding(16)}}.background(Theme.background).navigationTitle(pet?.name ?? "うちの子").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented:$editing) {NavigationStack {LocalPetEditor(petID:petID)}}
    }
    @ViewBuilder private func petIcon(_ pet:PetRecord)->some View {
        if let image=store.album(petID).first(where:{$0.id==pet.iconPhotoID})?.image {Image(uiImage:image).resizable().scaledToFill().frame(width:76,height:76).clipShape(Circle())}
        else {Image(systemName:"pawprint.fill")}
    }

}

struct LocalPetEditor:View {
    let petID:UUID
    @EnvironmentObject var store:PrototypeStore
    @Environment(\.dismiss) private var dismiss
    @State private var name=""
    @State private var breed=""
    @State private var introduction=""
    @State private var sex=""
    @State private var birthday=""
    @State private var coverPhotoID:UUID?
    @State private var iconPhotoID:UUID?
    private enum PicturePurpose:String,Identifiable {case cover,icon;var id:String {rawValue}}
    @State private var picturePurpose:PicturePurpose?
    @State private var error:String?
    var body:some View {
        Form {
            Section {
                PhotoHero(image:store.album(petID).first(where:{$0.id==coverPhotoID})?.image ?? store.album(petID).first?.image,height:160)
                HStack {Button("カバー写真を選ぶ") {picturePurpose = .cover};Spacer();Button("アイコンを選ぶ") {picturePurpose = .icon}}.font(.caption).buttonStyle(.borderless)
                Text("うちの子のプロフィール").font(.headline)
            }
            TextField("名前",text:$name).accessibilityIdentifier("edit-pet-name")
            BreedAutocompleteField(species:store.pets.first(where:{$0.id==petID})?.species == .cat ? "cat" : "dog",text:$breed,identifier:"edit-pet-breed")
            Picker("性別",selection:$sex) {Text("未設定").tag("");Text("男の子").tag("male");Text("女の子").tag("female")}.pickerStyle(.segmented)
            TextField("誕生日（分かる範囲・任意）",text:$birthday).keyboardType(.numbersAndPunctuation)
            TextField("紹介文",text:$introduction,axis:.vertical)
            Section {Label("この編集で写真を公開しません",systemImage:"lock").font(.caption)}
            if let error {Text(error).foregroundStyle(.red)}
        }.scrollContentBackground(.hidden).background(Theme.background).navigationTitle("プロフィールを編集").navigationBarTitleDisplayMode(.inline)
            .toolbar {ToolbarItem(placement:.cancellationAction) {Button("キャンセル") {dismiss()}};ToolbarItem(placement:.confirmationAction) {Button("保存") {do {let species=store.pets.first(where:{$0.id==petID})?.species == .cat ? "cat" : "dog";let selectedBreed=PetBreedCatalog.canonical(breed,species:species) ?? breed.trimmingCharacters(in:.whitespacesAndNewlines);try store.updatePet(id:petID,name:name,breed:selectedBreed,introduction:introduction,sex:sex.isEmpty ? nil : sex,birthday:birthday.isEmpty ? nil : birthday,pictures:(coverPhotoID,iconPhotoID));dismiss()} catch {self.error=error.localizedDescription}}.accessibilityIdentifier("save-pet-edit")}}
            .onAppear {if let pet=store.pets.first(where:{$0.id==petID}) {name=pet.name;breed=pet.breed;introduction=pet.introduction;sex=pet.sex ?? "";birthday=pet.birthday ?? "";coverPhotoID=pet.coverPhotoID;iconPhotoID=pet.iconPhotoID}}
            .sheet(item:$picturePurpose) {purpose in NavigationStack {PrivateProfilePhotoChoice(petID:petID) {id in if purpose == .cover {coverPhotoID=id} else {iconPhotoID=id};picturePurpose=nil}}}.protectWhenInactive()
    }
}

struct MemoryTimelineView:View {
    let petID:UUID
    @EnvironmentObject var store:PrototypeStore
    @State private var month=Calendar.current.component(.month,from:Date())
    @State private var day=Calendar.current.component(.day,from:Date())
    private var matching:[PhotoRecord] {
        store.album(petID).filter {photo in guard let captured=photo.captured,captured.count==10 else{return false};let parts=captured.split(separator:"-");return Int(parts[1])==month && Int(parts[2])==day}.sorted {($0.captured ?? "")<($1.captured ?? "")}
    }
    var body:some View {
        ScrollView {VStack(alignment:.leading,spacing:18) {
            HStack {Image(systemName:"calendar").foregroundStyle(Theme.accent);Picker("月",selection:$month) {ForEach(1...12,id:\.self) {Text("\($0)月").tag($0)}};Picker("日",selection:$day) {ForEach(1...31,id:\.self) {Text("\($0)日").tag($0)}}}.padding(8).background(.white).clipShape(Capsule())
            Text("同じ日の思い出").font(.headline)
            ForEach(matching) {photo in VStack(alignment:.leading,spacing:8) {Text(photo.captured ?? "日付不明").font(.caption.bold());Image(uiImage:photo.image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius:12))}.padding(10).background(.white).clipShape(RoundedRectangle(cornerRadius:16))}
            if matching.isEmpty {ContentUnavailableView("この日の写真はありません",systemImage:"calendar",description:Text("撮影日の分かる写真から、同じ月日の思い出を振り返れます。"))}
            NavigationLink {AlbumView(petID:petID)} label: {Label("2枚を選んで思い出カードを作る",systemImage:"photo.on.rectangle").frame(maxWidth:.infinity)}.buttonStyle(CoralButtonStyle())
            Text("日付不明や年・月のみの写真は同日の記録として扱いません。").font(.caption).foregroundStyle(.secondary)
        }.padding(16)}.background(Theme.background).navigationTitle("あの頃と今").navigationBarTitleDisplayMode(.inline)
    }
}

struct PrivacyInformationView:View {
    private let publicInfoBase = "https://mefrion-support.toshiki1108.chatgpt.site"
    var body:some View {
        List {
            Section("公開ページ") {
                Link("プライバシーポリシー",destination:URL(string:"\(publicInfoBase)/privacy")!)
                Link("利用規約",destination:URL(string:"\(publicInfoBase)/terms")!)
                Link("サポート・お問い合わせ",destination:URL(string:publicInfoBase)!)
            }
            Section("利用条件") {
                NavigationLink("画像比較モデルのライセンス") {LegalDraftView(title:"モデルのライセンス",text:(Bundle.main.url(forResource:"ModelNotices",withExtension:"txt").flatMap{try? String(contentsOf:$0,encoding:.utf8)}) ?? "ライセンス情報を読み込めません。")}
                Text("初期版は18歳以上・無料・広告なしの方針です。現在は提供準備中です。最新の案内は公開ページをご確認ください。")
            }
            Section("写真の公開") {Label("家族内写真は初期非公開",systemImage:"lock");Text("アルバム保存と公開同意は別です。提供者の用途同意とオーナーの明示操作を確認します。SNS、Twins参加、外部共有は用途ごとに選択します。")}
            Section("Twins") {Text("参考写真検索は、検索ボタンを押すと写真の特徴数値をSupabaseへ送りサーバーで比較します。写真そのものは送信せず、自動公開・候補登録もしません。未保存入力は10分または画面終了等で破棄します。実写真の類似品質は評価待ちです。")}
            Section("同意と削除") {Text("用途同意の撤回・元写真削除・退会で関連公開を終了します。アプリ内退会はログイン中のアカウントから削除を確認して申し込めます。物理削除・バックアップの期限運用は常時サーバーの配備後に検証します。端末や第三者が保存したコピーは回収できません。")}
            Section("運営と問い合わせ") {Text("運営名：MEFRION。運営はサービス提供者本人が担当します。現在の案を発効済みの規約、既存利用者の同意済み文書として扱いません。");Link("nextedovation@gmail.com",destination:URL(string:"mailto:nextedovation@gmail.com")!).accessibilityLabel("MEFRIONへの問い合わせメールを作成").accessibilityIdentifier("operator-contact");Text("パスワードや認証コードは送らないでください。").font(.caption).foregroundStyle(.secondary)}
        }.scrollContentBackground(.hidden).background(Theme.background).navigationTitle("プライバシーと同意").navigationBarTitleDisplayMode(.inline)
    }
}

private struct LegalDraftView:View {
    let title:String
    let text:String
    var body:some View {
        ScrollView {Text(text).font(.body).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading).padding(16)}
            .background(Theme.background).navigationTitle(title).navigationBarTitleDisplayMode(.inline)
    }
}

private enum MEFRIONLegalDraft {
    static let terms = "現在は提供準備中です。この文書を正式発効済み、既存利用者の同意済みとは扱いません。取扱主体の正式情報・URLを補完し、提供機能と運用を検証してから発効します。\n\n1. MEFRIONは18歳以上を対象とするiPhone向けペット記録・家族共有・公開交流サービスです。初期版は無料です。有料機能を導入する場合は事前に料金と条件を案内します。\n2. 登録情報は正確に入力し、本人が利用できる認証手段を使用してください。他人へのなりすましや認証手段の共有は禁止します。サービスの規約への同意だけで写真は公開されません。\n3. 家族内アルバムは参加権限のある人だけが閲覧します。招待の共有先は慎重に選んでください。家族の閲覧権限とSNSのブロックは別です。端末へ保存されたコピーや画面撮影を当サービスから回収することはできません。\n4. 写真・文章の権利は投稿者または元の権利者に残ります。サービス提供に必要な保存、縮小、表示、同意した範囲の配信だけを許可いただきます。無関係な広告利用や学習用途へ自動転用しません。第三者が写る写真や第三者の作品は必要な許可を取得してください。\n5. 公開投稿、Twinsの候補参加、外部共有はそれぞれ明示同意を必要とします。家族の写真は提供者の用途同意とオーナーの操作を確認します。撤回または元写真削除時は関連する公開経路を終了します。\n6. Twinsは写真の見た目から候補を探す機能です。血縁、同一個体、健康状態を判定する機能ではありません。現在の実写真品質は評価待ちであり、根拠のない類似パーセントは表示しません。\n7. 権利侵害、個人情報の無断公開、嫌がらせ、差別、脅迫、虐待の助長、性的な不適切内容、スパム、不正アクセスは禁止します。通報とブロックを用意し、違反や重大な安全上の問題に対して非表示・利用停止等を行います。対象者はアプリの処分通知から異議を申し立てられます。通報者と内部調査情報は公開しません。\n8. 運営が制作・管理するPetと投稿が含まれます。通常投稿の画面で表示し、実際の反応だけを集計します。運営コンテンツは所有または許諾素材を使います。\n9. アカウント削除はアプリ内から申請できます。ログイン中のアカウントで削除を確認した後にアクセスを失効し、本人データ・提供写真・関連公開物を削除計画に従って処理します。他の人が提供したデータの扱いは権利と共同管理の状態に従います。実行期限とバックアップ運用の正式提供は配備・検証後に案内します。\n10. 障害、保守、違反対処による利用制限が生じる場合があります。重要な変更は事前に案内し、必要な同意を取得します。法律で認められない責任免除を定めません。問い合わせ先と提供主体は公開前に記載します。\n\n取扱主体の正式氏名/事業名：本人情報待ち。運営名：MEFRION。問い合わせ先：nextedovation@gmail.com。正式URL・発効日：未設定。"
    static let privacy = "現在は提供準備中です。正式な取扱主体・委託先と処理地域、運用実績を補完するまで、発効済みの文書として扱いません。\n\n取得する情報と目的\n\n認証識別子、メール、表示名、同意状態を登録・本人確認・復旧に使用します。Pet情報、写真、撮影日、家族参加情報を非公開記録と家族共有に使用します。公開を選んだプロフィール・投稿・コメント・反応・Twins候補・共有カードを指定した範囲で表示します。通知設定・通知先は希望した通知に、通報・処分・最小監査情報は安全な運営と異議対応に使用します。障害情報と件数はサービス改善に使用し、写真・本文・招待秘密・認証資格を不要にログへ記録しません。\n\n公開と共有\n\n家族内写真は初期非公開です。公開Pet、SNS投稿、Twins参加、外部共有には個別の明示操作と必要な提供者同意があります。閲覧・保存・アルバム登録だけで公開しません。家族原本を運営者が任意に閲覧できる権限は設けません。公開を選んだデータは第三者に閲覧され、外部コピーの回収はできません。\n\nTwinsの入力\n\n参考写真検索では、検索ボタンを押した時に犬猫写真の特徴数値・近重複判定用指紋・種類をSupabaseへ送信し、サーバーで候補を比較します。写真そのものは送信せず、送信した特徴を候補DB・履歴・アプリログへ保存しません。再試行用の候補ID・識別子は10分で利用終了し、期限切れ行は次回検索時に整理します。回数制限用のアカウントまたは端末識別子・日付・回数は当日を含む3日分を検索時に整理します。通信基盤の標準リクエストメタデータは別途保持される可能性があり、写真・特徴値をログに記録しない運用を行います。従来の公開Pet検索は端末内比較です。10分経過・画面終了・アプリ非アクティブ時に未保存入力を破棄します。アプリ内アルバムから選ぶ写真は、別途家族保存した写真です。会員の検索履歴には候補ID・状態等の記録を保存します。公開候補登録と外部共有は別の同意を用います。広告や汎用AI学習へ写真を自動転用しません。\n\n委託・国外処理・安全管理\n\n現在のサービス基盤はSupabaseを使用します。正式提供時は契約主体、処理地域、国外取扱いの情報、安全管理を確認し、必要な説明/同意を整えます。通信の保護、権限分離、Keychain、用途別公開、MFA、最小権限、失効再確認を採用します。委託先の契約やバックアップ機能が設定済みだとは断定しません。\n\n保持・削除\n\n非公開データは利用目的に必要な期間保管します。用途同意の撤回・削除受付で関連公開を終了します。アプリ内の退会手続にはログインと明示確認が必要です。採用する運用目標は原本/派生/Authの7日以内処理、暗号化バックアップ30日、技術ログ30日、安全監査180日、最小の復元抑止台帳365日です。これらの自動期限処理と常時運用は未配備であり、現在の利用者向け保証ではありません。正式提供前に実際の処理・復元時再削除を検証します。法律上必要な保全は理由・対象・期間を限定します。\n\n本人の権利・問い合わせ\n\nアプリからプロフィール編集、用途同意の撤回、写真削除、退会を行えます。開示・訂正・利用停止等の問い合わせは、nextedovation@gmail.comで本人確認のうえ対応します。パスワードや認証コードの送付は求めません。変更時は変更点と適用日を案内し、必要な同意を取得します。\n\n運営名：MEFRION。問い合わせ先：nextedovation@gmail.com。取扱主体の正式氏名/事業名・正式URL・発効日：本人情報/設定待ち。"
}

struct FamilyInviteView:View {
    let pet:CloudPet
    @ObservedObject var client:CloudFamilyClient
    @State private var showQR=false
    @State private var cancel=false
    private var shareValue:String? {client.invitation.map {"mefrion://family?token="+$0.token}}
    var body:some View {
        ScrollView {VStack(alignment:.leading,spacing:18) {
            PhotoHero(image:client.images.values.first,height:200)
            Text("大切な家族と、一緒に見守ろう").font(.title2.bold())
            Text(pet.name+"の家族アルバム").font(.headline)
            Text("家族は写真の閲覧・追加ができます。公開操作や提供者の公開同意は別に確認します。").font(.caption).foregroundStyle(.secondary)
            if let value=shareValue,let invite=client.invitation {
                HStack {ShareLink(item:value) {Label("招待を共有",systemImage:"link")}.buttonStyle(CoralButtonStyle());Button("QRコードを表示") {showQR.toggle()}.buttonStyle(.bordered)}
                if showQR,let qr=qrImage(value) {Image(uiImage:qr).interpolation(.none).resizable().scaledToFit().frame(height:220).frame(maxWidth:.infinity).accessibilityLabel("家族への招待QRコード")}
                Text("有効期限："+invite.expires_at).font(.caption)
                Label("1回だけ使える招待です",systemImage:"person.badge.plus").font(.subheadline)
                Button("招待を取り消す",role:.destructive) {cancel=true}.frame(minHeight:44)
            } else {Button("招待を作成") {Task {await client.perform {try await client.invite(pet:pet.id)}}}.buttonStyle(CoralButtonStyle()).disabled(client.busy || pet.role != "owner")}
            if client.busy {ProgressView()}
            if let error=client.error {Text(error).foregroundStyle(.red)}
            Text("リンクを受け取る端末にもMEFRIONが必要です。Universal Linksは公開準備の工程で接続します。").font(.caption).foregroundStyle(.secondary)
        }.padding(16)}.background(Theme.background).navigationTitle("家族を招待").navigationBarTitleDisplayMode(.inline).protectWhenInactive()
            .confirmationDialog("この招待を取り消しますか？",isPresented:$cancel) {Button("招待を取り消す",role:.destructive) {Task {await client.perform {try await client.cancelInvite()}}}}
    }
    private func qrImage(_ value:String)->UIImage? {
        let filter=CIFilter.qrCodeGenerator();filter.message=Data(value.utf8)
        guard let output=filter.outputImage,let cg=CIContext().createCGImage(output.transformed(by:CGAffineTransform(scaleX:8,y:8)),from:output.extent.applying(CGAffineTransform(scaleX:8,y:8))) else{return nil};return UIImage(cgImage:cg)
    }
}

struct FamilyInvitationAcceptView:View {
    @ObservedObject private var client=CloudFamilyClient.shared
    @State var token:String=""
    @State private var confirmed=false
    @State private var joined=false
    var body:some View {
        ScrollView {VStack(spacing:24) {
            Image(systemName:"envelope.badge.fill").font(.system(size:56)).foregroundStyle(Theme.accent).padding(25).background(Theme.accent.opacity(0.08)).clipShape(Circle())
            Text("招待が届きました！").font(.title2.bold())
            Text("家族のペットアルバムに参加するための招待です。").multilineTextAlignment(.center).font(.subheadline)
            if !client.authenticated {NavigationLink {CloudFamilyView()} label: {Text("ログインして招待を確認")}.buttonStyle(CoralButtonStyle())}
            else if joined {Label("家族に参加しました",systemImage:"checkmark.circle.fill").foregroundStyle(Theme.accent)}
            else {
                TextField("招待トークン",text:$token).textInputAutocapitalization(.never).autocorrectionDisabled().padding(14).background(.white).clipShape(RoundedRectangle(cornerRadius:12))
                Toggle("家族内の写真を閲覧・追加する範囲に同意する",isOn:$confirmed)
                Button("参加する") {let value=token;Task {await client.perform {try await client.accept(token:value,confirmed:confirmed);token="";joined=true}}}.buttonStyle(CoralButtonStyle()).disabled(!confirmed || token.isEmpty || client.busy)
            }
            if let error=client.error {Text(error).foregroundStyle(.red)}
            Text("SNS・Twinsへの公開権限はこの参加操作で付与されません。").font(.caption).foregroundStyle(.secondary)
        }.padding(24)}.background(Theme.background).navigationTitle("家族への招待").navigationBarTitleDisplayMode(.inline).protectWhenInactive().task {await client.restore()}
    }
}

struct CloudPetPublicSettingsView:View {
    let pet:CloudPet
    @ObservedObject var client:CloudFamilyClient
    @State private var selectedPublic:Bool?
    @State private var confirming=false
    @State private var changed=false
    var body:some View {
        ScrollView {VStack(alignment:.leading,spacing:22) {
            PhotoHero(image:client.images.values.first)
            Text(pet.name).font(.title2.bold())
            Label("公開設定",systemImage:"globe").font(.headline)
            Text("現在の設定を推測せず、変更する設定を選びます。家族の元写真はどちらでも非公開のままです。").font(.caption).foregroundStyle(.secondary)
            HStack(spacing:12) {option("公開","globe",true);option("非公開","lock",false)}
            Button("選択した設定を保存") {confirming=true}.buttonStyle(CoralButtonStyle()).disabled(selectedPublic==nil || pet.role != "owner" || client.busy)
            Label("Twinsへの参加",systemImage:"pawprint.fill").font(.headline)
            Text("候補登録のクラウド接続は準備中です。家族の写真は自動登録しません。").font(.caption)
            if changed {Text("公開設定を保存しました").foregroundStyle(Theme.accent)}
            if let error=client.error {Text(error).foregroundStyle(.red)}
        }.padding(16)}.background(Theme.background).navigationTitle("編集・公開設定").navigationBarTitleDisplayMode(.inline)
            .confirmationDialog(selectedPublic==true ? "Petのプロフィールを公開しますか？" : "公開プロフィールと関連する投稿を停止しますか？",isPresented:$confirming,titleVisibility:.visible) {Button("確認して保存") {if let enabled=selectedPublic {Task {await client.perform {try await client.setPublicProfile(pet:pet.id,enabled:enabled,explicit:enabled);changed=true}}}}} message: {Text("写真の公開投稿は、提供者の用途同意と投稿の確認を別途必要とします。")}
    }
    private func option(_ title:String,_ icon:String,_ enabled:Bool)->some View {
        Button {selectedPublic=enabled;changed=false} label: {VStack(spacing:10) {Image(systemName:icon).font(.title2);Text(title).bold()}.frame(maxWidth:.infinity).frame(height:110).background(.white).clipShape(RoundedRectangle(cornerRadius:14)).overlay(RoundedRectangle(cornerRadius:14).stroke(selectedPublic==enabled ? Theme.accent : Color(.systemGray5),lineWidth:1))}.foregroundStyle(selectedPublic==enabled ? Theme.accent : Theme.text)
    }
}

struct CloudPostEntryView:View {
    private enum Step {case media,caption}
    var albumOnly=false
    @ObservedObject private var client=CloudFamilyClient.shared
    @State private var chosenPetID=""
    @State private var selection:[PhotosPickerItem]=[]
    @State private var photos:[QuickPostPhoto]=[]
    @State private var caption=""
    @State private var step:Step = .media
    @State private var featuredPhotoID:UUID?
    @State private var importing=false
    @State private var importError:String?
    @State private var rejectedMedia:[RejectedPostMedia]=[]
    @State private var importGeneration=UUID()
    @State private var postKey=UUID()
    @State private var posted:CloudPublication?
    @State private var albumSaved=false
    @State private var postedPhotoIDs:[String]=[]
    @State private var showingCamera=false
    @State private var previewVideoURL:URL?
    @State private var submitting=false
    @State private var submissionError:String?
    @FocusState private var editingCaption:Bool
    private var ownedPets:[CloudPet] {client.pets.filter{$0.role=="owner"}}
    private var chosenPet:CloudPet? {ownedPets.first(where:{$0.id==chosenPetID}) ?? ownedPets.first}
    private var featuredPhoto:QuickPostPhoto? {photos.first(where:{$0.id==featuredPhotoID}) ?? photos.first}
    private var canAdvance:Bool {chosenPet != nil && !photos.isEmpty && photos.count<=10 && !importing && !submitting && posted==nil && !albumSaved}
    private var captionLimit:Int {albumOnly ? 200 : 500}
    private var canPost:Bool {canAdvance && caption.count<=captionLimit}
    var body:some View {
        ScrollViewReader {scrollProxy in
        ScrollView {VStack(alignment:.leading,spacing:13) {
            if client.authenticated {
                if ownedPets.isEmpty {
                    ContentUnavailableView("うちの子の写真を投稿",systemImage:"pawprint",description:Text("写真を投稿するときに、うちの子を登録できます"))
                    NavigationLink("うちの子を登録") {CloudFamilyView()}.buttonStyle(CoralButtonStyle()).frame(maxWidth:.infinity)
                } else if let pet=chosenPet {
                    if ownedPets.count>1 {
                        Text("誰の写真？").font(.subheadline.weight(.semibold))
                        ScrollView(.horizontal,showsIndicators:false) {HStack(spacing:8) {
                            ForEach(ownedPets) {item in
                                Button(item.name) {chosenPetID=item.id}
                                    .buttonStyle(.bordered)
                                    .tint(item.id==pet.id ? Theme.accent : Theme.secondaryText)
                                    .accessibilityIdentifier("post-entry-pet-"+item.id)
                            }
                        }}
                    } else {
                        Label(pet.name+"の投稿",systemImage:"pawprint.fill")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.actionText)
                    }
                    if posted != nil || albumSaved {
                        VStack(spacing:12) {
                            Image(systemName:"checkmark.circle.fill").font(.system(size:48)).foregroundStyle(Theme.accent)
                            Text(albumSaved ? "アルバムに残したよ！" : posted?.state=="published" ? "投稿できたよ！" : "投稿を受け付けたよ！")
                                .font(.title3.bold())
                            if !albumSaved && posted?.state != "published" {Text("準備が終わると、おすすめに表示されます。").font(.footnote).foregroundStyle(Theme.secondaryText)}
                            Button("もう1件投稿する") {reset()}.buttonStyle(CoralButtonStyle())
                            if albumSaved {
                                NavigationLink("アルバムを見る") {CloudAlbumLibraryView()}
                                    .font(.subheadline.weight(.semibold))
                            } else {
                                NavigationLink("自分の投稿を見る") {CloudMyPostsView(client:client)}
                                    .font(.subheadline.weight(.semibold))
                            }
                            #if DEBUG
                            if ProcessInfo.processInfo.arguments.contains("--ui-test-isolated"),!postedPhotoIDs.isEmpty {
                                Button("検証投稿を削除") {removeTestPost(pet:pet)}
                                    .accessibilityIdentifier("quick-post-fixture-cleanup")
                            }
                            #endif
                        }.frame(maxWidth:.infinity).padding(24).background(.white,in:RoundedRectangle(cornerRadius:22))
                    } else if step == .media {
                        if !rejectedMedia.isEmpty {rejectedMediaPanel}
                        if let featuredPhoto {
                            mediaPreview(featuredPhoto)
                            ScrollView(.horizontal,showsIndicators:false) {HStack(alignment:.top,spacing:10) {
                                ForEach(Array(photos.enumerated()),id:\.element.id) {index,photo in
                                    mediaThumbnail(photo,index:index)
                                }
                            }.padding(.vertical,4)}
                            Text("左から順に表示されます · 長押しで並べ替え")
                                .font(.caption).foregroundStyle(Theme.secondaryText)
                        } else if rejectedMedia.isEmpty {
                            VStack(spacing:13) {
                                ZStack {
                                    Circle().fill(.white).frame(width:112,height:112)
                                    Image(systemName:"pawprint.fill").font(.system(size:48)).foregroundStyle(Theme.accent)
                                    Image(systemName:"heart.fill").font(.system(size:17)).foregroundStyle(Theme.accent).offset(x:47,y:-43)
                                }
                                Text(albumOnly ? "かわいい思い出を残そう ♡" : "今日のかわいいを、シェアしよう ♡")
                                    .font(.headline).foregroundStyle(Theme.text)
                                Text("写真も動画も、合わせて10件まで").font(.caption).foregroundStyle(Theme.secondaryText)
                            }.frame(maxWidth:.infinity,minHeight:205)
                                .background(Theme.accent.opacity(0.065),in:RoundedRectangle(cornerRadius:24))
                        }
                        HStack(spacing:10) {
                            PhotosPicker(selection:$selection,maxSelectionCount:max(1,10-photos.count),matching:.any(of:[.images,.videos])) {
                                Label(photos.isEmpty ? "写真・動画を選ぶ" : "追加する",systemImage:"photo.badge.plus")
                                    .frame(maxWidth:.infinity,minHeight:52)
                                    .background(.white,in:RoundedRectangle(cornerRadius:17))
                            }.buttonStyle(.plain).disabled(photos.count>=10 || importing || client.busy)
                                .accessibilityIdentifier("quick-post-pick-photos")
                            Button {showingCamera=true} label: {
                                Label("写真を撮る",systemImage:"camera.fill")
                                    .frame(maxWidth:.infinity,minHeight:52)
                                    .background(.white,in:RoundedRectangle(cornerRadius:17))
                            }.buttonStyle(.plain).accessibilityIdentifier("quick-post-camera")
                                .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera) || photos.count>=10 || importing || client.busy)
                        }.font(.subheadline.weight(.semibold)).foregroundStyle(Theme.actionText)
                        #if DEBUG
                        if ProcessInfo.processInfo.arguments.contains("--ui-test-isolated"),!ProcessInfo.processInfo.arguments.contains("--appstore-screenshots") {
                            Button("検証用の写真を選ぶ") {
                                guard let image=UIImage(named:"appstore-dog-one") else{return}
                                let unique=UIGraphicsImageRenderer(size:image.size).image {_ in
                                    image.draw(in:CGRect(origin:.zero,size:image.size))
                                    UUID().uuidString.draw(at:CGPoint(x:4,y:4),withAttributes:[.font:UIFont.systemFont(ofSize:8),.foregroundColor:UIColor.black])
                                }
                                guard let data=unique.pngData(),let jpeg=try? CloudPhotoCodec.encode(data),let preview=UIImage(data:jpeg) else{return}
                                let photo=QuickPostPhoto(id:UUID(),jpeg:jpeg,image:preview)
                                photos.append(photo);featuredPhotoID=photo.id;postKey=UUID()
                            }.accessibilityIdentifier("quick-post-fixture-photo")
                        }
                        #endif
                        if !photos.isEmpty {
                            Button("選んだ写真・動画をすべて外す") {clearSelectedMedia()}
                                .font(.caption.weight(.medium)).foregroundStyle(Theme.secondaryText)
                                .disabled(importing)
                                .accessibilityIdentifier("quick-post-clear-media")
                        }
                    } else {
                        Button {editingCaption=false;step = .media} label: {
                            Label("写真・動画にもどる",systemImage:"chevron.left")
                                .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.actionText)
                        }.accessibilityIdentifier("quick-post-back-media")
                        if let featuredPhoto {mediaPreview(featuredPhoto,height:190)}
                        Text("ひとこと ♡").font(.headline).foregroundStyle(Theme.text)
                        ZStack(alignment:.topLeading) {
                            if caption.isEmpty {Text("この瞬間のこと、書いてみよう（なくてもOK）")
                                .foregroundStyle(Theme.secondaryText).padding(.horizontal,20).padding(.top,19).allowsHitTesting(false)}
                            TextEditor(text:$caption).focused($editingCaption)
                                .font(.body).scrollContentBackground(.hidden)
                                .padding(.horizontal,13).padding(.vertical,10)
                                .frame(minHeight:180)
                                .accessibilityIdentifier("quick-post-caption")
                        }.background(.white,in:RoundedRectangle(cornerRadius:18))
                            .id("quick-post-caption-container")
                        Text("\(caption.count)/\(captionLimit)").font(.caption)
                            .foregroundStyle(caption.count>captionLimit ? .red : Theme.secondaryText)
                            .frame(maxWidth:.infinity,alignment:.trailing)
                    }
                    if importing {PawLoadingView(title:"犬・猫が写っているか確認中",compact:true)}
                    if submitting {PawLoadingView(title:"送信中。完了までお待ちください",compact:true)}
                    if let importError {
                        Label(importError,systemImage:"exclamationmark.circle.fill")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(.red)
                            .frame(maxWidth:.infinity,alignment:.leading).padding(14)
                            .background(Color.red.opacity(0.08),in:RoundedRectangle(cornerRadius:16))
                    }
                    if let submissionError {Text("投稿できませんでした："+submissionError).font(.footnote).foregroundStyle(.red)}
                }
            } else {
                ContentUnavailableView("投稿するにはログイン",systemImage:"heart.text.square",description:Text("うちの子の写真を、みんなに見せよう"))
                NavigationLink {CloudFamilyView()} label: {Text("ログイン・新規登録").frame(maxWidth:.infinity)}.buttonStyle(CoralButtonStyle())
            }
        }.disabled(submitting).padding(16).padding(.bottom,editingCaption ? 220 : 0)}.background(Theme.background)
            .onChange(of:editingCaption) {_,focused in
                if focused {withAnimation(.easeOut(duration:0.2)) {scrollProxy.scrollTo("quick-post-caption-container",anchor:.top)}}
            }
            .onReceive(NotificationCenter.default.publisher(for:UIResponder.keyboardWillShowNotification)) {_ in
                if editingCaption {withAnimation(.easeOut(duration:0.2)) {scrollProxy.scrollTo("quick-post-caption-container",anchor:.top)}}
            }
            .safeAreaInset(edge:.bottom,spacing:0) {
                if !editingCaption && !photos.isEmpty,posted==nil,!albumSaved,let pet=chosenPet {
                    VStack(spacing:8) {
                        Button {
                            if step == .media {step = .caption}
                            else {publish(pet:pet)}
                        } label: {
                            Text(submitting ? "送信中…" : step != .caption ? "次へ" : albumOnly ? "アルバムに残す" : "投稿する")
                                .font(.headline).foregroundStyle(.white)
                                .frame(maxWidth:.infinity,minHeight:52)
                                .background(Theme.accent.gradient,in:Capsule())
                        }.buttonStyle(.plain)
                            .disabled(!(step != .caption ? canAdvance : canPost))
                            .opacity((step != .caption ? canAdvance : canPost) ? 1 : 0.5)
                            .accessibilityIdentifier(step != .caption ? "quick-post-next" : "quick-post-submit")
                    }.padding(.horizontal,16).padding(.top,8).padding(.bottom,10)
                        .background(.regularMaterial)
                }
            }
            .task {
                await client.restore()
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--appstore-screenshots"),photos.isEmpty,
                   let image=UIImage(named:"appstore-dog-one"),let jpeg=image.jpegData(compressionQuality:0.92) {
                    let photo=QuickPostPhoto(id:UUID(),jpeg:jpeg,image:image)
                    photos=[photo];featuredPhotoID=photo.id
                }
                #endif
            }
            .onChange(of:selection) {_,items in load(items)}
            .onChange(of:albumOnly) {_,_ in
                editingCaption=false;step = .media
                if posted != nil || albumSaved {reset()}
            }
            .onChange(of:chosenPetID) {_,_ in resetPhotoIdentity()}
            .onChange(of:caption) {_,_ in if posted==nil {postKey=UUID()} }
            .onChange(of:client.authenticated) {_,active in if !active {reset()} }
            .fullScreenCover(isPresented:$showingCamera) {
                PrivateCameraCapture(onCapture:{image in
                    showingCamera=false
                    importing=true;importError=nil;rejectedMedia=[]
                    Task {
                        do {
                            guard let data=image.jpegData(compressionQuality:0.9) else {throw CloudPhotoCodec.Failure.decode}
                            let jpeg=try CloudPhotoCodec.encode(data)
                            try await PetPostValidator.shared.validatePhoto(jpeg)
                            guard let normalized=UIImage(data:jpeg) else {throw CloudPhotoCodec.Failure.decode}
                            let photo=QuickPostPhoto(id:UUID(),jpeg:jpeg,image:normalized)
                            photos.append(photo);featuredPhotoID=photo.id;postKey=UUID()
                        } catch {
                            rejectedMedia=[RejectedPostMedia(position:1,kind:"写真",preview:image,reason:error.localizedDescription)]
                        }
                        importing=false
                    }
                },onCancel:{showingCamera=false}).ignoresSafeArea()
            }
            .sheet(isPresented:Binding(get:{previewVideoURL != nil},set:{if !$0 {previewVideoURL=nil}})) {
                if let url=previewVideoURL {NavigationStack {QuickPostVideoPreview(url:url)
                    .navigationTitle("動画を確認").navigationBarTitleDisplayMode(.inline)
                    .toolbar {Button("閉じる") {previewVideoURL=nil}}}}
            }
            .toolbar {ToolbarItemGroup(placement:.keyboard) {Spacer();Button("完了") {
                editingCaption=false
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),to:nil,from:nil,for:nil)
            }}}
            .alert("投稿できませんでした",isPresented:Binding(get:{submissionError != nil},set:{if !$0 {submissionError=nil}})) {
                Button("もう一度試す") {submissionError=nil;if let pet=chosenPet {publish(pet:pet)}}
                Button("閉じる",role:.cancel) {submissionError=nil}
            } message: {Text(submissionError ?? "送信できませんでした。")}
            .protectWhenInactive()
        }
    }
    private var rejectedMediaPanel:some View {
        VStack(alignment:.leading,spacing:11) {
            HStack(spacing:9) {
                Image(systemName:"exclamationmark.circle.fill").font(.title2)
                Text("\(rejectedMedia.count)件は追加できなかったよ").font(.title3.bold())
            }.foregroundStyle(Theme.actionText)
            Text("下の写真・動画を確認して、別のものを選んでね。")
                .font(.subheadline).foregroundStyle(Theme.text)
            ForEach(rejectedMedia) {item in
                HStack(alignment:.center,spacing:12) {
                    ZStack {
                        RoundedRectangle(cornerRadius:12).fill(.white)
                        if let preview=item.preview {
                            Image(uiImage:preview).resizable().scaledToFill()
                                .frame(width:72,height:72).clipped()
                                .clipShape(RoundedRectangle(cornerRadius:12))
                        } else {
                            Image(systemName:item.kind=="動画" ? "video.fill" : "photo.fill")
                                .font(.title2).foregroundStyle(Theme.actionText)
                        }
                    }.frame(width:72,height:72)
                    VStack(alignment:.leading,spacing:4) {
                        Text("選んだ\(item.position)番目の\(item.kind)")
                            .font(.subheadline.bold()).foregroundStyle(Theme.text)
                        Text(item.reason).font(.body.weight(.medium)).foregroundStyle(Theme.text)
                            .fixedSize(horizontal:false,vertical:true)
                    }
                    Spacer(minLength:0)
                }.padding(9).background(.white,in:RoundedRectangle(cornerRadius:16))
                    .accessibilityElement(children:.combine)
                    .accessibilityIdentifier("quick-post-rejected-\(item.position)")
            }
        }.padding(14).frame(maxWidth:.infinity,alignment:.leading)
            .background(Theme.accent.opacity(0.10),in:RoundedRectangle(cornerRadius:20))
            .overlay {RoundedRectangle(cornerRadius:20).stroke(Theme.accent.opacity(0.35),lineWidth:1)}
            .accessibilityIdentifier("quick-post-rejected-media")
    }
    private func mediaPreview(_ photo:QuickPostPhoto,height:CGFloat=300)->some View {
        GeometryReader {geometry in
            ZStack {
                RoundedRectangle(cornerRadius:20).fill(Color.black)
                Image(uiImage:photo.image).resizable()
                    .aspectRatio(contentMode:photo.videoURL == nil ? .fill : .fit)
                    .frame(width:geometry.size.width,height:height).clipped().allowsHitTesting(false)
                if photo.videoURL != nil {
                    Button {
                        editingCaption=false
                        previewVideoURL=photo.videoURL
                    } label: {
                        Image(systemName:"play.circle.fill").font(.system(size:54))
                            .foregroundStyle(.white).shadow(radius:5)
                            .frame(maxWidth:.infinity,maxHeight:.infinity)
                    }.accessibilityLabel("選んだ動画を再生")
                }
            }.frame(width:geometry.size.width,height:height)
                .clipShape(RoundedRectangle(cornerRadius:20)).contentShape(Rectangle())
        }.frame(height:height).accessibilityIdentifier("quick-post-featured-media")
    }
    private func mediaThumbnail(_ photo:QuickPostPhoto,index:Int)->some View {
        VStack(spacing:5) {
            Button {featuredPhotoID=photo.id} label: {
                Image(uiImage:photo.image).resizable().scaledToFill()
                    .frame(width:82,height:82).clipped()
                    .overlay(alignment:.topLeading) {
                        Text("\(index+1)").font(.caption2.bold()).foregroundStyle(.white)
                            .frame(width:21,height:21).background(Theme.accent,in:Circle()).padding(4)
                    }
                    .overlay(alignment:.center) {
                        if photo.videoURL != nil {Image(systemName:"play.circle.fill").font(.title3).foregroundStyle(.white).allowsHitTesting(false)}
                    }
                    .clipShape(RoundedRectangle(cornerRadius:12))
                    .overlay {RoundedRectangle(cornerRadius:12).stroke(featuredPhoto?.id==photo.id ? Theme.accent : .clear,lineWidth:3)}
            }.buttonStyle(.plain).accessibilityLabel("\(index+1)番目を大きく表示")
                .accessibilityIdentifier("quick-post-thumbnail-\(index)")
                .overlay(alignment:.topTrailing) {
                    Button {removePhoto(photo.id)} label: {
                        Image(systemName:"xmark").font(.system(size:10,weight:.bold)).foregroundStyle(.white)
                            .frame(width:25,height:25).background(.black.opacity(0.75),in:Circle())
                    }.accessibilityLabel("\(index+1)番目を取り消す")
                        .disabled(importing)
                        .accessibilityIdentifier("quick-post-remove-\(index)")
                        .offset(x:7,y:-7)
                }
                .draggable(photo.id.uuidString)
                .dropDestination(for:String.self) {items,_ in
                    guard !importing else{return false}
                    guard let raw=items.first,let source=UUID(uuidString:raw) else{return false}
                    movePhoto(source,to:photo.id);return true
                }
            HStack(spacing:2) {
                Button {movePhoto(at:index,by:-1)} label: {Image(systemName:"chevron.left").frame(width:36,height:28)}
                    .disabled(importing || index==0).accessibilityLabel("\(index+1)番目を前へ")
                Button {movePhoto(at:index,by:1)} label: {Image(systemName:"chevron.right").frame(width:36,height:28)}
                    .disabled(importing || index==photos.count-1).accessibilityLabel("\(index+1)番目を後へ")
            }.font(.caption.bold()).foregroundStyle(Theme.actionText)
        }.frame(width:82)
    }
    private func movePhoto(_ source:UUID,to target:UUID) {
        guard let from=photos.firstIndex(where:{$0.id==source}),let to=photos.firstIndex(where:{$0.id==target}),from != to else{return}
        let photo=photos.remove(at:from);photos.insert(photo,at:to);postKey=UUID()
    }
    private func movePhoto(at index:Int,by offset:Int) {
        let target=index+offset
        guard photos.indices.contains(index),photos.indices.contains(target) else{return}
        photos.swapAt(index,target);postKey=UUID()
    }
    private func removePhoto(_ id:UUID) {
        guard let index=photos.firstIndex(where:{$0.id==id}) else{return}
        let removed=photos.remove(at:index)
        if let url=removed.videoURL {try? FileManager.default.removeItem(at:url)}
        if featuredPhotoID==id {featuredPhotoID=photos.first?.id}
        if photos.isEmpty {step = .media}
        postKey=UUID()
    }
    private func clearSelectedMedia() {
        for photo in photos {if let url=photo.videoURL {try? FileManager.default.removeItem(at:url)}}
        photos=[];selection=[];rejectedMedia=[];featuredPhotoID=nil;step = .media;postKey=UUID()
    }
    private func load(_ items:[PhotosPickerItem]) {
        guard !items.isEmpty else{return}
        let stamp=UUID();importGeneration=stamp;importing=true;importError=nil;rejectedMedia=[]
        Task {
            var prepared:[QuickPostPhoto]=[]
            var rejected:[RejectedPostMedia]=[]
            for (index,item) in items.enumerated() {
                guard stamp==importGeneration else {
                    for photo in prepared {if let url=photo.videoURL {try? FileManager.default.removeItem(at:url)}}
                    return
                }
                let isVideo=item.supportedContentTypes.contains(where:{$0.conforms(to:.movie)})
                var preview:UIImage?
                do {
                    if isVideo {
                        guard let movie=try await item.loadTransferable(type:QuickPostMovie.self) else {throw QuickVideoError.invalid}
                        defer {try? FileManager.default.removeItem(at:movie.url)}
                        let result:(url:URL,poster:UIImage,duration:Double)
                        do {result=try await QuickVideoCodec.prepare(movie.url)}
                        catch {preview=QuickVideoCodec.preview(movie.url);throw error}
                        preview=result.poster
                        do {try await PetPostValidator.shared.validateVideo(result.url,duration:result.duration)}
                        catch {try? FileManager.default.removeItem(at:result.url);throw error}
                        prepared.append(QuickPostPhoto(id:UUID(),jpeg:nil,image:result.poster,videoURL:result.url,duration:result.duration))
                    } else {
                        let data=try await imageData(from:item)
                        if data.count<=100*1024*1024 {preview=CloudPhotoCodec.preview(data)}
                        let jpeg=try CloudPhotoCodec.encode(data)
                        if preview==nil {preview=CloudPhotoCodec.preview(jpeg)}
                        try await PetPostValidator.shared.validatePhoto(jpeg)
                        guard let image=UIImage(data:jpeg) else {throw CloudPhotoCodec.Failure.decode}
                        prepared.append(QuickPostPhoto(id:UUID(),jpeg:jpeg,image:image))
                    }
                } catch {
                    rejected.append(RejectedPostMedia(position:index+1,kind:isVideo ? "動画" : "写真",preview:preview,reason:error.localizedDescription))
                }
            }
            guard stamp==importGeneration else {
                for photo in prepared {if let url=photo.videoURL {try? FileManager.default.removeItem(at:url)}}
                return
            }
            if photos.count+prepared.count<=10 {
                photos.append(contentsOf:prepared)
                if featuredPhotoID==nil {featuredPhotoID=photos.first?.id}
                rejectedMedia=rejected
            } else {
                for photo in prepared {if let url=photo.videoURL {try? FileManager.default.removeItem(at:url)}}
                importError="写真・動画は合わせて10件までです。"
            }
            selection=[];postKey=UUID();importing=false
        }
    }
    private func imageData(from item:PhotosPickerItem) async throws -> Data {
        if let data=try? await item.loadTransferable(type:Data.self) {return data}
        guard let file=try await item.loadTransferable(type:QuickPostImage.self) else {throw CloudPhotoCodec.Failure.decode}
        defer {try? FileManager.default.removeItem(at:file.url)}
        return try Data(contentsOf:file.url,options:.mappedIfSafe)
    }
    private func resetPhotoIdentity() {
        if posted != nil {reset();return}
        photos=photos.map{QuickPostPhoto(id:UUID(),jpeg:$0.jpeg,image:$0.image,videoURL:$0.videoURL,duration:$0.duration)}
        featuredPhotoID=photos.first?.id;postKey=UUID()
    }
    private func reset() {
        for photo in photos {if let url=photo.videoURL {try? FileManager.default.removeItem(at:url)}}
        importGeneration=UUID();selection=[];photos=[];rejectedMedia=[];caption="";step = .media;featuredPhotoID=nil;editingCaption=false
        showingCamera=false;previewVideoURL=nil;albumSaved=false
        importing=false;importError=nil;submissionError=nil;submitting=false;posted=nil;postedPhotoIDs=[];postKey=UUID()
    }
    private func publish(pet:CloudPet) {
        let chosen=photos
        let text=caption,key=postKey,saveToAlbum=albumOnly
        guard !submitting else{return}
        submitting=true;submissionError=nil
        Task {
            do {
                var photoIDs:[String]=[]
                for medium in chosen {
                    if let jpeg=medium.jpeg {
                        let ids=try await client.uploadForPublication([CloudUploadDraft(pet:pet.id,jpeg:jpeg,captured:nil,id:medium.id)],pet:pet.id)
                        photoIDs.append(contentsOf:ids)
                    } else if let url=medium.videoURL {
                        photoIDs.append(try await client.uploadVideo(pet:pet.id,url:url,poster:medium.image,duration:medium.duration,id:medium.id))
                    }
                }
                postedPhotoIDs=photoIDs
                if saveToAlbum {
                    if !text.isEmpty {
                        for id in photoIDs {
                            try await client.editPhoto(CloudPhoto(id:id,path:"",captured:nil,title:"",mine:true),pet:pet.id,captured:nil,title:"",kind:nil,note:text)
                        }
                    }
                    albumSaved=true
                } else {
                    for id in photoIDs {try await client.setAlbumVisibility(photo:id,visible:false)}
                    for id in photoIDs {try await client.consent(photo:id,purpose:"sns",allowed:true)}
                    try await client.setPublicProfile(pet:pet.id,enabled:true,explicit:true)
                    posted=try await client.requestPublication(pet:pet.id,photos:photoIDs,body:text,key:key)
                }
            } catch {
                submissionError=error.localizedDescription
            }
            submitting=false
        }
    }
    #if DEBUG
    private func removeTestPost(pet:CloudPet) {
        let ids=postedPhotoIDs,post=posted
        Task {await client.perform {
            if let post {try await client.stopPublication(id:post.id)}
            for id in ids {try await client.delete(photo:id,pet:pet.id)}
            reset()
        }}
    }
    #endif
}

private struct RejectedPostMedia:Identifiable {
    let id=UUID()
    let position:Int
    let kind:String
    let preview:UIImage?
    let reason:String
}

private struct QuickPostPhoto:Identifiable {
    let id:UUID
    let jpeg:Data?
    let image:UIImage
    var videoURL:URL?=nil
    var duration:Double=0
}

private struct QuickPostVideoPreview:View {
    let url:URL
    @State private var player:AVPlayer?
    var body:some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let player {VideoPlayer(player:player)}
        }.task(id:url) {player=AVPlayer(url:url);player?.play()}
            .onDisappear {player?.pause();player=nil}
    }
}

private struct QuickPostMovie:Transferable {
    let url:URL
    static var transferRepresentation:some TransferRepresentation {
        FileRepresentation(contentType:.movie) {movie in SentTransferredFile(movie.url)} importing: {received in
            let copy=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".mov")
            try FileManager.default.copyItem(at:received.file,to:copy)
            return QuickPostMovie(url:copy)
        }
    }
}

private struct QuickPostImage:Transferable {
    let url:URL
    static var transferRepresentation:some TransferRepresentation {
        FileRepresentation(contentType:.image) {image in SentTransferredFile(image.url)} importing: {received in
            let copy=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".image")
            try FileManager.default.copyItem(at:received.file,to:copy)
            return QuickPostImage(url:copy)
        }
    }
}

private enum QuickVideoError:LocalizedError {
    case invalid,duration,size,export
    var errorDescription:String? {switch self {
    case .invalid:return "この動画を読み込めませんでした。別の動画を選んでください。"
    case .duration:return "動画は1件5分以内にしてください。"
    case .size:return "動画を50MB以内にできませんでした。短い動画を選んでください。"
    case .export:return "動画を準備できませんでした。もう一度お試しください。"
    }}
}

private enum QuickVideoCodec {
    static func preview(_ source:URL)->UIImage? {
        let generator=AVAssetImageGenerator(asset:AVURLAsset(url:source))
        generator.appliesPreferredTrackTransform=true
        generator.maximumSize=CGSize(width:180,height:180)
        guard let image=try? generator.copyCGImage(at:.zero,actualTime:nil) else {return nil}
        return UIImage(cgImage:image)
    }
    static func prepare(_ source:URL) async throws -> (url:URL,poster:UIImage,duration:Double) {
        let asset=AVURLAsset(url:source)
        let time=try await asset.load(.duration)
        let duration=CMTimeGetSeconds(time)
        guard duration.isFinite,duration>0 else {throw QuickVideoError.invalid}
        guard duration<=300 else {throw QuickVideoError.duration}
        for preset in [AVAssetExportPreset960x540,AVAssetExportPreset640x480,AVAssetExportPresetMediumQuality] {
            guard let exporter=AVAssetExportSession(asset:asset,presetName:preset) else {continue}
            let destination=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".mp4")
            exporter.outputURL=destination;exporter.outputFileType = .mp4
            exporter.shouldOptimizeForNetworkUse=true;exporter.metadata=[]
            exporter.fileLengthLimit=49*1024*1024
            do {
                try await withCheckedThrowingContinuation {continuation in
                    exporter.exportAsynchronously {
                        if exporter.status == .completed {continuation.resume()}
                        else {continuation.resume(throwing:exporter.error ?? QuickVideoError.export)}
                    }
                }
                let size=try destination.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
                guard size>0,size<=49*1024*1024 else {try? FileManager.default.removeItem(at:destination);continue}
                let generator=AVAssetImageGenerator(asset:AVURLAsset(url:destination))
                generator.appliesPreferredTrackTransform=true
                let cg=try generator.copyCGImage(at:CMTime(seconds:min(1,duration/2),preferredTimescale:600),actualTime:nil)
                return (destination,UIImage(cgImage:cg),duration)
            } catch {
                try? FileManager.default.removeItem(at:destination)
            }
        }
        throw QuickVideoError.size
    }
}

struct CloudFamilyActivityView:View {
    let pet:CloudPet
    @ObservedObject var client:CloudFamilyClient
    @State private var records:[CloudFamilyActivity]=[]
    private let titles=["photo.finish":"写真を追加しました","photo.delete":"写真を削除しました","pet.update":"プロフィールを更新しました","invite.accept":"家族が参加しました","member.remove":"家族の参加を終了しました","card.create":"思い出カードを保存しました"]
    var body:some View {
        List {
            Section(pet.name+"の家族の記録") {ForEach(records) {record in VStack(alignment:.leading) {Text(((record.actor_name ?? (record.mine ? "あなた" : "家族"))+"が")+(titles[record.action] ?? "記録を更新しました"));Text(record.created_at).font(.caption).foregroundStyle(.secondary)}}}
            NavigationLink("メンバーの管理") {CloudMembersView(pet:pet,client:client)}
            if records.isEmpty && !client.busy {Text("まだ記録はありません。")}
            if let error=client.error {Text(error).foregroundStyle(.red)}
        }.navigationTitle("家族のアクティビティ").task {await client.performRefresh {records=try await client.familyActivity(pet:pet.id)}}.protectWhenInactive()
        .onChange(of:client.currentUserID) {_,_ in records=[]}
    }
}

struct ViewerMyPageView:View {
    @StateObject private var following=SocialClient()
    @StateObject private var saved=SocialClient()
    private var pets:[FeedPost] {var ids=Set<String>();return following.posts.filter{ids.insert($0.pet_id).inserted}}
    var body:some View {
        ScrollView {VStack(alignment:.leading,spacing:20) {
            PhotoHero(asset:"pet-1",height:170)
            HStack {Image(systemName:"person.crop.circle.fill").font(.system(size:60)).foregroundStyle(Theme.accent).padding(.top,-30);Spacer();NavigationLink {SettingsView()} label: {Text("設定").font(.caption).padding(12).background(.white).clipShape(Capsule())}}
            Text("あなたのマイページ").font(.title2.bold());Text("かわいい毎日に、出会おう。").font(.subheadline)
            HStack {Text("フォロー中のペット").font(.headline);Spacer();Text("\(pets.count)匹").font(.caption).foregroundStyle(.secondary)}
            ScrollView(.horizontal,showsIndicators:false) {HStack(spacing:16) {ForEach(pets) {pet in NavigationLink {PublicPetView(post:pet,client:following)} label: {VStack {Image(pet.asset).resizable().scaledToFill().frame(width:68,height:68).clipShape(Circle());Text(pet.name).font(.caption)}}}}}
            if pets.isEmpty {Text("おすすめから気になるPetをフォローできます。").font(.caption).foregroundStyle(.secondary)}
            Text("保存した投稿").font(.headline)
            LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible()),GridItem(.flexible())],spacing:6) {ForEach(saved.posts) {post in DiscoveryTile(post:post,client:saved)}}
            if saved.posts.isEmpty {Text("保存した投稿はありません").font(.caption).foregroundStyle(.secondary)}
            if let error=following.error ?? saved.error {Text(error).font(.footnote).foregroundStyle(.red)}
        }.padding(16)}.background(Theme.background).navigationTitle("マイページ").navigationBarTitleDisplayMode(.inline).task {await following.load(following:true);await saved.loadSaved()}
    }
}

#if DEBUG
// Isolated, visibly marked review routes. They do not prove cloud functionality.
struct UIReferenceGallery:View {
    @EnvironmentObject var store:PrototypeStore
    @StateObject private var cloud=CloudFamilyClient.uiReviewFixture()
    private let pet=CloudPet(id:"ui-pet",name:"こむぎ",species:"dog",breed:"犬",introduction:"所有デモイラスト",role:"owner")
    private let routes=["01-intro","01-auth","01-invitation","02-home","02-detail","03-create-pet","03-edit-pet","03-public-settings","03-public-profile","04-album","04-add-photos","04-event","05-invite","05-members","05-activity","06-memories","06-card","07-post","07-confirm","07-comments","08-twins","08-crop","08-results","08-empty","08-history","09-search","09-notifications","10-owner","10-viewer","10-settings"]
    @State private var previewIndex=0
    var body:some View {
        Group {
        if ProcessInfo.processInfo.arguments.contains("--ui-preview-sequence") {
            VStack(spacing:0) {
                VStack(spacing:2) {Text("UIプレビュー · 合成データ · クラウド送信なし").font(.caption2);HStack {Text(routes[previewIndex]).font(.caption).accessibilityIdentifier("ui-preview-current");Spacer();Button("次のプレビュー") {previewIndex=(previewIndex+1)%routes.count}.frame(minHeight:44).accessibilityIdentifier("ui-preview-next")}}.padding(.horizontal,12).background(Theme.background).zIndex(1)
                destination(routes[previewIndex]).id(routes[previewIndex]).frame(maxWidth:.infinity,maxHeight:.infinity).clipped().zIndex(0)
            }
        } else {
        List(routes,id:\.self) {route in NavigationLink(route) {destination(route).safeAreaInset(edge:.top) {Text("UIプレビュー · 合成データ · クラウド送信なし").font(.caption2).frame(maxWidth:.infinity).padding(5).background(Theme.background)}.accessibilityIdentifier("ui-review-screen")}.accessibilityIdentifier("ui-route-"+route)}
            .navigationTitle("UI 10枚の検証")
        }
        }.task {
                guard store.pets.isEmpty else{return}
                do {
                    try store.createPet(name:"こむぎ",species:.dog,breed:"犬",introduction:"かわいい毎日を、いっしょに。")
                    store.addDemoDrafts();try store.saveDrafts(allowDuplicates:false)
                    if let first=store.photos.first {try store.updatePhoto(first.id,title:"同じ日の思い出",captured:Self.todayOneYearAgo)}
                    try store.recordTwinsSearch(species:.dog,state:"results",mode:"fixture",candidates:[2,4])
                } catch {store.operationError=error.localizedDescription}
            }
    }
    private static var todayOneYearAgo:String {
        let calendar=Calendar(identifier:.gregorian);let now=calendar.dateComponents([.year,.month,.day],from:Date())
        return String(format:"%04d-%02d-%02d",(now.year ?? 2026)-1,now.month ?? 1,now.day ?? 1)
    }
    private var sample:FeedPost {FeedPost(id:"ui-post",pet_id:"ui-pet",name:"こむぎ",species:"dog",body:"かわいい毎日を、いっしょに。",asset:"pet-0",images:[FeedImage(asset:"pet-0",captured:nil),FeedImage(asset:"pet-1",captured:nil)],likes:0,comments:0,liked:false,saved:false,following:false)}
    @ViewBuilder private func destination(_ route:String)->some View {
        let petID=store.pets.first?.id ?? UUID()
        switch route {
        case "01-intro":WelcomeFlowView(onStart:{})
        case "01-auth":WelcomeFlowView(initialStep:1,onStart:{})
        case "01-invitation":FamilyInvitationAcceptView()
        case "02-home":HomeView()
        case "02-detail","07-comments":PostDetailView(post:sample,client:SocialClient())
        case "03-create-pet":PetForm()
        case "03-edit-pet":LocalPetEditor(petID:petID)
        case "03-public-settings":CloudPetPublicSettingsView(pet:pet,client:cloud).disabled(true)
        case "03-public-profile":PublicPetView(post:sample,client:SocialClient())
        case "04-album":AlbumView(petID:petID)
        case "04-add-photos":AlbumComposer()
        case "04-event":if let photo=store.photos.first {PhotoEditor(photoID:photo.id)}
        case "05-invite":FamilyInviteView(pet:pet,client:cloud)
        case "05-members":CloudMembersView(pet:pet,client:cloud).disabled(true)
        case "05-activity":CloudFamilyActivityView(pet:pet,client:cloud).disabled(true)
        case "06-memories":MemoryTimelineView(petID:petID)
        case "06-card":ComparisonView(petID:petID,ids:Array(store.photos.prefix(2).map(\.id)))
        case "07-post":CloudPostEntryView()
        case "07-confirm":CloudPublicationComposer(pet:pet,photos:cloud.photos,images:cloud.images,client:cloud).disabled(true)
        case "08-twins":TwinsView()
        case "08-crop":if let image=UIImage(named:"pet-0") {PrivateCropView(image:image,onApply:{_ in})}
        case "08-results":TwinsView(reviewState:"results")
        case "08-empty":TwinsView(reviewState:"insufficient")
        case "08-history":TwinsHistoryView()
        case "09-search":PublicSearchView()
        case "09-notifications":NotificationHubView()
        case "10-owner":MyPage()
        case "10-viewer":ViewerMyPageView()
        default:SettingsView()
        }
    }
}
#endif

struct PrivateProfilePhotoChoice:View {
    let petID:UUID
    let onSelect:(UUID?)->Void
    @EnvironmentObject var store:PrototypeStore
    @Environment(\.dismiss) private var dismiss
    var body:some View {
        ScrollView {VStack(alignment:.leading,spacing:16) {
            Text("このPetのアルバム写真から選びます。プロフィールを編集しても写真は公開されません。").font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible()),GridItem(.flexible())],spacing:8) {
                ForEach(store.album(petID)) {photo in Button {onSelect(photo.id)} label: {Image(uiImage:photo.image).resizable().scaledToFill().frame(height:110).clipped().clipShape(RoundedRectangle(cornerRadius:10))}.accessibilityLabel("プロフィール写真を選択")}
            }
            if store.album(petID).isEmpty {ContentUnavailableView("アルバムに写真を追加してください",systemImage:"photo")}
            Button("写真を設定しない") {onSelect(nil)}
        }.padding(16)}.background(Theme.background).navigationTitle("写真を選ぶ").navigationBarTitleDisplayMode(.inline)
            .toolbar {ToolbarItem(placement:.cancellationAction) {Button("キャンセル") {dismiss()}}}.protectWhenInactive()
    }
}

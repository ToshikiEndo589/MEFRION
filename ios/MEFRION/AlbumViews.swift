import SwiftUI
import PhotosUI

struct PetForm: View {
    @EnvironmentObject var store: PrototypeStore
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var species = Species.dog
    @State private var speciesSelected=false
    @State private var breed = ""
    @State private var introduction = ""
    @State private var sex=""
    @State private var birthday=""
    @State private var error: String?
    var body: some View {
        Form {
            Section {
                Image(systemName:"pawprint.fill").font(.system(size:48)).foregroundStyle(Theme.accent)
                    .frame(maxWidth:.infinity).frame(height:120).background(Theme.accent.opacity(0.07)).clipShape(RoundedRectangle(cornerRadius:16))
                Text("うちの子のプロフィールをつくろう").font(.headline)
                Label("家族内のみ・写真0枚で作成できます。",systemImage:"lock").font(.caption)
            }
            TextField("犬・猫の名前（必須）", text: $name).accessibilityIdentifier("pet-name")
            PetSpeciesSelectionField(species:Binding(get:{species.rawValue},set:{if let next=Species(rawValue:$0) {species=next}}),selected:$speciesSelected)
            if speciesSelected {
                BreedAutocompleteField(species:species.rawValue,text:$breed,identifier:"private-pet-breed")
            }
            Picker("性別（任意）",selection:$sex) {Text("未設定").tag("");Text("男の子").tag("male");Text("女の子").tag("female")}.pickerStyle(.segmented)
            TextField("誕生日 YYYY / YYYY-MM / YYYY-MM-DD（任意）",text:$birthday).keyboardType(.numbersAndPunctuation)
            TextField("紹介文（任意）", text: $introduction,axis:.vertical)
            if let error { Text(error).foregroundStyle(.red) }
            Button("非公開で作成") {
                do { let selectedBreed=PetBreedCatalog.canonical(breed,species:species == .cat ? "cat" : "dog") ?? breed.trimmingCharacters(in:.whitespacesAndNewlines);try store.createPet(name: name, species: species, breed: selectedBreed, introduction: introduction,sex:sex.isEmpty ? nil : sex,birthday:birthday.isEmpty ? nil : birthday); dismiss() }
                catch { self.error = error.localizedDescription }
            }.disabled(!speciesSelected || !(1...40).contains(name.trimmingCharacters(in:.whitespacesAndNewlines).count) || !(1...100).contains(breed.trimmingCharacters(in:.whitespacesAndNewlines).count))
                .frame(minHeight: 44).accessibilityIdentifier("save-private-pet")
        }.scrollContentBackground(.hidden).background(Theme.background).protectWhenInactive().navigationTitle("Petを作る").navigationBarTitleDisplayMode(.inline)
            .onChange(of:species) {_,_ in breed=""}
    }
}

struct AlbumComposer: View {
    @EnvironmentObject var store: PrototypeStore
    @State private var selected: [PhotosPickerItem] = []
    @State private var creatingPet = false
    @State private var importing = false
    @State private var allowDuplicates = false
    @State private var message: String?
    var body: some View {
        Form {
            Section {
                NavigationLink {CloudPostEntryView()} label: {Label("公開投稿を作る",systemImage:"globe")}.accessibilityIdentifier("open-public-post-entry")
                Text("アルバムに残す（家族内のみ）").font(.headline)
                Text("この画面の選択写真はiPhone内に非公開で保存します。サーバーでの家族共有はマイページの「家族で共有」から利用できます。SNS公開の接続は準備中です。")
                    .font(.caption)
                if !store.pets.isEmpty {
                    Picker("対象Pet", selection: $store.selectedPet) {
                        ForEach(store.pets) { Text($0.name).tag(Optional($0.id)) }
                    }
                }
                Button("Petを作成") { creatingPet = true }.accessibilityIdentifier("create-pet")
                PhotosPicker(selection: $selected, maxSelectionCount: PrototypePolicy.albumBatch, matching: .images) {
                    Label("写真を選ぶ（最大30枚）", systemImage: "photo.on.rectangle")
                }.disabled(importing)
                Button("所有テストイラスト2枚で試す") { store.addDemoDrafts() }.disabled(importing).accessibilityIdentifier("demo-photos")
                if importing { ProgressView("写真を読み込み中") }
                if store.failedImports > 0 {
                    Text("読み込み失敗：\(store.failedImports)枚。成功分は保持しています。失敗した画像を再選択してください。")
                }
            }
            if !store.drafts.isEmpty {
                Section("選択した写真 · \(store.drafts.count)枚") {
                    LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible()),GridItem(.flexible())],spacing:6) {
                        ForEach(store.drafts) {draft in Image(uiImage:draft.image).resizable().scaledToFill().frame(height:95).clipped().clipShape(RoundedRectangle(cornerRadius:8)).overlay(alignment:.topTrailing) {Image(systemName:draft.saved ? "checkmark.circle.fill" : "circle").foregroundStyle(Theme.accent).padding(4)}}
                    }
                }
            }
            ForEach($store.drafts) { $draft in
                Section(draft.saved ? "保存済み・家族内のみ" : "保存前の日付確認") {
                    Image(uiImage: draft.image).resizable().scaledToFit().frame(maxHeight: 180)
                        .accessibilityLabel(draft.title.isEmpty ? "選択した写真" : draft.title)
                    TextField("タイトル・節目（任意）", text: $draft.title).disabled(draft.saved)
                    TextField("YYYY / YYYY-MM / YYYY-MM-DD / 空欄は不明", text: $draft.captured)
                        .keyboardType(.numbersAndPunctuation).disabled(draft.saved)
                    if let error = draft.error { Text(error).foregroundStyle(.red) }
                    if !draft.saved { Button("選択から外す", role: .destructive) { store.drafts.removeAll { $0.id == draft.id } } }
                }
            }
            Section {
                Toggle("重複候補も確認して追加する", isOn: $allowDuplicates)
                Button("家族内アルバムに保存・失敗分を再試行") {
                    do {
                        try store.saveDrafts(allowDuplicates: allowDuplicates)
                        message = "保存済み \(store.drafts.filter(\.saved).count)枚。未保存分の日付・重複を確認できます。"
                    } catch { message = error.localizedDescription; if store.pets.isEmpty { creatingPet = true } }
                }.disabled(importing || store.drafts.isEmpty).accessibilityIdentifier("save-private-album")
                if let message { Text(message) }
                Button("保存済みの選択を閉じる") { store.drafts.removeAll { $0.saved } }
            }
            if let petID = store.selectedPet {
                NavigationLink("成長アルバムを見る") { AlbumView(petID: petID) }.accessibilityIdentifier("open-album")
            }
        }.scrollContentBackground(.hidden).background(Theme.background).navigationTitle("新規投稿・写真を追加").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $creatingPet) { NavigationStack { PetForm() } }
        .onChange(of: selected) { _, items in
            guard !items.isEmpty else { return }
            importing = true
            Task { await store.importPhotos(items); selected = []; importing = false }
        }
    }
}

struct MyPage: View {
    @State private var viewer=false
    @EnvironmentObject var store: PrototypeStore
    @StateObject private var savedClient=SocialClient()
    var body:some View {
        VStack(spacing:0) {
            Picker("マイページの表示",selection:$viewer) {Text("飼い主").tag(false);Text("見る専用").tag(true)}.pickerStyle(.segmented).padding(.horizontal,16).padding(.vertical,8)
            if viewer {ViewerMyPageView()} else {ownerPage}
        }.background(Theme.background)
    }
    private var ownerPage:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:22) {
                VStack(alignment:.leading,spacing:0) {
                    ZStack(alignment:.bottomLeading) {
                        if let photo=store.photos.first {
                            Image(uiImage:photo.image).resizable().scaledToFill().frame(height:190).clipped()
                        } else {
                            LinearGradient(colors:[Theme.accent.opacity(0.18),Theme.background],startPoint:.topLeading,endPoint:.bottomTrailing).frame(height:190)
                            Image(systemName:"pawprint.fill").font(.system(size:64)).foregroundStyle(Theme.accent.opacity(0.22)).padding(25)
                        }
                    }
                    HStack(alignment:.bottom) {
                        ZStack {
                            Circle().fill(Theme.background)
                            Image(systemName:"person.crop.circle.fill").font(.system(size:64)).foregroundStyle(Theme.accent)
                        }.frame(width:78,height:78).overlay(Circle().stroke(.white,lineWidth:4)).padding(.top,-36)
                        Spacer()
                        NavigationLink {SettingsView()} label: {Text("設定").font(.caption.bold()).padding(.horizontal,20).frame(minHeight:44).background(Theme.accent.opacity(0.09)).clipShape(Capsule())}
                    }.padding(.horizontal,16)
                    VStack(alignment:.leading,spacing:5) {
                        Text("あなたのマイページ").font(.title2.bold())
                        Text("家族だけの、大切な毎日。").font(.subheadline)
                        Text("開発アカウント · 非公開の記録").font(.caption).foregroundStyle(.secondary)
                    }.padding(16)
                    HStack {
                        profileCount(store.pets.count,title:"うちの子")
                        Divider().frame(height:28)
                        profileCount(store.photos.count,title:"家族内の写真")
                        Divider().frame(height:28)
                        profileCount(store.cards.count,title:"思い出カード")
                    }.padding(.bottom,16)
                }.background(.white).clipShape(RoundedRectangle(cornerRadius:20))
                HStack { Text("うちの子").font(.headline);Spacer();NavigationLink { PetForm() } label: { Label("追加",systemImage:"plus.circle") }.font(.subheadline) }
                if store.pets.isEmpty { Text("写真がなくてもPetを作成できます。").font(.subheadline).foregroundStyle(.secondary) }
                ScrollView(.horizontal,showsIndicators:false) {
                    HStack(spacing:14) {
                        ForEach(store.pets) { pet in
                            NavigationLink { LocalPetProfileView(petID:pet.id) } label: {
                                VStack(alignment:.leading,spacing:10) {
                                    if let image=store.album(pet.id).first(where:{$0.id==pet.coverPhotoID})?.image ?? store.album(pet.id).first?.image { Image(uiImage:image).resizable().scaledToFill().frame(width:140,height:110).clipped().clipShape(RoundedRectangle(cornerRadius:14)) }
                                    else { Image(systemName:"pawprint.fill").font(.system(size:36)).foregroundStyle(Theme.accent).frame(width:140,height:110).background(Theme.accent.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius:14)) }
                                    Text(pet.name).font(.headline);Text(pet.breed.isEmpty ? pet.species.title : pet.breed).font(.caption).foregroundStyle(.secondary)
                                }.foregroundStyle(Theme.text).padding(12).background(.white).clipShape(RoundedRectangle(cornerRadius:18))
                            }
                        }
                    }
                }
                Text("成長アルバム").font(.headline)
                ForEach(store.pets) { pet in
                    NavigationLink { AlbumView(petID:pet.id) } label: {
                        HStack { Image(systemName:"book.closed").foregroundStyle(Theme.accent);VStack(alignment:.leading) { Text(pet.name).font(.subheadline.bold());Text("\(store.album(pet.id).count)枚 · 家族内のみ").font(.caption).foregroundStyle(.secondary) };Spacer();Image(systemName:"chevron.right").font(.caption) }.foregroundStyle(Theme.text).padding(16).background(.white).clipShape(RoundedRectangle(cornerRadius:16))
                    }
                }
                NavigationLink { SavedPostsView() } label: { HStack { Label("保存した投稿",systemImage:"square.stack.3d.up.fill");Spacer();Image(systemName:"chevron.right") }.padding(16).background(.white).clipShape(RoundedRectangle(cornerRadius:16)) }
                NavigationLink { CloudFamilyView() } label: { HStack { Label("家族で共有",systemImage:"person.2");Spacer();Image(systemName:"chevron.right") }.padding(16).background(.white).clipShape(RoundedRectangle(cornerRadius:16)) }.accessibilityIdentifier("open-cloud-family")
                NavigationLink { SettingsView() } label: { HStack { Label("設定",systemImage:"gearshape");Spacer();Image(systemName:"chevron.right") }.padding(16).background(.white).clipShape(RoundedRectangle(cornerRadius:16)) }
                Text("この画面の記録は端末内に保存します。家族共有にはログインが必要です。").font(.footnote).foregroundStyle(.secondary)
                if let error=store.storageError { Text(error).font(.footnote).foregroundStyle(.red) }
            }.padding(16)
        }.background(Theme.background).foregroundStyle(Theme.text).navigationTitle("マイページ").navigationBarTitleDisplayMode(.inline)
    }
    private func profileCount(_ count:Int,title:String)->some View {
        VStack(spacing:3) {Text("\(count)").font(.headline);Text(title).font(.caption2).foregroundStyle(.secondary)}.frame(maxWidth:.infinity)
    }

}

struct SavedPostsView:View {
    @StateObject private var client=SocialClient()
    var body:some View {
        ScrollView { VStack(spacing:16) {
            if client.loading { ProgressView() }
            if client.posts.isEmpty && !client.loading { ContentUnavailableView("保存した投稿はありません",systemImage:"square.stack.3d.up",description:Text("投稿の保存ボタンから追加できます。公開が終了した投稿は表示しません。")) }
            ForEach(client.posts) { FeedCard(post:$0,client:client) }
            if let error=client.error { Text(error).foregroundStyle(.red) }
        }.padding() }.background(Theme.background).navigationTitle("保存した投稿").task { await client.loadSaved() }
    }
}

struct SettingsView:View {
    @EnvironmentObject var store:PrototypeStore
    var body:some View {
        List {
            Section {
                NavigationLink {CloudFamilyView()} label: {settingsRow("アカウント情報","プロフィール・ログインを管理","person")}
                NavigationLink {CloudFamilyView()} label: {settingsRow("公開設定","Petの公開範囲・写真の用途同意","lock")}
                NavigationLink {PrivacyInformationView()} label: {settingsRow("同意設定","利用規約・プライバシーについて","doc.text")}
            }
            Section {
                NavigationLink {if CloudFamilyClient.shared.authenticated {CloudNotificationSettingsView(client:CloudFamilyClient.shared)} else {CloudFamilyView()}} label: {settingsRow("通知設定","いいね・コメント・家族アルバム","bell")}
                NavigationLink {if CloudFamilyClient.shared.authenticated {CloudBlockedPetsView(client:CloudFamilyClient.shared)} else {CloudFamilyView()}} label: {settingsRow("ブロックしたユーザー","相手の管理するすべてのPetに適用","person.crop.circle.badge.xmark")}
            }
            Section {
                NavigationLink {VStack(alignment:.leading,spacing:18) {Label("端末内の非公開データ",systemImage:"lock").font(.headline);Text("Pet \(store.pets.count)匹・写真 \(store.photos.count)枚・比較 \(store.cards.count)件");Text("家族写真は保護領域に保存し、端末バックアップの対象から除外します。個別写真の削除はアルバムから行えます。");Text("退会の全経路削除とバックアップ運用は整備中です。").font(.caption)}.padding().navigationTitle("データ管理")} label: {settingsRow("データ管理","端末内の記録・保存・削除","externaldrive")}
                NavigationLink {VStack(spacing:18) {BrandWordmark();Text("バージョン "+(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"));Text("運営が制作・管理するコンテンツが含まれる場合があります。").font(.footnote)}.padding().navigationTitle("MEFRIONについて")} label: {settingsRow("アプリについて","バージョン・コンテンツについて","info.circle")}
            }
            Section {
                NavigationLink {AccountRetirementView()} label: {Label("アカウントを削除する",systemImage:"trash").foregroundStyle(Theme.accent)}
            }
        }.contentMargins(.bottom,88,for:.scrollContent)
        .scrollContentBackground(.hidden).background(Theme.background).navigationTitle("設定").navigationBarTitleDisplayMode(.inline)
    }
    private func settingsRow(_ title:String,_ subtitle:String,_ icon:String)->some View {
        HStack(spacing:16) {Image(systemName:icon).font(.system(size:22)).frame(width:28);VStack(alignment:.leading,spacing:5) {Text(title).font(.subheadline);Text(subtitle).font(.caption2).foregroundStyle(.secondary)}}.padding(.vertical,8)
    }

}

struct AlbumView: View {
    @EnvironmentObject var store: PrototypeStore
    let petID: UUID
    @State private var collapsed:Set<String>=[]
    private var groups:[String] {Array(Set(store.album(petID).map{$0.captured ?? "日付不明"})).sorted {a,b in if a=="日付不明" {return false};if b=="日付不明" {return true};return a>b}}
    var body: some View {
        ScrollView {
            VStack(spacing: Theme.spacing) {
                Text("家族内のみ・非公開").font(.headline)
                NavigationLink {LocalPetProfileView(petID:petID)} label: {Label("Petプロフィール",systemImage:"pawprint")}
                if store.album(petID).isEmpty { Text("写真1枚から記録を始められます。投稿タブから追加してください。") }
                if !store.memories(petID).isEmpty {
                    Text("去年の今日の思い出").font(.headline)
                    ForEach(store.memories(petID)) { photo in
                        Image(uiImage: photo.image).resizable().scaledToFit().frame(maxHeight: 180)
                            .accessibilityLabel("撮影日の分かる去年の今日の写真")
                    }
                }
                ForEach(groups,id:\.self) {date in
                    let photos=store.album(petID).filter{($0.captured ?? "日付不明")==date}
                    VStack(alignment:.leading,spacing:12) {
                        Button {if collapsed.contains(date) {collapsed.remove(date)} else {collapsed.insert(date)}} label:{HStack {Image(systemName:"calendar").foregroundStyle(Theme.accent);Text(date).bold();Spacer();Text("\(photos.count)枚").font(.caption);Image(systemName:collapsed.contains(date) ? "chevron.down" : "chevron.up")}.foregroundStyle(Theme.text).frame(minHeight:44)}.accessibilityLabel(date+"の写真を"+(collapsed.contains(date) ? "開く" : "閉じる"))
                        if !collapsed.contains(date) {
                            LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible()),GridItem(.flexible())],spacing:10) {
                                ForEach(photos) {photo in
                                    VStack(alignment:.leading,spacing:4) {
                                        NavigationLink {PhotoEditor(photoID:photo.id)} label:{
                                            GeometryReader {geometry in Image(uiImage:photo.image).resizable().scaledToFill().frame(width:geometry.size.width,height:geometry.size.width).clipped().clipShape(RoundedRectangle(cornerRadius:10))}
                                                .aspectRatio(1,contentMode:.fit)
                                        }.accessibilityLabel(photo.title.isEmpty ? "アルバム写真を編集" : photo.title+"を編集")
                                        if !photo.title.isEmpty {Text(photo.title).font(.caption).lineLimit(2)}
                                    }
                                }
                            }
                        }
                    }.padding(12).background(.white).clipShape(RoundedRectangle(cornerRadius:Theme.radius))
                }
            }.padding()
        }.background(Theme.background).foregroundStyle(Theme.text)
            .navigationTitle(store.pets.first { $0.id == petID }?.name ?? "アルバム")
    }
}

struct PhotoEditor: View {
    @EnvironmentObject var store: PrototypeStore
    @Environment(\.dismiss) var dismiss
    let photoID: UUID
    @State private var title = ""
    @State private var captured = ""
    @State private var eventKind=""
    @State private var note=""
    @State private var error: String?
    @State private var confirmDelete = false
    var body: some View {
        Form {
            if let photo=store.photos.first(where:{$0.id==photoID}) {
                Image(uiImage:photo.image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius:14)).accessibilityLabel("編集する家族内の写真")
            }
            Section("イベントの種類") {
                Picker("種類",selection:$eventKind) {Text("未設定").tag("");Text("誕生日").tag("birthday");Text("うちの子記念日").tag("anniversary");Text("お迎えした日").tag("arrival");Text("通院").tag("hospital");Text("その他").tag("other")}
            }
            TextField("タイトル・節目", text: $title)
            TextField("撮影日（空欄は不明）", text: $captured)
            TextField("メモ（任意・200文字まで）",text:$note,axis:.vertical)
            Text("\(note.count) / 200").font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).foregroundStyle(.red) }
            Button("修正を保存") {
                do { try store.updatePhoto(photoID, title: title, captured: captured,eventKind:eventKind,note:note); dismiss() }
                catch { self.error = error.localizedDescription }
            }
            Button("写真を削除", role: .destructive) { confirmDelete = true }
        }.scrollContentBackground(.hidden).background(Theme.background).navigationTitle("記念日・記録を編集").navigationBarTitleDisplayMode(.inline)
        .onAppear { if let p = store.photos.first(where: { $0.id == photoID }) { title = p.title; captured = p.captured ?? "";eventKind=p.eventKind ?? "";note=p.note ?? "" } }
        .confirmationDialog("この写真と、使用している比較カードを削除します。", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("削除する", role: .destructive) { if store.deletePhoto(photoID) { dismiss() } else { error=store.operationError } }
        }
    }
}

struct ComparisonView: View {
    @EnvironmentObject var store: PrototypeStore
    let petID: UUID
    let ids: [UUID]
    var initialText = ""
    var initialZooms: [Double] = [1, 1]
    var initialOffsets: [Double] = [0, 0]
    @State private var zooms: [Double] = [1, 1]
    @State private var offsets: [Double] = [0, 0]
    @State private var text = ""
    @State private var message: String?
    var body: some View {
        ScrollView {
            VStack(spacing: Theme.spacing) {
                GeometryReader { geometry in
                    VStack(spacing: 8) {
                        Label("あの頃と今",systemImage:"heart").font(.title2.bold()).foregroundStyle(Theme.accent)
                        Text("ずっと、いっしょに。").font(.caption).foregroundStyle(Theme.accent)
                        Spacer(minLength:8)
                        HStack(alignment:.center,spacing:12) {
                            ForEach(Array(ids.prefix(2).enumerated()),id:\.element) {item in
                                if let photo=store.photos.first(where:{$0.id==item.element}) {
                                    VStack(spacing:8) {
                                        Image(uiImage:photo.image).resizable().scaledToFill()
                                            .frame(width:max(0,(geometry.size.width-64)/2),height:max(0,geometry.size.height*0.43))
                                            .scaleEffect(zooms[item.offset]).offset(y:geometry.size.height*0.43*offsets[item.offset])
                                            .frame(width:max(0,(geometry.size.width-64)/2),height:max(0,geometry.size.height*0.43)).clipped()
                                            .accessibilityLabel(photo.title.isEmpty ? "比較写真" : photo.title)
                                        Text(photo.captured ?? "日付不明").font(.caption)
                                    }.padding(6).padding(.bottom,8).background(.white)
                                        .rotationEffect(.degrees(item.offset==0 ? -3 : 3)).shadow(color:Theme.accent.opacity(0.1),radius:4,y:3)
                                }
                            }
                        }
                        Spacer(minLength:8)
                        Text(text).font(.caption).lineLimit(3)
                        Spacer(minLength: 0)
                        Text("MEFRION").font(.headline)
                    }.padding(16).frame(width: geometry.size.width, height: geometry.size.height)
                }.aspectRatio(9.0 / 16.0, contentMode: .fit)
                    .background(LinearGradient(colors:[Theme.accent.opacity(0.07),Theme.background],startPoint:.topLeading,endPoint:.bottomTrailing)).clipShape(RoundedRectangle(cornerRadius: Theme.radius))
                ForEach(0..<2, id: \.self) { index in
                    VStack(alignment: .leading) {
                        Text("写真\(index + 1)の切り抜き（拡大・上下位置）")
                        Slider(value: $zooms[index], in: 1...3).accessibilityLabel("写真\(index + 1)の拡大")
                        Slider(value: $offsets[index], in: -0.25...0.25).accessibilityLabel("写真\(index + 1)の上下位置")
                    }
                }
                TextField("短い文章（任意）", text: $text)
                Text("家族内のみ。切り抜き・撮影時期を確認してください。外部共有は未実装です。")
                Button("家族内に比較を保存") {
                    do { try store.saveCard(petID: petID, ids: ids, text: text, zooms: zooms, offsets: offsets); message = "非公開で保存しました。" }
                    catch { message = error.localizedDescription }
                }.buttonStyle(CoralButtonStyle()).frame(minHeight: 44).accessibilityIdentifier("save-private-card")
                if let message { Text(message) }
            }.padding()
        }.navigationTitle("あの頃と今").onAppear { text = initialText; zooms = initialZooms; offsets = initialOffsets }
    }
}

struct PrivateAlbumLibraryView:View {
    @EnvironmentObject var store:PrototypeStore
    @State private var selected:UUID?
    private let columns=Array(repeating:GridItem(.flexible(),spacing:10),count:2)
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:16) {
                Label("家族だけの思い出",systemImage:"lock.fill")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.actionText)
                    .padding(.horizontal,16).padding(.top,4)
                if store.photos.isEmpty {
                    ContentUnavailableView("まだ写真がありません",systemImage:"photo.on.rectangle.angled",description:Text("投稿タブから写真をアルバムに残せます"))
                }
                LazyVGrid(columns:columns,spacing:10) {
                    ForEach(store.photos.sorted {($0.captured ?? "") > ($1.captured ?? "")}) {photo in
                        Button {selected=photo.id} label: {
                            VStack(alignment:.leading,spacing:6) {
                                GeometryReader {geometry in
                                    Image(uiImage:photo.image).resizable().scaledToFill()
                                        .frame(width:geometry.size.width,height:geometry.size.height).clipped()
                                        .clipShape(RoundedRectangle(cornerRadius:13))
                                }.aspectRatio(0.9,contentMode:.fit)
                                HStack(spacing:4) {
                                    Text(store.pets.first(where:{$0.id==photo.petID})?.name ?? "思い出")
                                        .font(.caption.weight(.semibold)).lineLimit(1)
                                    Spacer(minLength:0)
                                    if let captured=photo.captured {Text(captured).font(.caption2).foregroundStyle(Theme.secondaryText).lineLimit(1)}
                                }.padding(.horizontal,2)
                            }.padding(6).background(.white,in:RoundedRectangle(cornerRadius:18))
                                .overlay(alignment:.top) {
                                    RoundedRectangle(cornerRadius:4).fill(Theme.accent.opacity(0.18))
                                        .frame(width:46,height:11).rotationEffect(.degrees(-8)).offset(y:-3)
                                }
                                .shadow(color:Theme.accent.opacity(0.09),radius:5,y:3)
                        }.buttonStyle(.plain).foregroundStyle(Theme.text)
                    }
                }.padding(.horizontal,12)
            }.padding(.bottom,24)
        }.background(Theme.background).navigationTitle("アルバム").navigationBarTitleDisplayMode(.inline)
            .sheet(item:Binding(get:{selected.flatMap {id in store.photos.first(where:{$0.id==id})}},set:{selected=$0?.id})) {photo in
                NavigationStack {
                    ScrollView {VStack(alignment:.leading,spacing:12) {
                        Image(uiImage:photo.image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius:18))
                        Text(store.pets.first(where:{$0.id==photo.petID})?.name ?? "思い出").font(.headline)
                        if !photo.title.isEmpty {Text(photo.title)}
                    }.padding(16)}.navigationTitle("思い出").toolbar {ToolbarItem(placement:.topBarTrailing) {Button("閉じる") {selected=nil}}}
                }
            }.protectWhenInactive()
    }
}

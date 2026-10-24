import SwiftUI

struct CloudUnifiedComposer:View {
    @ObservedObject private var client=CloudFamilyClient.shared
    @State private var publish=true
    @Environment(\.rootTabSwipe) private var moveRootTab
    var body:some View {
        VStack(spacing:0) {
            Picker("保存先",selection:$publish) {Text("公開投稿").tag(true);Text("アルバムに残す").tag(false)}
                .pickerStyle(.segmented).padding(.horizontal,16).padding(.top,6).padding(.bottom,8)
                .accessibilityIdentifier("cloud-composer-destination")
            CloudPostEntryView(albumOnly:!publish)
                .frame(maxWidth:.infinity,maxHeight:.infinity).contentShape(Rectangle())
                .modifier(HorizontalTabSwipe {towardRight in
                    if publish == !towardRight {moveRootTab(towardRight)} else {publish = !towardRight}
                })
        }.background(Theme.background).navigationTitle("新規投稿").navigationBarTitleDisplayMode(.inline).task {await client.restore()}.protectWhenInactive()
    }
}

struct CloudAccountPage:View {
    @ObservedObject private var client=CloudFamilyClient.shared
    @State private var showingManagement=false
    var body:some View {
        ScrollView {VStack(alignment:.leading,spacing:16) {
            HStack(spacing:14) {
                if client.authenticated {
                    NavigationLink {CloudAccountProfileEditor(client:client)} label: {
                        HStack(spacing:12) {
                            ProfileIconImage(encoded:client.accountProfile.icon,size:52,fallback:"person.fill")
                            VStack(alignment:.leading,spacing:4) {
                                Text(client.accountProfile.name.isEmpty ? "マイプロフィール" : client.accountProfile.name)
                                    .font(.headline).foregroundStyle(Theme.text)
                                Text("プロフィールを編集").font(.caption.weight(.semibold)).foregroundStyle(Theme.actionText)
                            }
                            Spacer(minLength:0)
                        }
                    }.buttonStyle(.plain).accessibilityIdentifier("open-account-profile")
                } else {
                    Text("🐾").font(.system(size:31))
                        .frame(width:48,height:48).background(Theme.accent.opacity(0.1),in:Circle())
                    VStack(alignment:.leading,spacing:3) {
                        Text("こんにちは ♡").font(.title3.bold())
                        Text("うちの子も、推しの子も。").font(.subheadline).foregroundStyle(Theme.secondaryText)
                    }
                    Spacer()
                }
                NavigationLink {SettingsView()} label: {Image(systemName:"gearshape").font(.title3).frame(width:44,height:44)}
                    .accessibilityLabel("設定")
            }.padding(16).background(.white,in:RoundedRectangle(cornerRadius:20))
            if client.authenticated {
                if client.pets.isEmpty {
                    VStack(alignment:.leading,spacing:8) {
                        Text("見るだけでも楽しめるよ").font(.headline)
                        Text("気になる犬猫を見つけて、いいねやフォローを楽しもう。")
                            .font(.subheadline).foregroundStyle(Theme.secondaryText)
                    }
                    .frame(maxWidth:.infinity,alignment:.leading)
                    .padding(16)
                    .background(.white,in:RoundedRectangle(cornerRadius:20))
                }
                if !client.pets.isEmpty {
                    Text("うちの子").font(.headline)
                    ForEach(client.pets) {pet in NavigationLink {
                        if pet.role=="owner" {CloudProfileEditor(pet:pet,client:client)}
                        else {CloudAlbumLibraryView()}
                    } label: {
                        HStack(spacing:13) {
                            ProfileIconImage(encoded:pet.icon,size:48)

                            VStack(alignment:.leading,spacing:3) {
                                Text(pet.name).font(.headline)
                                if !pet.breed.isEmpty {Text(pet.breed).font(.caption).foregroundStyle(Theme.secondaryText)}
                                Text(pet.role=="owner" ? "プロフィールを編集" : "写真を見る").font(.caption).foregroundStyle(Theme.actionText)
                            }
                            Spacer();Image(systemName:"chevron.right").font(.caption).foregroundStyle(Theme.secondaryText)
                        }.foregroundStyle(Theme.text).padding(14).frame(maxWidth:.infinity)
                            .background(.white,in:RoundedRectangle(cornerRadius:18))
                    }.accessibilityIdentifier("cloud-pet-"+pet.id)}
                }
                NavigationLink {CloudFamilyView(registrationOnly:true)} label: {
                    Label(client.pets.isEmpty ? "うちの子を登録" : "うちの子を追加",systemImage:"plus.circle.fill")
                        .frame(maxWidth:.infinity)
                }.buttonStyle(.bordered).tint(Theme.actionText).accessibilityIdentifier("open-cloud-family")
                HStack(spacing:10) {
                    NavigationLink {CloudSocialConnectionsView(initialKind:"following",client:client)} label: {
                        Label("フォロー中",systemImage:"heart.circle.fill")
                            .frame(maxWidth:.infinity,minHeight:52)
                            .background(.white,in:RoundedRectangle(cornerRadius:17))
                    }.accessibilityIdentifier("open-following-list")
                    NavigationLink {CloudSocialConnectionsView(initialKind:"followers",client:client)} label: {
                        Label("フォロワー",systemImage:"person.2.fill")
                            .frame(maxWidth:.infinity,minHeight:52)
                            .background(.white,in:RoundedRectangle(cornerRadius:17))
                    }.accessibilityIdentifier("open-followers-list")
                }.font(.subheadline.weight(.semibold)).foregroundStyle(Theme.actionText)
                NavigationLink {CloudDiscoveryView(client:client,initialMode:"saved")} label: {
                    Label("保存した投稿",systemImage:"square.stack.3d.up.fill")
                        .frame(maxWidth:.infinity,alignment:.leading).padding(16)
                        .background(.white,in:RoundedRectangle(cornerRadius:18))
                }.foregroundStyle(Theme.text)
                NavigationLink {CloudLikedPostsView()} label: {
                    Label("いいねした投稿",systemImage:"heart.fill")
                        .frame(maxWidth:.infinity,alignment:.leading).padding(16)
                        .background(.white,in:RoundedRectangle(cornerRadius:18))
                }.foregroundStyle(Theme.text).accessibilityIdentifier("open-liked-posts")
                NavigationLink {ReferenceHistoryView()} label: {
                    Label("そっくりの履歴",systemImage:"pawprint.fill")
                        .frame(maxWidth:.infinity,alignment:.leading).padding(16)
                        .background(.white,in:RoundedRectangle(cornerRadius:18))
                }.foregroundStyle(Theme.text).accessibilityIdentifier("open-twins-history")
                NavigationLink {CloudNotificationSettingsView(client:client)} label: {
                    Label("通知設定",systemImage:"bell.badge.fill")
                        .frame(maxWidth:.infinity,alignment:.leading).padding(16)
                        .background(.white,in:RoundedRectangle(cornerRadius:18))
                }.foregroundStyle(Theme.text).accessibilityIdentifier("open-notification-settings")
                NavigationLink {CloudAlbumSettingsView(client:client)} label: {
                    Label("アルバムの設定",systemImage:"slider.horizontal.3")
                        .frame(maxWidth:.infinity,alignment:.leading).padding(16)
                        .background(.white,in:RoundedRectangle(cornerRadius:18))
                }.foregroundStyle(Theme.text).accessibilityIdentifier("open-album-settings")
                VStack(alignment:.leading,spacing:10) {
                    NavigationLink {CloudMyPostsView(client:client)} label: {
                        HStack {
                            Label("自分の投稿",systemImage:"square.grid.2x2.fill").font(.headline)
                            Spacer()
                            Text("すべて見る").font(.caption.weight(.semibold))
                            Image(systemName:"chevron.right").font(.caption)
                        }
                    }.accessibilityIdentifier("open-my-posts")
                }.foregroundStyle(Theme.text).padding(16)
                    .background(.white,in:RoundedRectangle(cornerRadius:18))
                DisclosureGroup("設定・管理",isExpanded:$showingManagement) {
                    VStack(alignment:.leading,spacing:16) {
                        NavigationLink("家族の招待・メンバー") {CloudAlbumSettingsView(client:client)}
                        NavigationLink("写真の公開許可") {ProviderConsentView(client:client)}
                        NavigationLink("運営からのお知らせ") {CloudModerationNoticesView(client:client)}
                        Button("ログアウト",role:.destructive) {Task {await client.signOut()}}
                    }.padding(.top,8)
                }.padding(16).background(.white,in:RoundedRectangle(cornerRadius:18))
                NavigationLink {AccountRetirementView()} label: {
                    HStack(spacing:12) {
                        Image(systemName:"person.crop.circle.badge.xmark")
                        Text("アカウントを削除する")
                        Spacer()
                        Image(systemName:"chevron.right").font(.caption)
                    }
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .frame(maxWidth:.infinity,minHeight:44)
                    .padding(.horizontal,16)
                    .background(.white,in:RoundedRectangle(cornerRadius:18))
                }.accessibilityIdentifier("open-account-retirement")
            } else {
                Text("見るだけなら登録なしでもOK。フォローや家族アルバムはログインから。")
                    .font(.subheadline).foregroundStyle(Theme.secondaryText)
                NavigationLink {CloudFamilyView()} label: {
                    Text("登録・ログイン").font(.headline).foregroundStyle(.white)
                        .frame(maxWidth:.infinity,minHeight:52)
                        .background(Theme.accent.gradient,in:Capsule())
                }.accessibilityIdentifier("open-cloud-family")
            }
            if let error=client.error {Text(error).foregroundStyle(.red)}
        }.padding(16)}
        // TabView's floating bar is hosted outside this navigation stack. Keep
        // trailing rows above it after the scroll view finishes bouncing.
        .contentMargins(.bottom,88,for:.scrollContent)
        .background(Theme.background).navigationTitle("マイページ").navigationBarTitleDisplayMode(.inline)
        .task {await client.restore();if client.authenticated {await client.performRefresh {async let pets:Void=client.loadPets();async let profile:Void=client.loadAccountProfile();_ = try await (pets,profile)}}}
        .protectWhenInactive()
    }
}

private struct CloudAccountProfileEditor:View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var client:CloudFamilyClient
    @State private var name=""
    @State private var originalName=""
    @State private var icon:String?
    @State private var iconChanged=false
    @State private var importingIcon=false
    @State private var saved=false
    @State private var initialized=false
    private var valid:Bool {name.trimmingCharacters(in:.whitespacesAndNewlines).count<=40 && (originalName.isEmpty || !name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)}
    var body:some View {
        Form {
            Section {EditableProfileIcon(encoded:$icon,changed:$iconChanged,importing:$importingIcon)}
            Section("ニックネーム") {
                TextField("コメントで使う名前",text:$name).accessibilityIdentifier("account-profile-name")
                Text("うちの子の名前・写真は、マイページの「うちの子」から変更できます。")
                    .font(.caption).foregroundStyle(Theme.secondaryText)
            }
            Section {
                if !valid {Text("ニックネームは1〜40文字で入力してね").font(.caption).foregroundStyle(Theme.actionText)}
                if let error=client.error {Text(error).font(.footnote).foregroundStyle(.red)}
            }
        }.disabled(client.busy).scrollContentBackground(.hidden).background(Theme.background)
            .navigationTitle("マイプロフィール").navigationBarTitleDisplayMode(.inline).protectWhenInactive()
            .safeAreaInset(edge:.top,spacing:0) {
                if saved {
                    Label("保存したよ ♡",systemImage:"checkmark.circle.fill").font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.actionText).frame(maxWidth:.infinity).padding(.vertical,9)
                        .background(Theme.accent.opacity(0.08)).accessibilityIdentifier("account-profile-saved")
                }
            }
            .toolbar {ToolbarItem(placement:.topBarTrailing) {
                Button(importingIcon ? "写真を準備中…" : client.busy ? "保存中…" : "保存") {
                    Task {await client.perform {
                        try await client.saveAccountProfile(name:name,icon:icon,iconChanged:iconChanged)
                        originalName=client.accountProfile.name;iconChanged=false;saved=true
                    }}
                }.fontWeight(.semibold).disabled(client.busy || importingIcon || !valid)
                    .accessibilityIdentifier("account-profile-save")
            }}
            .onChange(of:name) {_,_ in saved=false}
            .onChange(of:icon) {_,_ in saved=false}
            .onChange(of:client.currentUserID) {_,_ in dismiss()}
            .onChange(of:[client.accountProfile.name,client.accountProfile.icon ?? ""]) {_,_ in
                if name==originalName && !iconChanged && !saved {
                    name=client.accountProfile.name;originalName=name;icon=client.accountProfile.icon
                }
            }
            .task {
                guard !initialized else{return};initialized=true
                name=client.accountProfile.name;originalName=name;icon=client.accountProfile.icon
            }
    }
}

private struct CloudSocialConnectionsView:View {
    let initialKind:String
    @ObservedObject var client:CloudFamilyClient
    @State private var kind="following"
    @State private var entries:[CloudSocialConnection]=[]
    @State private var loading=false
    @State private var more=true
    @State private var error:String?
    @State private var loadGeneration=UUID()
    var body:some View {
        ScrollView {LazyVStack(spacing:10) {
            Picker("つながり",selection:$kind) {
                Text("フォロー中").tag("following")
                Text("フォロワー").tag("followers")
            }.pickerStyle(.segmented).padding(.bottom,8)
            if let error {
                VStack(spacing:8) {
                    Text(error).font(.subheadline).foregroundStyle(.red)
                    Button("もう一度") {Task {await reload()}}.font(.subheadline.bold())
                }.padding(16)
            }
            ForEach(entries) {entry in
                Group {
                    if let id=entry.profile_pet_id {
                        NavigationLink {CloudPublicPetView(petID:id,client:client)} label: {row(entry)}
                    } else {row(entry)}
                }
            }
            if entries.isEmpty && !loading && error == nil {
                ContentUnavailableView(kind=="following" ? "フォロー中の子はまだいないよ" : "フォロワーはまだいないよ",
                    systemImage:"pawprint",description:Text(kind=="following" ? "気になる子を見つけてフォローしてみよう" : "投稿をシェアして、うちの子を見つけてもらおう"))
            }
            if loading {PawLoadingView(compact:true).frame(maxWidth:.infinity).padding(16)}
            if more && !loading && !entries.isEmpty {
                Button("もっと見る") {Task {await loadNext()}}
                    .font(.subheadline.weight(.semibold)).padding(14)
            }
        }.padding(16)}.background(Theme.background)
            .navigationTitle("つながり").navigationBarTitleDisplayMode(.inline)
            .task {kind=initialKind;await reload()}
            .onChange(of:kind) {_,_ in Task {await reload()}}
            .refreshable {await reload()}
    }
    private func row(_ entry:CloudSocialConnection)->some View {
        HStack(spacing:12) {
            Text(entry.species=="cat" ? "🐱" : entry.species=="dog" ? "🐶" : "🐾")
                .font(.system(size:25)).frame(width:48,height:48)
                .background(Theme.accent.opacity(0.1),in:Circle())
            VStack(alignment:.leading,spacing:3) {
                Text(entry.name).font(.subheadline.bold()).foregroundStyle(Theme.text)
                let detail=kind=="followers" ? (entry.followed_pet_name.map{$0+"をフォロー中"} ?? "") : (entry.breed ?? "")
                if !detail.isEmpty {Text(detail).font(.caption).foregroundStyle(Theme.secondaryText)}
            }
            Spacer()
            if entry.profile_pet_id != nil {Image(systemName:"chevron.right").font(.caption).foregroundStyle(Theme.secondaryText)}
        }.padding(12).background(.white,in:RoundedRectangle(cornerRadius:18))
    }
    private func reload() async {
        loadGeneration=UUID();entries=[];more=true;loading=false;error=nil
        await loadNext()
    }
    private func loadNext() async {
        guard !loading,more else {return}
        let requested=kind,offset=entries.count,generation=loadGeneration
        loading=true;error=nil
        do {
            let page=try await client.socialConnections(kind:requested,offset:offset)
            guard generation==loadGeneration,kind==requested else {return}
            entries+=page;more=page.count==40
        } catch {if generation==loadGeneration,kind==requested {self.error="つながりを読み込めませんでした。もう一度お試しください。"}}
        if generation==loadGeneration {loading=false}
    }
}

private struct CloudLikedPostsView:View {
    @StateObject private var client=CloudFamilyClient()
    var body:some View {CloudDiscoveryView(client:client,initialMode:"liked")}
}

private struct CloudAlbumSettingsView:View {
    @ObservedObject var client:CloudFamilyClient
    var body:some View {
        ScrollView {VStack(alignment:.leading,spacing:16) {
            Text("家族と楽しむアルバム").font(.title3.bold())
            Text("アルバムを一緒に楽しむ家族を管理できます。")
                .font(.subheadline).foregroundStyle(Theme.secondaryText)
            if client.pets.isEmpty {
                if client.busy {
                    PawLoadingView(title:"家族アルバムを確認中",compact:true)
                } else if client.error==nil {
                    VStack(alignment:.leading,spacing:12) {
                        Text("うちの子を登録して、家族を招待しよう 🐾").font(.headline)
                        Text("登録した子のアルバムに、家族を招待できます。")
                            .font(.subheadline).foregroundStyle(Theme.secondaryText)
                        NavigationLink {CloudFamilyView(registrationOnly:true)} label: {
                            Label("うちの子を登録",systemImage:"plus.circle.fill")
                                .frame(maxWidth:.infinity)
                        }.buttonStyle(CoralButtonStyle())
                    }.padding(16).frame(maxWidth:.infinity,alignment:.leading)
                        .background(.white,in:RoundedRectangle(cornerRadius:18))
                }
            }
            ForEach(client.pets) {pet in
                VStack(alignment:.leading,spacing:10) {
                    Text(pet.name).font(.headline)
                    NavigationLink {CloudMembersView(pet:pet,client:client)} label: {
                        Label("家族メンバー",systemImage:"person.2")
                    }
                    if pet.role=="owner" {
                        NavigationLink {FamilyInviteView(pet:pet,client:client)} label: {
                            Label("家族を招待",systemImage:"person.badge.plus")
                        }
                    } else {
                        Text("招待リンクは、アルバムを作った人から送ってもらってね。")
                            .font(.caption).foregroundStyle(Theme.secondaryText)
                    }
                }.frame(maxWidth:.infinity,alignment:.leading).padding(16)
                    .background(.white,in:RoundedRectangle(cornerRadius:18))
            }
            if let error=client.error {Text(error).font(.subheadline).foregroundStyle(.red)}
        }.padding(16)}.background(Theme.background).navigationTitle("アルバムの設定")
            .navigationBarTitleDisplayMode(.inline)
            .task {await client.performRefresh {try await client.loadPets()}}
    }
}

struct CloudMyPostsView:View {
    @ObservedObject var client:CloudFamilyClient
    @State private var posts:[CloudMyPublication]=[]
    @State private var images:[String:UIImage]=[:]
    @State private var loading=true
    @State private var loadError:String?
    @State private var previewRevision=0
    @State private var selectedPost:CloudMyPublication?
    @State private var deleteCandidate:CloudMyPublication?
    @State private var deleting=false
    @State private var videoID=""
    @State private var videoIsPrivate=false
    @State private var selectedMediaIndex=0
    private let columns=Array(repeating:GridItem(.flexible(),spacing:8),count:2)
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:8) {
                if loading && posts.isEmpty {PawLoadingView(title:"投稿を確認中",compact:true).frame(maxWidth:.infinity)}
                if !loading && posts.isEmpty && loadError == nil {
                    ContentUnavailableView("投稿はまだありません",systemImage:"photo.badge.plus",description:Text("投稿がサーバーに届くと、ここに表示されます"))
                }
                if let loadError {Text(loadError).font(.subheadline).foregroundStyle(.red).padding(.horizontal,12)}
                LazyVGrid(columns:columns,spacing:8) {
                    ForEach(posts) {post in
                        tile(post)
                            .task(id:post.id+"-"+String(previewRevision)) {await loadImage(post)}
                    }
                }
            }.padding(.horizontal,10).padding(.top,6)
        }.background(Theme.background).navigationTitle("自分の投稿").navigationBarTitleDisplayMode(.inline)
            .refreshable {await load()}
            .task {await load()}
            .onChange(of:client.currentUserID) {_,_ in posts=[];images=[:];selectedPost=nil}
            .sheet(item:$selectedPost) {post in
                NavigationStack {
                    ScrollView {VStack(alignment:.leading,spacing:14) {
                        mediaGallery(post)
                        Text(status(post.state)).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.actionText)
                        if !post.body.isEmpty {Text(post.body).font(.body)}
                        Button("投稿を削除",role:.destructive) {deleteCandidate=post}
                            .disabled(deleting).accessibilityIdentifier("my-post-delete-detail")
                    }.padding(16)}.navigationTitle("投稿").navigationBarTitleDisplayMode(.inline)
                        .toolbar {ToolbarItem(placement:.topBarTrailing) {Button("閉じる") {selectedPost=nil}}}
                }
                .sheet(isPresented:Binding(get:{!videoID.isEmpty},set:{if !$0 {videoID=""}})) {
                    NavigationStack {CloudVideoScreen(id:videoID,privateMedia:videoIsPrivate,client:client)
                        .navigationTitle("動画").toolbar {Button("閉じる") {videoID=""}}}
                }
            }
            .confirmationDialog("投稿を削除しますか？",isPresented:Binding(
                get:{deleteCandidate != nil},set:{if !$0 {deleteCandidate=nil}}),titleVisibility:.visible) {
                Button("投稿を削除",role:.destructive) {
                    if let post=deleteCandidate {Task {await delete(post)}}
                }
            } message: {Text("公開を取り消し、投稿一覧から削除します。")}
            .protectWhenInactive()
    }
    private func tile(_ post:CloudMyPublication)->some View {
        GeometryReader {geometry in
            ZStack(alignment:.bottomLeading) {
                preview(post).frame(width:geometry.size.width,height:geometry.size.height).clipped()
            }.frame(width:geometry.size.width,height:geometry.size.height)
                .clipShape(RoundedRectangle(cornerRadius:15))
                .contentShape(Rectangle()).onTapGesture {selectedMediaIndex=0;selectedPost=post}
                .overlay(alignment:.topTrailing) {
                    Button {deleteCandidate=post} label: {
                        Image(systemName:"ellipsis").font(.caption.bold()).foregroundStyle(.white)
                            .frame(width:30,height:30).background(.black.opacity(0.55),in:Circle())
                    }.accessibilityLabel(post.pet_name+"の投稿を削除")
                        .accessibilityIdentifier("my-post-delete-"+post.id)
                        .padding(5)
                }
                .overlay(alignment:.topLeading) {
                    if post.state != "published" {
                        Text(status(post.state)).font(.caption2.weight(.semibold)).foregroundStyle(.white)
                            .padding(.horizontal,7).padding(.vertical,4)
                            .background(Theme.accent,in:Capsule()).padding(7)
                    }
                }
                .overlay {if post.video_media?.isEmpty==false {
                    Image(systemName:"play.circle.fill").font(.system(size:38)).foregroundStyle(.white).allowsHitTesting(false)
                }}
        }.aspectRatio(1,contentMode:.fit)
            .accessibilityElement(children:.contain)
            .accessibilityIdentifier("my-post-"+post.id)
    }
    @ViewBuilder private func preview(_ post:CloudMyPublication)->some View {
        if let id=post.media.first ?? post.preview_photo,let image=images[id] {
            Image(uiImage:image).resizable().scaledToFill()
        } else {
            Rectangle().fill(Theme.accent.opacity(0.08))
                .overlay {Image(systemName:"photo").font(.title2).foregroundStyle(Theme.accent.opacity(0.6))}
        }
    }
    @ViewBuilder private func mediaGallery(_ post:CloudMyPublication)->some View {
        let media=post.media.isEmpty ? [post.preview_photo].compactMap{$0} : post.media
        if media.isEmpty {
            preview(post).frame(maxWidth:.infinity).frame(height:420).clipped()
        } else {
            VStack(spacing:8) {
                TabView(selection:$selectedMediaIndex) {
                    ForEach(Array(media.enumerated()),id:\.offset) {index,id in
                        ZStack {
                            if let image=images[id] {
                                Image(uiImage:image).resizable().scaledToFit()
                            } else {
                                Rectangle().fill(Theme.accent.opacity(0.08))
                                    .overlay {ProgressView().tint(Theme.accent)}
                            }
                            if post.video_media?.contains(id)==true {
                                Button {Task {await playVideo(in:post,publicID:id)}} label: {
                                    Image(systemName:"play.circle.fill").font(.system(size:56))
                                        .foregroundStyle(.white).shadow(radius:5)
                                }.accessibilityLabel("動画を再生")
                            }
                        }.frame(maxWidth:.infinity,maxHeight:.infinity)
                            .background(Color.black.opacity(0.06))
                            .tag(index)
                            .task(id:id) {await loadImage(post,mediaID:id)}
                    }
                }.tabViewStyle(.page(indexDisplayMode:.never)).frame(height:420)
                    .overlay(alignment:.topTrailing) {
                        if media.count>1 {
                            Text("\(selectedMediaIndex+1)/\(media.count)").font(.caption.bold())
                                .foregroundStyle(.white).padding(.horizontal,10).padding(.vertical,6)
                                .background(.black.opacity(0.55),in:Capsule()).padding(12)
                        }
                    }
                if media.count>1 {
                    HStack(spacing:6) {ForEach(media.indices,id:\.self) {index in
                        Circle().fill(index==selectedMediaIndex ? Theme.accent : Color(.systemGray4))
                            .frame(width:index==selectedMediaIndex ? 7 : 5,height:index==selectedMediaIndex ? 7 : 5)
                    }}.frame(height:10)
                }
            }.accessibilityIdentifier("my-post-media-carousel")
        }
    }
    private func status(_ state:String)->String {
        switch state {
        case "published":return "公開中"
        case "pending","processing":return "公開準備中"
        case "stopped":return "公開終了"
        default:return "状態を確認中"
        }
    }
    private func load() async {
        guard client.authenticated else {loading=false;posts=[];return}
        loading=true;loadError=nil
        do {
            let fresh=try await client.myPublications()
            posts=fresh;previewRevision += 1;loading=false
        } catch {loadError="投稿一覧を取得できませんでした。下に引いて再読み込みしてください。";loading=false}
    }
    private func loadImage(_ post:CloudMyPublication,mediaID:String?=nil) async {
        guard let id=mediaID ?? post.media.first ?? post.preview_photo,images[id]==nil else{return}
        let image=post.media.contains(id) ? try? await client.twinsImage(id) : try? await client.privatePhotoForDeviceSave(id)
        guard !Task.isCancelled,posts.contains(where:{$0.id==post.id}) else{return}
        if let image {images[id]=image}
    }
    private func playVideo(in post:CloudMyPublication,publicID:String) async {
        if post.state=="published",post.media.contains(publicID) {
            videoIsPrivate=false;videoID=publicID;return
        }
        do {
            guard let source=try await client.ownPostVideoSource(post.id) else {
                loadError="動画の準備が終わるまで、少し待ってください。";return
            }
            videoIsPrivate=true;videoID=source
        } catch {loadError="動画を開けませんでした。少し待って再試行してください。"}
    }
    private func delete(_ post:CloudMyPublication) async {
        guard !deleting else{return}
        deleting=true;loadError=nil
        do {
            try await client.stopPublication(id:post.id)
            posts.removeAll(where:{$0.id==post.id})
            selectedPost=nil;deleteCandidate=nil
        } catch {loadError="削除できませんでした。通信状態を確認して、もう一度お試しください。"}
        deleting=false
    }
}

struct CloudAlbumManagerView:View {
    @ObservedObject private var client=CloudFamilyClient.shared
    var body:some View {
        Group {
            if client.authenticated,client.pets.count==1,let pet=client.pets.first {
                CloudAlbumView(pet:pet,client:client)
            } else {petChooser}
        }.task {await client.restore();if client.authenticated {await client.performRefresh {try await client.loadPets()}}}
            .protectWhenInactive()
    }
    private var petChooser:some View {
        ScrollView {VStack(alignment:.leading,spacing:14) {
            HStack(spacing:8) {
                Image(systemName:"lock.fill").font(.caption)
                Text("家族内のみ・非公開").font(.subheadline.weight(.semibold))
            }.foregroundStyle(Theme.actionText).accessibilityElement(children:.combine)
            if client.authenticated {
                ForEach(client.pets) {pet in
                    NavigationLink {CloudAlbumView(pet:pet,client:client)} label: {
                        HStack(spacing:14) {
                            Text(pet.species=="cat" ? "🐱" : "🐶").font(.system(size:28))
                                .frame(width:58,height:58)
                                .background(Theme.accent.opacity(0.1),in:RoundedRectangle(cornerRadius:16))
                            VStack(alignment:.leading,spacing:4) {
                                Text(pet.name).font(.headline)
                                Text(pet.breed.isEmpty ? "写真を見る" : pet.breed)
                                    .font(.caption).foregroundStyle(Theme.secondaryText)
                            }
                            Spacer();Image(systemName:"chevron.right").font(.caption).foregroundStyle(Theme.secondaryText)
                        }.padding(14).frame(maxWidth:.infinity)
                            .background(.white,in:RoundedRectangle(cornerRadius:20))
                            .foregroundStyle(Theme.text)
                    }.accessibilityIdentifier("album-library-pet-"+pet.id)
                }
                if client.pets.isEmpty {ContentUnavailableView("まだアルバムがありません",systemImage:"pawprint",description:Text("犬猫がいなくてもMEFRIONを楽しめます"))}
                NavigationLink {CloudFamilyView(registrationOnly:true)} label: {Label("うちの子を追加",systemImage:"plus.circle.fill").frame(maxWidth:.infinity)}.buttonStyle(.bordered).tint(Theme.actionText)
            } else {
                ContentUnavailableView("思い出を、家族と一緒に",systemImage:"photo.on.rectangle.angled",description:Text("ログインすると、非公開アルバムを作れます"))
                NavigationLink("ログインしてアルバムを使う") {CloudFamilyView()}.buttonStyle(CoralButtonStyle()).frame(maxWidth:.infinity)
            }
            if client.busy {PawLoadingView(title:"アルバムを準備中",compact:true)}
            if let error=client.error {Text(error).foregroundStyle(.red)}
        }.padding(16)}.background(Theme.background).navigationTitle("アルバムに残す").navigationBarTitleDisplayMode(.inline)
    }
}

private struct CloudAlbumGalleryPhoto:Identifiable {
    let photo:CloudPhoto
    let petName:String
    var id:String {photo.id}
}

private struct AlbumGallerySkeleton:View {
    private let columns=Array(repeating:GridItem(.flexible(),spacing:10),count:2)
    var body:some View {
        LazyVGrid(columns:columns,spacing:10) {
            ForEach(0..<6,id:\.self) {_ in
                VStack(alignment:.leading,spacing:8) {
                    RoundedRectangle(cornerRadius:13).fill(Theme.accent.opacity(0.1)).aspectRatio(0.9,contentMode:.fit)
                    Capsule().fill(Theme.accent.opacity(0.1)).frame(width:80,height:10)
                }.padding(6).background(.white,in:RoundedRectangle(cornerRadius:18))
            }
        }.padding(.horizontal,12).accessibilityIdentifier("album-gallery-skeleton")
            .accessibilityLabel("アルバムを読み込み中")
    }
}

struct CloudAlbumLibraryView:View {
    @ObservedObject private var client=CloudFamilyClient.shared
    var refreshID=0
    @Environment(\.scenePhase) private var scenePhase
    @State private var photos:[CloudAlbumGalleryPhoto]=[]
    @State private var images:[String:UIImage]=[:]
    @State private var selected:CloudAlbumGalleryPhoto?
    @State private var loading=true
    @State private var message:String?
    @State private var reloadStamp=UUID()
    @State private var imageRevision=0
    @State private var selectedVideo=""
    private let columns=Array(repeating:GridItem(.flexible(),spacing:10),count:2)

    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:16) {
                if client.authenticated {
                    if !client.pets.isEmpty {VStack(alignment:.leading,spacing:10) {
                        Text("思い出あそび ♡").font(.headline).foregroundStyle(Theme.actionText)
                            .padding(.horizontal,16)
                        NavigationLink {CloudGestureAtlasView()} label: {
                            albumFeatureLink("しぐさ図鑑","かわいいを集めよう","pawprint.fill",
                                             Color(red:0.91,green:0.89,blue:1))
                        }.buttonStyle(.plain).padding(.horizontal,12)
                    }}
                    HStack(spacing:6) {
                        Image(systemName:"lock.fill").font(.caption)
                        Text("家族だけの思い出").font(.subheadline.weight(.semibold))
                    }.foregroundStyle(Theme.actionText).padding(.horizontal,16).padding(.top,4)
                    if loading && photos.isEmpty {
                        AlbumGallerySkeleton()
                    }
                    if let message {
                        Text(message).font(.subheadline).foregroundStyle(.red).padding(.horizontal,16)
                    }
                    if !loading && photos.isEmpty && message == nil {
                        ContentUnavailableView("まだ写真がありません",systemImage:"photo.on.rectangle.angled",description:Text("投稿タブから写真をアルバムに残せます"))
                    }
                    LazyVGrid(columns:columns,spacing:10) {
                        ForEach(photos) {entry in
                            Button {selected=entry} label: {
                                VStack(alignment:.leading,spacing:6) {
                                    GeometryReader {geometry in
                                        galleryImage(entry.id)
                                            .frame(width:geometry.size.width,height:geometry.size.height).clipped()
                                            .clipShape(RoundedRectangle(cornerRadius:13))
                                    }.aspectRatio(0.9,contentMode:.fit)
                                        .overlay {if entry.photo.media_kind=="video" {Image(systemName:"play.circle.fill").font(.system(size:37)).foregroundStyle(.white).shadow(radius:4)}}
                                    HStack(spacing:4) {
                                        Text(entry.petName).font(.caption.weight(.semibold)).lineLimit(1)
                                        Spacer(minLength:0)
                                        if let created=entry.photo.created_at ?? entry.photo.captured {
                                            Text(PostTime.label(created)).font(.caption2).foregroundStyle(Theme.secondaryText).lineLimit(1)
                                        }
                                    }.padding(.horizontal,2)
                                }.padding(6).background(.white,in:RoundedRectangle(cornerRadius:18))
                                    .overlay(alignment:.top) {
                                        RoundedRectangle(cornerRadius:4).fill(Theme.accent.opacity(0.18))
                                            .frame(width:46,height:11).rotationEffect(.degrees(-8)).offset(y:-3)
                                    }
                                    .shadow(color:Theme.accent.opacity(0.09),radius:5,y:3)
                            }.buttonStyle(.plain).foregroundStyle(Theme.text)
                                .accessibilityLabel(entry.petName+"のアルバム写真")
                                .accessibilityIdentifier("cloud-album-gallery-photo-"+entry.id)
                                .task(id:entry.id+"-"+String(imageRevision)) {await loadImage(entry.id)}
                        }
                    }.padding(.horizontal,12)
                } else if loading {
                    PawLoadingView(title:"アルバムを開いています",compact:true).frame(maxWidth:.infinity)
                } else {
                    ContentUnavailableView("思い出を、家族と一緒に",systemImage:"photo.on.rectangle.angled",description:Text("ログインすると家族だけの写真を見られます"))
                    NavigationLink("ログインしてアルバムを使う") {CloudFamilyView()}
                        .buttonStyle(CoralButtonStyle()).frame(maxWidth:.infinity).padding(.horizontal,16)
                }
            }.padding(.bottom,24)
        }.background(Theme.background).navigationTitle("アルバム").navigationBarTitleDisplayMode(.inline)
            .refreshable {await reload()}
            .task(id:refreshID) {await client.restore();await reload()}
            .onChange(of:client.currentUserID) {_,_ in photos=[];images=[:];selected=nil;Task {await reload()}}
            .onChange(of:scenePhase) {_,phase in
                if phase == .active {Task {await reload()}}
            }
            .overlay(alignment:.top) {
                if loading && !photos.isEmpty {
                    Label("思い出を更新中 🐾",systemImage:"arrow.clockwise")
                        .font(.caption.bold()).foregroundStyle(Theme.actionText)
                        .padding(.horizontal,14).padding(.vertical,8)
                        .background(.white,in:Capsule())
                        .shadow(color:Theme.accent.opacity(0.12),radius:8,y:3)
                        .padding(.top,8)
                        .accessibilityIdentifier("album-gallery-refreshing")
                }
            }
            .sheet(item:$selected) {entry in
                NavigationStack {
                    ScrollView {
                        VStack(alignment:.leading,spacing:12) {
                            if let image=images[entry.id] {
                                Image(uiImage:image).resizable().scaledToFit().frame(maxWidth:.infinity)
                                    .clipShape(RoundedRectangle(cornerRadius:18))
                            } else {
                                galleryImage(entry.id).frame(maxWidth:.infinity).frame(height:320).clipped()
                            }
                            if entry.photo.media_kind=="video" {
                                Button {selectedVideo=entry.id} label: {Label("動画を再生",systemImage:"play.circle.fill")}
                                    .buttonStyle(CoralButtonStyle())
                            }
                            Text(entry.petName).font(.headline)
                            if !entry.photo.title.isEmpty {Text(entry.photo.title)}
                            if let created=entry.photo.created_at ?? entry.photo.captured {Text("追加："+PostTime.label(created)).font(.caption).foregroundStyle(Theme.secondaryText)}
                        }.padding(16)
                    }.navigationTitle("思い出").navigationBarTitleDisplayMode(.inline)
                        .toolbar {ToolbarItem(placement:.topBarTrailing) {Button("閉じる") {selected=nil}}}
                }.task {await loadImage(entry.id)}
                    .sheet(isPresented:Binding(get:{!selectedVideo.isEmpty},set:{if !$0 {selectedVideo=""}})) {
                        NavigationStack {CloudVideoScreen(id:selectedVideo,privateMedia:true,client:client)
                            .navigationTitle("動画").toolbar {Button("閉じる") {selectedVideo=""}}}
                    }
            }.protectWhenInactive()
    }

    @ViewBuilder private func galleryImage(_ id:String)->some View {
        if let image=images[id] {Image(uiImage:image).resizable().scaledToFill().accessibilityIdentifier("cloud-album-gallery-image-"+id)}
        else {Rectangle().fill(Theme.accent.opacity(0.07))
            .overlay {Image(systemName:"heart.text.square").font(.title2).foregroundStyle(Theme.accent.opacity(0.65))}}
    }
    private func albumFeatureLink(_ title:String,_ subtitle:String,_ symbol:String,_ color:Color)->some View {
        VStack(alignment:.leading,spacing:7) {
            Image(systemName:symbol).font(.system(size:25,weight:.medium))
                .frame(width:48,height:48).background(.white.opacity(0.72),in:Circle())
            Spacer(minLength:0)
            Text(title).font(.subheadline.bold()).lineLimit(1)
            Text(subtitle).font(.caption2).lineLimit(2)
        }.foregroundStyle(Theme.actionText).frame(maxWidth:.infinity,alignment:.leading)
            .frame(height:128).padding(14).background(color,in:RoundedRectangle(cornerRadius:20))
    }
    private func reload() async {
        let stamp=UUID();reloadStamp=stamp
        guard client.authenticated else {loading=false;photos=[];images=[:];return}
        let actor=client.currentUserID
        loading=true;message=nil
        do {
            try await client.loadPets()
            var gathered:[CloudAlbumGalleryPhoto]=[]
            for pet in client.pets {
                try Task.checkCancellation()
                let records=try await client.albumPhotos(pet:pet.id)
                gathered += records.map {CloudAlbumGalleryPhoto(photo:$0,petName:pet.name)}
            }
            guard !Task.isCancelled,stamp==reloadStamp,actor==client.currentUserID else {return}
            photos=gathered.sorted {($0.photo.created_at ?? $0.photo.captured ?? "") > ($1.photo.created_at ?? $1.photo.captured ?? "")}
            let validIDs=Set(photos.map(\.id))
            images=images.filter {validIDs.contains($0.key)}
            imageRevision &+= 1
        } catch {if !Task.isCancelled,stamp==reloadStamp,actor==client.currentUserID {message="写真を読み込めませんでした。下に引いて再試行してください。"}}
        if stamp==reloadStamp {loading=false}
    }
    private func loadImage(_ id:String) async {
        guard images[id]==nil,photos.contains(where:{$0.id==id}) else{return}
        let actor=client.currentUserID
        guard let image=try? await client.privatePhotoForDeviceSave(id),
              actor==client.currentUserID,scenePhase == .active,photos.contains(where:{$0.id==id}) else{return}
        images[id]=image
    }
}

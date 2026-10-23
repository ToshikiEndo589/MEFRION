import SwiftUI
import AVKit

private struct SkeletonLine:View {
    var width:CGFloat?=nil
    var height:CGFloat=12
    var body:some View {
        RoundedRectangle(cornerRadius:height/2)
            .fill(LinearGradient(colors:[Theme.accent.opacity(0.065),Theme.accent.opacity(0.13),Theme.accent.opacity(0.065)],startPoint:.leading,endPoint:.trailing))
            .frame(width:width,height:height)
    }
}

private struct FeedMediaSkeleton:View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var glowing=false
    var body:some View {
        Rectangle().fill(LinearGradient(colors:[Color(red:1,green:0.965,blue:0.96),Color(red:1,green:0.91,blue:0.93),Color(red:1,green:0.965,blue:0.96)],startPoint:glowing ? .topTrailing : .bottomLeading,endPoint:glowing ? .bottomLeading : .topTrailing))
            .overlay {
                Image(systemName:"pawprint.fill").font(.system(size:38,weight:.ultraLight))
                    .foregroundStyle(Theme.accent.opacity(glowing ? 0.24 : 0.12))
            }
            .accessibilityLabel("写真を読み込み中")
            .onAppear {if !reduceMotion {withAnimation(.easeInOut(duration:1.3).repeatForever(autoreverses:true)) {glowing=true}}}
    }
}

private struct PublicFeedSkeleton:View {
    var body:some View {
        LazyVStack(spacing:4) {
            ForEach(0..<2,id:\.self) {_ in
                VStack(alignment:.leading,spacing:0) {
                    HStack(spacing:10) {
                        Circle().fill(Theme.accent.opacity(0.1)).frame(width:36,height:36)
                        VStack(alignment:.leading,spacing:7) {SkeletonLine(width:104);SkeletonLine(width:68,height:9)}
                        Spacer()
                        SkeletonLine(width:66,height:24)
                    }.padding(.horizontal,12).frame(height:56)
                    FeedMediaSkeleton().aspectRatio(4.0/5.0,contentMode:.fit)
                    HStack(spacing:11) {
                        Circle().fill(Theme.accent.opacity(0.1)).frame(width:30,height:30)
                        Circle().fill(Theme.accent.opacity(0.1)).frame(width:30,height:30)
                        Spacer()
                        Circle().fill(Theme.accent.opacity(0.1)).frame(width:30,height:30)
                    }.padding(.horizontal,14).frame(height:48)
                    SkeletonLine(width:220).padding(.horizontal,14).padding(.bottom,8)
                }.background(.white)
            }
        }.accessibilityElement(children:.ignore).accessibilityLabel("公開投稿を読み込み中")
    }
}

private struct VideoViewportPreferenceKey:PreferenceKey {
    static var defaultValue:[String:CGFloat]=[:]
    static func reduce(value:inout [String:CGFloat],nextValue:()->[String:CGFloat]) {
        value.merge(nextValue(),uniquingKeysWith:{$1})
    }
}

private struct InlineAutoplayVideo:View {
    let id:String
    let poster:UIImage?
    let active:Bool
    @ObservedObject var client:CloudFamilyClient
    @Environment(\.scenePhase) private var scenePhase
    @State private var player:AVPlayer?
    @State private var file:URL?
    @State private var muted=false
    @State private var paused=false
    @State private var failed=false
    var body:some View {
        ZStack {
            Color.black
            if let poster {Image(uiImage:poster).resizable().scaledToFit()}
            if let player {InlinePlayerSurface(player:player)}
            if failed {
                Button {Task {await load()}} label: {Label("動画を再読み込み",systemImage:"arrow.clockwise")
                    .font(.caption.bold()).padding(12).background(.black.opacity(0.7),in:Capsule())}
                    .foregroundStyle(.white)
            } else if player == nil {
                ProgressView().tint(.white).padding(12).background(.black.opacity(0.45),in:Circle())
            }
            if player != nil {
                Button {paused.toggle();paused ? player?.pause() : player?.play()} label: {
                    ZStack {
                        Color.clear
                        if paused {
                            Image(systemName:"play.fill").font(.system(size:20)).foregroundStyle(.white)
                                .frame(width:48,height:48).background(.black.opacity(0.55),in:Circle())
                        }
                    }.frame(maxWidth:.infinity,maxHeight:.infinity).contentShape(Rectangle())
                }.accessibilityLabel(paused ? "動画を再生" : "動画を一時停止")
            }
        }.overlay(alignment:.bottomTrailing) {
            if player != nil {
                Button {muted.toggle();player?.isMuted=muted} label: {
                    Image(systemName:muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.caption.bold()).foregroundStyle(.white)
                        .frame(width:36,height:36).background(.black.opacity(0.5),in:Circle())
                }.accessibilityLabel(muted ? "音を出す" : "音を消す").padding(12)
            }
        }
        .task(id:id) {await load()}
        .onChange(of:scenePhase) {_,phase in if phase == .active && active && !paused {player?.play()} else {player?.pause()}}
        .onChange(of:active) {_,visible in if visible && scenePhase == .active && !paused {player?.play()} else {player?.pause()}}
        .onReceive(NotificationCenter.default.publisher(for:.AVPlayerItemDidPlayToEndTime)) {note in
            if let item=note.object as? AVPlayerItem,item === player?.currentItem {
                player?.seek(to:.zero);if scenePhase == .active && active && !paused {player?.play()}
            }
        }
        .onDisappear {player?.pause();player=nil;file=nil}
    }
    private func load() async {
        failed=false
        do {
            let url=try await client.videoFile(id,privateMedia:false)
            guard !Task.isCancelled else {try? FileManager.default.removeItem(at:url);return}
            file=url
            let next=AVPlayer(url:url);next.isMuted=muted;next.actionAtItemEnd = .none
            player=next
            if scenePhase == .active && active && !paused {next.play()}
        } catch {if !Task.isCancelled {failed=true}}
    }
}

private struct InlinePlayerSurface:UIViewRepresentable {
    let player:AVPlayer
    final class PlayerView:UIView {
        override static var layerClass:AnyClass {AVPlayerLayer.self}
        var playerLayer:AVPlayerLayer {layer as! AVPlayerLayer}
    }
    func makeUIView(context:Context)->PlayerView {
        let view=PlayerView();view.backgroundColor = .black
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.player=player
        return view
    }
    func updateUIView(_ view:PlayerView,context:Context) {view.playerLayer.player=player}
}

struct CloudVideoScreen:View {
    let id:String
    let privateMedia:Bool
    @ObservedObject var client:CloudFamilyClient
    @State private var player:AVPlayer?
    @State private var file:URL?
    @State private var errorMessage:String?
    var body:some View {
        ZStack {
            Color.black
            if let player {VideoPlayer(player:player)}
            else if let errorMessage {
                VStack(spacing:12) {
                    Text(errorMessage).foregroundStyle(.white)
                    Button("再試行") {Task {await load()}}.buttonStyle(.borderedProminent)
                }
            } else {PawLoadingView(title:"動画を準備中",compact:true)}
        }.task(id:id) {await load()}
            .onAppear {if !privateMedia {client.setPublicVideoVisible(id,true)}}
            .onDisappear {player?.pause();if privateMedia,let file {try? FileManager.default.removeItem(at:file)};player=nil;file=nil;if !privateMedia {client.setPublicVideoVisible(id,false)}}
    }
    private func load() async {
        errorMessage=nil
        do {
            let url=try await client.videoFile(id,privateMedia:privateMedia)
            guard !Task.isCancelled else {try? FileManager.default.removeItem(at:url);return}
            file=url;player=AVPlayer(url:url);player?.play()
        } catch {errorMessage="動画を再生できませんでした。通信状態を確認してください。"}
    }
}

struct CloudPublicationComposer:View {
    let pet:CloudPet
    let photos:[CloudPhoto]
    let images:[String:UIImage]
    @ObservedObject var client:CloudFamilyClient
    @Environment(\.dismiss) private var dismiss
    @State private var selected:Set<String>=[]
    @State private var petTags:Set<String>=[]
    @State private var bodyText=""
    @State private var providerConsent=false
    @State private var publicationConsent=false
    @State private var key=UUID()
    @State private var publication:CloudPublication?
    @State private var withdrawn=false
    @FocusState private var editingBody:Bool
    var body:some View {
        ScrollView {VStack(alignment:.leading,spacing:16) {
            Text("写真を選ぶ").font(.title3.bold())
            if let photo=photos.first(where:{selected.contains($0.id)}) ?? photos.first,let image=images[photo.id] {PhotoHero(image:image,height:270).clipShape(RoundedRectangle(cornerRadius:18))}
            VStack(alignment:.leading,spacing:12) {
                Text("投稿する写真・動画 · 最大10件").font(.subheadline.weight(.semibold))
                ScrollView(.horizontal,showsIndicators:false) {HStack(spacing:10) {
                    ForEach(photos) {photo in
                        Button {if selected.contains(photo.id) {selected.remove(photo.id)} else {selected.insert(photo.id)}} label: {
                            VStack(spacing:5) {
                                if let image=images[photo.id] {Image(uiImage:image).resizable().scaledToFill().frame(width:78,height:78).clipped().clipShape(RoundedRectangle(cornerRadius:10)).overlay(alignment:.topTrailing) {Image(systemName:selected.contains(photo.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(Theme.actionText).padding(4)}}
                                Text(photo.captured ?? "日付不明").font(.caption2)
                            }
                        }.buttonStyle(.borderless).disabled(publication != nil || (selected.count==10 && !selected.contains(photo.id))).accessibilityIdentifier("cloud-publication-select").accessibilityLabel(selected.contains(photo.id) ? "選択解除" : "選択")
                    }
                }}
            }.padding(14).background(.white,in:RoundedRectangle(cornerRadius:18))
            VStack(alignment:.leading,spacing:12) {
                Text(pet.name+"の投稿").font(.headline)
                TextField("ひとことを書く（任意）",text:$bodyText,axis:.vertical).focused($editingBody).disabled(publication != nil).accessibilityIdentifier("cloud-publication-body")
                Text("\(bodyText.count) / 500文字").font(.caption).foregroundStyle(bodyText.count>500 ? .red : .secondary)
            }.padding(14).background(.white,in:RoundedRectangle(cornerRadius:18))
            if !client.pets.filter({$0.role=="owner" && $0.id != pet.id}).isEmpty {
                VStack(alignment:.leading,spacing:10) {
                Text("一緒に写っている子").font(.subheadline.weight(.semibold))
                ForEach(client.pets.filter{$0.role=="owner" && $0.id != pet.id}) {other in Toggle(other.name,isOn:Binding(get:{petTags.contains(other.id)},set:{if $0 {petTags.insert(other.id)} else {petTags.remove(other.id)}}))}
                }.padding(14).background(.white,in:RoundedRectangle(cornerRadius:18)).disabled(publication != nil)
            }
            VStack(alignment:.leading,spacing:12) {
                Label("公開する前に確認",systemImage:"lock.shield").font(.headline)
                Text("選んだ写真だけを公開用に加工します。家族アルバムの元写真は公開しません。").font(.caption).foregroundStyle(.secondary)
                Toggle("自分が提供した選択写真のSNS利用に同意する",isOn:$providerConsent).disabled(publication != nil).accessibilityIdentifier("cloud-provider-consent")
                Toggle("このPetのプロフィールを公開し、選択写真の投稿に同意する",isOn:$publicationConsent).disabled(publication != nil).accessibilityIdentifier("cloud-publication-consent")
                Text("家族が提供した写真には、提供者本人のSNS同意が必要です。").font(.caption).foregroundStyle(.secondary)
                if publication==nil {
                    Button("投稿する") {
                        let chosen=photos.filter{selected.contains($0.id)};let text=bodyText;let requestKey=key
                        Task {await client.perform {
                        for photo in chosen {
                            if photo.media_kind=="video" {
                                let file=try await client.videoFile(photo.id,privateMedia:true)
                                defer {try? FileManager.default.removeItem(at:file)}
                                let duration:Double
                                if let stored=photo.duration_seconds {duration=stored}
                                else {duration=CMTimeGetSeconds(try await AVURLAsset(url:file).load(.duration))}
                                try await PetPostValidator.shared.validateVideo(file,duration:duration)
                            } else {
                                guard let jpeg=images[photo.id]?.jpegData(compressionQuality:0.9) else {throw PetPostValidationError.unreadable}
                                try await PetPostValidator.shared.validatePhoto(jpeg)
                            }
                        }
                        try await client.loadProvidedPhotos()
                        for photo in chosen where photo.mine {
                            if !client.providedPhotos.contains(where:{$0.id==photo.id && $0.sns}) {try await client.consent(photo:photo.id,purpose:"sns",allowed:true)}
                        }
                        try await client.setPublicProfile(pet:pet.id,enabled:true,explicit:true)
                        publication=try await client.requestPublication(pet:pet.id,photos:chosen.map(\.id),body:text,key:requestKey,tags:Array(petTags))
                    }}}.buttonStyle(CoralButtonStyle()).frame(maxWidth:.infinity).disabled(client.busy || selected.isEmpty || selected.count>10 || bodyText.count>500 || !providerConsent || !publicationConsent).accessibilityIdentifier("cloud-request-publication")
                }
            }.padding(14).background(.white,in:RoundedRectangle(cornerRadius:18))
            if let publication {
                VStack(alignment:.leading,spacing:8) {
                    Text(withdrawn || publication.state=="stopped" ? "公開を停止しました" : publication.state=="published" ? "公開済み" : "公開用画像を処理待ちです").accessibilityIdentifier("cloud-publication-status")
                    Text("写真の準備と公開範囲の確認が終わると、おすすめに表示されます。").font(.caption)
                    if !withdrawn {Button("この投稿の公開を取り消す",role:.destructive) {Task {await client.perform {try await client.stopPublication(id:publication.id);withdrawn=true}}}.accessibilityIdentifier("cloud-stop-publication")}
                }.padding(14).background(.white,in:RoundedRectangle(cornerRadius:18))
            }
            if client.busy {PawLoadingView(title:"投稿を準備中",compact:true)}
            if let error=client.error {Text(error).foregroundStyle(.red)}
        }.padding(16)}.background(Theme.background).disabled(client.busy).scrollDismissesKeyboard(.interactively).navigationTitle("新規投稿").toolbar {
            ToolbarItem(placement:.cancellationAction) {Button("閉じる") {dismiss()}}
            ToolbarItemGroup(placement:.keyboard) {Spacer();Button("入力を完了") {editingBody=false}.accessibilityIdentifier("cloud-publication-done")}
        }
        .protectWhenInactive()
        .onChange(of:client.authenticated) {_,active in if !active {dismiss()}}
        .onChange(of:bodyText) {_,_ in if publication==nil {key=UUID()} }
        .onChange(of:selected) {_,_ in if publication==nil {key=UUID()} }
        .onChange(of:petTags) {_,_ in if publication==nil {key=UUID()} }
    }
}

struct CloudDiscoveryView:View {
    @ObservedObject var client:CloudFamilyClient
    var integrated:Bool
    var homeRefreshID:Int
    @Environment(\.rootTabSwipe) private var moveRootTab
    var detail:String?
    private var preview:CloudPetRecentPost?
    private var profile:CloudPublicPet?
    @Environment(\.scenePhase) private var scenePhase
    private struct Continuation {let post:String;let action:String}
    @State private var continuation:Continuation?
    @State private var authenticating=false
    @State private var reportPost:CloudPublicPost?
    @State private var blockPost:CloudPublicPost?
    @State private var commentPost:CloudPublicPost?
    @State private var mode="all"
    @State private var query=""
    @State private var species="all"
    @State private var loadingNext=false
    @State private var loadedFeedIdentity:String?
    @State private var initialFeedLoading=true
    @State private var homeRefreshInProgress=false
    @State private var pullRefreshInProgress=false
    @State private var expandedPostIDs:Set<String>=[]
    @State private var videoID=""
    @State private var activeVideoMedia:String?
    @State private var mediaPageByPost:[String:Int]=[:]
    @State private var carouselSwipeInProgress=false
    @State private var detailPost:CloudPublicPost?
    @State private var detailImages:[String:UIImage]=[:]
    @State private var detailLoading=false
    init(client:CloudFamilyClient,integrated:Bool=false,homeRefreshID:Int=0,detail:String?=nil,initialMode:String="all",preview:CloudPetRecentPost?=nil,profile:CloudPublicPet?=nil,previewImage:UIImage?=nil) {
        self.client=client;self.integrated=integrated;self.homeRefreshID=homeRefreshID;self.detail=detail;self.preview=preview;self.profile=profile
        _mode=State(initialValue:initialMode)
        if let preview,let profile {
            _detailPost=State(initialValue:CloudPublicPost(id:preview.id,pet_id:profile.id,name:profile.name,species:profile.species,breed:profile.breed ?? "",body:preview.body,kind:"post",media:preview.media,likes:0,comments:0,liked:false,saved:false,following:false))
        }
        if let id=preview?.media.first,let previewImage {_detailImages=State(initialValue:[id:previewImage])}
    }
    var body:some View {
        ScrollViewReader {scrollProxy in ScrollView {LazyVStack(alignment:.leading,spacing:integrated || mode=="liked" ? 4 : 18) {
            Color.clear.frame(height:0).id("cloud-home-top")
            if integrated {
                CompactHomeHeader {NavigationLink {CloudDiscoveryView(client:client)} label: {Image(systemName:"magnifyingglass").frame(width:44,height:44)}.accessibilityLabel("検索").accessibilityIdentifier("home-search");NavigationLink {NotificationHubView()} label: {Image(systemName:"bell").frame(width:44,height:44)}.accessibilityLabel("通知")}.padding(.horizontal,16)
                HStack {
                    Button {mode="all"} label: {Label("おすすめ",systemImage:"pawprint.fill").frame(maxWidth:.infinity,minHeight:44).contentShape(Rectangle())}.foregroundStyle(mode=="all" ? Theme.actionText : Theme.text).accessibilityIdentifier("home-recommended").accessibilityValue(mode=="all" ? "選択中" : "未選択")
                    Button {mode="following"} label: {Label("フォロー中",systemImage:"person.2").frame(maxWidth:.infinity,minHeight:44).contentShape(Rectangle())}.foregroundStyle(mode=="following" ? Theme.actionText : Theme.text).accessibilityIdentifier("home-following").accessibilityValue(mode=="following" ? "選択中" : "未選択")
                }.font(.caption.weight(.semibold)).dynamicTypeSize(...DynamicTypeSize.xxxLarge).frame(minHeight:44).padding(.horizontal,16)
                HStack(spacing:0) {Capsule().fill(mode=="all" ? Theme.accent : .clear);Capsule().fill(mode=="following" ? Theme.accent : .clear)}.frame(height:2).padding(.horizontal,16)
                if !client.authenticated && mode=="following" {NavigationLink("ログインしてフォロー・投稿する") {CloudFamilyView()}.padding(.horizontal,16)}
            }
            if client.authenticated && !integrated && detail==nil && mode != "liked" {
                HStack {NavigationLink("ブロックした相手") {CloudBlockedPetsView(client:client)};Spacer();NavigationLink("通知") {CloudSocialNotificationsView(client:client)}}
                if mode != "liked" {
                    Picker("投稿一覧",selection:$mode) {Text("おすすめ").tag("all");Text("フォロー中").tag("following");Text("保存済み").tag("saved")}.pickerStyle(.segmented)
                }
            }
            if !integrated && detail==nil && mode != "liked" {
            HStack {TextField("公開Petの名前・種類を検索",text:$query).textFieldStyle(.roundedBorder).accessibilityIdentifier("cloud-search-query");Button("検索") {Task {await client.perform {try await client.loadPublicFeed(mode:mode,query:query,species:species)}}}.disabled(client.busy || query.count>100)}
            Picker("犬・猫",selection:$species) {Text("すべて").tag("all");Text("犬").tag("dog");Text("猫").tag("cat")}.pickerStyle(.segmented)
            Button("最新の公開投稿を取得") {Task {await client.perform {try await client.loadPublicFeed(mode:mode,query:query,species:species)}}}
            }
            if let continuation,client.authenticated {
                VStack(alignment:.leading,spacing:8) {
                    Text("認証済みです。元の投稿への操作を確認してください。").accessibilityIdentifier("auth-resume-ready")
                    if let post=client.publicPosts.first(where:{$0.id==continuation.post}) {
                        Text("対象："+displayName(post))
                        Button("元の操作を確認して続ける") {resume(post:post,action:continuation.action)}.disabled(client.busy).accessibilityIdentifier("auth-resume-confirm")
                    } else {Text("元の投稿は公開終了などで表示できません。操作を中止します。");Button("操作を破棄") {self.continuation=nil}}
                }.padding().background(Theme.accent.opacity(0.07)).clipShape(RoundedRectangle(cornerRadius:14))
            }
            if let error=client.error {Text(error).foregroundStyle(.red)}
            if detail==nil && client.publicPosts.isEmpty && !client.busy && !initialFeedLoading {
                VStack(spacing:8) {
                    ContentUnavailableView(
                        mode=="liked" ? "いいねした投稿はまだありません" : !query.isEmpty || species != "all" ? "一致する投稿がありません" : mode=="following" ? "フォロー中の投稿はまだありません" : "公開された投稿はまだありません",
                        systemImage:mode=="liked" ? "heart" : "pawprint",
                        description:Text(mode=="liked" ? "お気に入りの投稿にいいねすると、ここに並びます。" : mode=="all" && query.isEmpty && species=="all" ? "あなたのペットとの毎日も、ここから共有できます。" : "検索条件やフォロー中のPetを確認してください。")
                    )
                    if integrated && mode=="all" {
                        NavigationLink {CloudUnifiedComposer()} label: {Label("投稿を始める",systemImage:"plus.circle.fill")}
                            .buttonStyle(CoralButtonStyle()).padding(.horizontal,36)
                    }
                }.frame(maxWidth:.infinity).padding(.vertical,32)
            }
            if !integrated && detail==nil && mode=="all" {
                Text("おすすめのペットたち").font(.headline)
                ScrollView(.horizontal,showsIndicators:false) {HStack(spacing:18) {ForEach(client.publicPosts) {post in
                    NavigationLink {CloudDiscoveryView(client:client,detail:post.id)} label: {VStack {PhotoHero(image:post.media.first.flatMap{client.publicImages[$0]},height:64).frame(width:64).clipShape(Circle());Text(displayName(post)).font(.caption)}}
                        .onAppear {if let media=post.media.first {client.setPublicImageVisible(media,true)}}
                        .onDisappear {if let media=post.media.first {client.setPublicImageVisible(media,false)}}
                }}}
                LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible()),GridItem(.flexible())],spacing:6) {
                    ForEach(client.publicPosts) {post in NavigationLink {CloudDiscoveryView(client:client,detail:post.id)} label: {
                        PhotoHero(image:post.media.first.flatMap{client.publicImages[$0]},height:130).overlay(alignment:.bottomLeading) {Label("\(post.likes)",systemImage:post.liked ? "heart.fill" : "heart").font(.caption).foregroundStyle(.white).padding(8)}
                    }.accessibilityIdentifier("cloud-open-post-"+post.id)
                        .onAppear {if let media=post.media.first {client.setPublicImageVisible(media,true)}}
                        .onDisappear {if let media=post.media.first {client.setPublicImageVisible(media,false)}}
                    }
                }
            }
            visiblePostRows
            if detail==nil && client.publicPosts.isEmpty && (initialFeedLoading || client.busy) {
                PublicFeedSkeleton().accessibilityIdentifier("public-feed-skeleton")
            }
            if detail==nil && client.hasMorePublicPosts {
                PawLoadingView(title:"次の投稿を準備中",compact:true).padding(.vertical,16)
                    .id(integrated ? "home-next" : "search-next-\(client.publicPosts.count)")
                    .onAppear {if !integrated {loadNextPage()}}
                    .accessibilityIdentifier("feed-next-page-loader")
            }
            if detail != nil && !detailLoading && detailPost == nil && !client.publicPosts.contains(where:{$0.id==detail}) {ContentUnavailableView("この投稿は表示できません",systemImage:"eye.slash",description:Text("公開終了・権限・最新の表示状態を確認してください。"))}
        }.padding(.horizontal,integrated || mode=="liked" || detail != nil ? 0 : 16).padding(.top,integrated || mode=="liked" || detail != nil ? 0 : 16).padding(.bottom,8)}.background(integrated || mode=="liked" || detail != nil ? Color.white : Theme.background)
        .onPreferenceChange(VideoViewportPreferenceKey.self) {positions in
            activeVideoMedia=positions.min(by:{$0.value<$1.value})?.key
        }
        .onChange(of:homeRefreshID) {_,_ in
            guard integrated else {return}
            withAnimation(.easeOut(duration:0.22)) {scrollProxy.scrollTo("cloud-home-top",anchor:.top)}
            guard !homeRefreshInProgress,!client.publicFeedIsRevalidating else {return}
            homeRefreshInProgress=true
            Task {
                if mode=="following" && !client.authenticated {client.clearPublicViews()}
                else {await client.performRefresh {try await client.loadPublicFeed(mode:mode,query:query,species:species,rotateRecommendations:mode=="all")}}
                homeRefreshInProgress=false
            }
        }
        }
        .overlay {
            if detail != nil && detailPost == nil && detailLoading {
                PawLoadingView(title:"投稿を準備中")
                    .padding(24).background(Theme.background.opacity(0.96),in:RoundedRectangle(cornerRadius:24))
                    .frame(maxWidth:260).allowsHitTesting(false)
                    .accessibilityIdentifier("public-feed-loading")
            }
        }
        .overlay(alignment:.top) {
            if (homeRefreshInProgress || pullRefreshInProgress) && !client.publicPosts.isEmpty {
                Label("新しい出会いを探し中 🐾",systemImage:"arrow.clockwise")
                    .font(.caption.bold()).foregroundStyle(Theme.actionText)
                    .padding(.horizontal,16).padding(.vertical,10)
                    .background(.white,in:Capsule())
                    .overlay(Capsule().stroke(Theme.accent.opacity(0.28),lineWidth:1))
                    .shadow(color:Theme.accent.opacity(0.13),radius:10,y:3)
                    .padding(.top,8)
                    .accessibilityIdentifier("home-refreshing")
            }
        }
        .navigationTitle(integrated ? "MEFRION" : detail != nil ? "投稿 ♡" : mode=="liked" ? "いいねした投稿" : "検索").navigationBarTitleDisplayMode(.inline).toolbar(integrated ? .hidden : .visible,for:.navigationBar)
        .modifier(HorizontalTabSwipe(enabled:integrated) {towardRight in
            guard !carouselSwipeInProgress else {carouselSwipeInProgress=false;return}
            let next=towardRight ? "following" : "all"
            if mode==next {moveRootTab(towardRight)} else {mode=next}
        })
        .refreshable {
            pullRefreshInProgress=true
            defer {pullRefreshInProgress=false}
            let selectedMode=mode,selectedQuery=query,selectedSpecies=species
            let shouldRotate=integrated && selectedMode=="all"
            // SwiftUI can cancel the refreshable closure when the feed redraws.
            // Keep the user-initiated fetch alive so a cancelled view task cannot
            // abandon the request after the pull gesture.
            let refresh=Task { @MainActor in
                await client.performRefresh {
                    try await client.loadPublicFeed(mode:selectedMode,query:selectedQuery,species:selectedSpecies,rotateRecommendations:shouldRotate)
                }
            }
            await refresh.value
        }
        .sheet(isPresented:$authenticating,onDismiss:{if !client.authenticated {continuation=nil} else {Task {await client.perform {try await client.loadPublicFeed(mode:mode,query:query,species:species)}}}}) {AuthenticationSheet(client:client)}
        .sheet(item:$commentPost,onDismiss:{if detail != nil {Task {await loadDetail()}}}) {post in NavigationStack {CloudCommentsView(post:post,client:client)}}
        .sheet(isPresented:Binding(get:{!videoID.isEmpty},set:{if !$0 {videoID=""}})) {
            NavigationStack {
                CloudVideoScreen(id:videoID,privateMedia:false,client:client)
                    .navigationTitle("動画").navigationBarTitleDisplayMode(.inline)
                    .toolbar {Button("閉じる") {videoID=""}}
            }
        }
        .onChange(of:species) {_,_ in Task {await client.performRefresh {try await client.loadPublicFeed(mode:mode,query:query,species:species)}}}
        .onChange(of:mode) {_,_ in initialFeedLoading=true;Task {await client.performRefresh {if mode=="following" && !client.authenticated {client.clearPublicViews()} else {try await client.loadPublicFeed(mode:mode,query:query,species:species)}};initialFeedLoading=false}}
        .sheet(item:$reportPost) {post in NavigationStack {CloudReportView(post:post,client:client)}}
        .confirmationDialog("この相手をブロックしますか？",isPresented:Binding(get:{blockPost != nil},set:{if !$0 {blockPost=nil}}),titleVisibility:.visible) {
            if let post=blockPost {Button("相手のすべてのPetをブロック",role:.destructive) {let target=post.pet_id;blockPost=nil;Task {await client.perform {try await client.block(pet:target,enabled:true)}}}}
        } message: {Text("ログイン中は双方の公開投稿を非表示にします。家族アルバムの権限は別です。家族のアクセスを止めるにはメンバー解除または退出してください。")}
        .task {
            await client.restore()
            if detail != nil {await loadDetail()} else {await loadFeedForNewIdentity()}
        }
        .onChange(of:client.authenticated) {_,_ in
            // Auth becomes available before the Pet list finishes loading.
            // Start the feed in parallel, and coalesce the later .task call.
            Task {if detail != nil {await loadDetail()} else {await loadFeedForNewIdentity()}}
        }
        .onChange(of:scenePhase) {_,phase in
            guard phase == .active,loadedFeedIdentity != nil,!initialFeedLoading,!client.publicFeedIsRevalidating else {return}
            Task {if detail != nil {await loadDetail()} else {await client.performRefresh {try await client.loadPublicFeed(mode:mode,query:query,species:species)}}}
        }
    }
    private func loadDetail() async {
        guard let id=detail else {return}
        detailLoading=true
        defer {detailLoading=false}
        let name=profile?.name ?? client.publicPosts.first(where:{$0.id==id})?.name ?? detailPost?.name ?? ""
        if !name.isEmpty {
            do {
                let result=try await client.publicPost(id,petName:name)
                guard result.visible else {detailPost=nil;detailImages=[:];return}
                if let fresh=result.post {detailPost=fresh}
            } catch {if detailPost==nil {client.error=error.localizedDescription}}
        } else if let cached=client.publicPosts.first(where:{$0.id==id}) {detailPost=cached}
        guard let post=detailPost else {return}
        await withTaskGroup(of:(String,UIImage?).self) {group in
            for media in post.media where detailImages[media]==nil && client.publicImages[media]==nil {
                group.addTask {let image=try? await client.twinsImage(media);return (media,image)}
            }
            for await (media,image) in group {if let image {detailImages[media]=image}}
        }
    }
    @ViewBuilder private var visiblePostRows:some View {
        ForEach(displayedPosts) {post in
            homePost(post,isDetail:detail != nil)
                .onAppear {if detail==nil {client.prefetchPublicImages(after:post.id);client.prefetchPublicVideos(after:post.id);loadNextPageIfNearEnd(post)}}
        }
    }
    private var displayedPosts:[CloudPublicPost] {
        if let detail {return [detailPost ?? client.publicPosts.first(where:{$0.id==detail})].compactMap{$0}}
        return integrated || mode != "all" ? client.publicPosts : []
    }
    private func loadFeedForNewIdentity() async {
        let identity=client.currentUserID ?? "guest"
        guard loadedFeedIdentity != identity else {return}
        loadedFeedIdentity=identity
        await loadFeedForCurrentIdentity()
    }
    private func loadFeedForCurrentIdentity() async {
        defer {initialFeedLoading=false}
        if mode=="following" && !client.authenticated {client.clearPublicViews();return}
        do {try await client.loadPublicFeed(mode:mode,query:query,species:species)}
        catch is CancellationError {} catch {client.error=error.localizedDescription}
    }
    private func homePost(_ post:CloudPublicPost,isDetail:Bool=false)->some View {
        VStack(alignment:.leading,spacing:0) {
            HStack(spacing:10) {
                NavigationLink {CloudPublicPetView(petID:post.pet_id,client:client)} label: {
                    Group {
                        if let media=post.media.first,let image=detailImages[media] ?? client.publicImages[media] {
                            Image(uiImage:image).resizable().scaledToFill().frame(width:36,height:36).clipShape(Circle())
                        } else {
                            Circle().fill(Theme.accent.opacity(0.12)).frame(width:36,height:36)
                                .overlay {Image(systemName:"pawprint.fill").font(.caption).foregroundStyle(Theme.actionText)}
                        }
                    }
                }.buttonStyle(.plain).accessibilityIdentifier("cloud-open-pet-"+post.pet_id)
                NavigationLink {if isDetail {CloudPublicPetView(petID:post.pet_id,client:client)} else {CloudDiscoveryView(client:client,detail:post.id)}} label: {
                    VStack(alignment:.leading,spacing:1) {
                        Text(displayName(post)).font(.subheadline.bold()).lineLimit(1)
                        if !breedLabel(post).isEmpty {
                            Text(breedLabel(post))
                                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                .accessibilityIdentifier("cloud-post-breed-"+post.id)
                        }
                    }
                }.buttonStyle(.plain).accessibilityIdentifier("cloud-open-post-"+post.id)
                Spacer(minLength:4)
                Button(post.following ? "フォロー中" : "フォロー") {
                    if client.authenticated {
                        Task {await client.perform {let enabled = !post.following;try await client.follow(pet:post.pet_id,enabled:enabled);if detailPost?.id==post.id {detailPost?.following=enabled}}}
                    } else {beginAuthentication(post:post,action:"follow")}
                }.font(.caption.bold()).foregroundStyle(post.following ? Theme.secondaryText : Theme.actionText)
                    .padding(.horizontal,10).frame(minHeight:32)
                    .overlay {Capsule().stroke(post.following ? Color(.systemGray4) : Theme.accent,lineWidth:1)}
                    .disabled(client.busy).accessibilityIdentifier(client.authenticated ? "cloud-follow-pet" : "cloud-guest-follow")
                Menu {
                    if client.authenticated {
                        Button("通報する",systemImage:"flag") {reportPost=post}.accessibilityIdentifier("cloud-report-post")
                        Button("ブロック",systemImage:"person.crop.circle.badge.xmark") {blockPost=post}.accessibilityIdentifier("cloud-block-post")
                    } else {
                        Button("ログインして通報する",systemImage:"flag") {beginAuthentication(post:post,action:"report")}
                    }
                } label: {Image(systemName:"ellipsis").font(.system(size:19)).frame(width:36,height:44)}
                    .accessibilityLabel("投稿のメニュー")
            }.padding(.horizontal,12).frame(minHeight:56)
            if post.media.count>1 {homeMediaCarousel(post)}
            else if let media=post.media.first {homeMedia(media,isVideo:post.video_media?.contains(media)==true)}
            HStack(spacing:16) {
                Button {
                    if client.authenticated {Task {await client.perform {let enabled = !post.liked;try await client.react(post:post.id,kind:"like",enabled:enabled);if detailPost?.id==post.id {detailPost?.liked=enabled;detailPost?.likes=max(0,post.likes+(enabled ? 1 : -1))}}}}
                    else {beginAuthentication(post:post,action:"like")}
                } label: {
                    HStack(spacing:5) {
                        ZStack {
                            Circle().fill(Theme.accent.opacity(0.12)).frame(width:34,height:34)
                            Image(systemName:post.liked ? "heart.fill" : "heart").font(.system(size:20,weight:.semibold)).foregroundStyle(Theme.actionText)
                            if post.liked {Image(systemName:"pawprint.fill").font(.system(size:8)).foregroundStyle(.white).offset(x:7,y:4)}
                        }.symbolEffect(.bounce,value:post.liked)
                        Text("\(post.likes)").font(.subheadline.weight(.semibold))
                    }.foregroundStyle(post.liked ? Theme.actionText : Theme.text).frame(minHeight:44)
                }.buttonStyle(.plain).disabled(client.busy)
                    .accessibilityIdentifier(client.authenticated ? "cloud-like-post" : "cloud-guest-like")
                    .accessibilityLabel("いいね \(post.likes)件").accessibilityValue(post.liked ? "いいね済み" : "いいねなし")
                Button {
                    if client.authenticated {commentPost=post}
                    else {beginAuthentication(post:post,action:"comment")}
                } label: {
                    HStack(spacing:5) {
                        ZStack {
                            Circle().fill(Theme.accent.opacity(0.12)).frame(width:34,height:34)
                            Image(systemName:"bubble.left.fill").font(.system(size:20)).foregroundStyle(Theme.actionText)
                            Image(systemName:"heart.fill").font(.system(size:7)).foregroundStyle(.white).offset(x:-2,y:-1)
                        }
                        Text("\(post.comments)").font(.subheadline.weight(.semibold))
                    }.frame(minHeight:44)
                }.buttonStyle(.plain).disabled(client.busy).accessibilityIdentifier("cloud-comments-post")
                    .accessibilityLabel("コメント \(post.comments)件")
                Spacer()
                Button {
                    if client.authenticated {Task {await client.perform {let enabled = !post.saved;try await client.react(post:post.id,kind:"save",enabled:enabled);if detailPost?.id==post.id {detailPost?.saved=enabled}}}}
                    else {beginAuthentication(post:post,action:"save")}
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius:11).fill(post.saved ? Theme.accent.opacity(0.18) : Theme.accent.opacity(0.08))
                            .frame(width:36,height:36)
                        Image(systemName:post.saved ? "square.stack.3d.up.fill" : "square.stack.3d.up")
                            .font(.system(size:19,weight:.medium)).foregroundStyle(Theme.actionText)
                        Image(systemName:"pawprint.fill").font(.system(size:7)).foregroundStyle(Theme.actionText)
                            .offset(x:10,y:10)
                    }.frame(width:44,height:44)
                }
                    .buttonStyle(.plain).disabled(client.busy).accessibilityIdentifier("cloud-save-post")
                    .accessibilityLabel("投稿を保存").accessibilityValue(post.saved ? "保存済み" : "未保存")
            }.padding(.horizontal,12).foregroundStyle(Theme.text)
            if !post.body.isEmpty && !isStockCaption(post) {
                Text(post.body).font(.subheadline).lineLimit(isDetail || expandedPostIDs.contains(post.id) ? nil : 2)
                    .frame(maxWidth:.infinity,alignment:.leading)
                    .padding(.horizontal,13).padding(.vertical,10)
                    .background(Theme.accent.opacity(0.065),in:RoundedRectangle(cornerRadius:15))
                    .padding(.horizontal,12)
                if !isDetail && (post.body.count>24 || post.body.contains("\n")) {
                    Button(expandedPostIDs.contains(post.id) ? "閉じる" : "もっと見る") {
                        withAnimation(.easeInOut(duration:0.2)) {
                            if !expandedPostIDs.insert(post.id).inserted {expandedPostIDs.remove(post.id)}
                        }
                    }.font(.caption).foregroundStyle(.secondary).padding(.horizontal,14).padding(.top,3)
                        .accessibilityIdentifier("cloud-caption-more-"+post.id)
                }
            }
            if let tags=post.tags,!tags.isEmpty {
                Text(tags.map(\.name).joined(separator:" · ")).font(.caption).foregroundStyle(Theme.actionText)
                    .padding(.horizontal,14).padding(.top,4)
            }
            if post.comments>0 {
                Button("コメントをすべて見る") {
                    if client.authenticated {commentPost=post}
                    else {beginAuthentication(post:post,action:"comment")}
                }.font(.caption).foregroundStyle(.secondary).padding(.horizontal,14).padding(.top,5)
            }
            if let time=post.published_at {Text(PostTime.label(time)).font(.caption2).foregroundStyle(Theme.secondaryText).padding(.horizontal,14).padding(.top,6)}
            if isDetail,let source=stockSource(post) {
                Link("写真情報",destination:source).font(.caption2).foregroundStyle(Theme.secondaryText)
                    .padding(.horizontal,14).padding(.top,6)
            }
        }.padding(.bottom,14).background(.white)
            .overlay(alignment:.bottom) {Rectangle().fill(Color(.systemGray5)).frame(height:0.5)}
    }
    private func isStockCaption(_ post:CloudPublicPost)->Bool {
        post.body.hasPrefix("【MEFRION運営・検証投稿】") || post.body.hasPrefix("運営セレクトの参考写真です。撮影:")
    }
    private func displayName(_ post:CloudPublicPost)->String {
        post.name
    }
    private func breedLabel(_ post:CloudPublicPost)->String {
        let value=post.breed.trimmingCharacters(in:.whitespacesAndNewlines)
        if value.isEmpty || value=="犬種未確認" || value=="猫種未確認" || value=="犬種未登録" || value=="猫種未登録" {return ""}
        return isStockCaption(post) ? value.replacingOccurrences(of:"（推定）",with:"") : value
    }
    private func stockSource(_ post:CloudPublicPost)->URL? {
        guard isStockCaption(post),let text=post.body.components(separatedBy:"\n").first(where:{$0.hasPrefix("https://www.pexels.com/")}),let url=URL(string:text),url.host=="www.pexels.com" else{return nil}
        return url
    }
    private func homeMediaCarousel(_ post:CloudPublicPost)->some View {
        let page=Binding<Int>(get:{min(mediaPageByPost[post.id] ?? 0,post.media.count-1)},set:{mediaPageByPost[post.id]=$0})
        return VStack(spacing:0) {
            GeometryReader {geometry in
                TabView(selection:page) {
                    ForEach(Array(post.media.enumerated()),id:\.offset) {index,media in
                        homeMedia(media,isVideo:post.video_media?.contains(media)==true,isCurrent:page.wrappedValue==index)
                            .frame(width:geometry.size.width,height:geometry.size.height)
                            .tag(index)
                    }
                }.tabViewStyle(.page(indexDisplayMode:.never))
                    .frame(width:geometry.size.width,height:geometry.size.height)
                    .background {
                        HorizontalPanObserver {active in
                            if active {carouselSwipeInProgress=true}
                            else {Task {@MainActor in
                                try? await Task.sleep(for:.milliseconds(250))
                                carouselSwipeInProgress=false
                            }}
                        }
                    }
                    .overlay(alignment:.topTrailing) {
                        Text("\(page.wrappedValue+1)/\(post.media.count)")
                            .font(.caption.bold()).foregroundStyle(.white)
                            .padding(.horizontal,10).padding(.vertical,6)
                            .background(.black.opacity(0.56),in:Capsule())
                            .padding(12)
                    }
            }.aspectRatio(4.0/5.0,contentMode:.fit)
            HStack(spacing:6) {
                ForEach(post.media.indices,id:\.self) {index in
                    Circle().fill(index==page.wrappedValue ? Theme.accent : Color(.systemGray4))
                        .frame(width:index==page.wrappedValue ? 7 : 5,height:index==page.wrappedValue ? 7 : 5)
                }
            }.frame(height:20).accessibilityLabel("\(post.media.count)枚中\(page.wrappedValue+1)枚目")
        }.accessibilityIdentifier("cloud-media-carousel-"+post.id)
    }
    @ViewBuilder private func homeMedia(_ media:String,isVideo:Bool=false,isCurrent:Bool=true)->some View {
        GeometryReader {geometry in
            ZStack {
                Rectangle().fill(client.failedPublicImages.contains(media) ? Color(.systemGray6) : Theme.background)
                if isVideo {
                    InlineAutoplayVideo(id:media,poster:detailImages[media] ?? client.publicImages[media],
                        active:activeVideoMedia==media && commentPost==nil && reportPost==nil && blockPost==nil && !authenticating,
                        client:client)
                } else if let image=detailImages[media] ?? client.publicImages[media] {
                    Image(uiImage:image).resizable().scaledToFill()
                        .frame(width:geometry.size.width,height:geometry.size.height).clipped()
                        .accessibilityIdentifier("cloud-public-image")
                } else if client.failedPublicImages.contains(media) {
                    VStack(spacing:8) {
                        Text("写真を表示できませんでした").font(.caption)
                        Button("再読み込み") {Task {await client.performRefresh {try await client.loadPublicFeed(mode:mode,query:query,species:species)}}}
                    }
                } else {FeedMediaSkeleton()}
            }.frame(width:geometry.size.width,height:geometry.size.height)
        }.aspectRatio(4.0/5.0,contentMode:.fit).frame(maxWidth:.infinity)
            .background {if isVideo && isCurrent {GeometryReader {geometry in
                let frame=geometry.frame(in:.global)
                let height=UIScreen.main.bounds.height
                Color.clear.preference(key:VideoViewportPreferenceKey.self,value:
                    frame.maxY>height*0.18 && frame.minY<height*0.78
                    ? [media:abs(frame.midY-height*0.48)] : [:])
            }}}
            .onAppear {if isCurrent {client.setPublicImageVisible(media,true);if isVideo {client.setPublicVideoVisible(media,true)}}}
            .onDisappear {client.setPublicImageVisible(media,false);if isVideo {client.setPublicVideoVisible(media,false)}}
            .onChange(of:isCurrent) {_,current in
                client.setPublicImageVisible(media,current)
                if isVideo {client.setPublicVideoVisible(media,current)}
            }
    }
    private func beginAuthentication(post:CloudPublicPost,action:String) {
        continuation=Continuation(post:post.id,action:action);authenticating=true
    }
    private func loadNextPage() {
        guard !loadingNext,!client.publicFeedIsRevalidating,client.hasMorePublicPosts else {return}
        loadingNext=true
        Task {
            await client.performRefresh {try await client.loadPublicFeed(append:true)}
            loadingNext=false
        }
    }
    private func loadNextPageIfNearEnd(_ post:CloudPublicPost) {
        guard client.hasMorePublicPosts,
              let index=client.publicPosts.firstIndex(where:{$0.id==post.id}),
              index>=client.publicPosts.count-6 else {return}
        loadNextPage()
    }
    private func resume(post:CloudPublicPost,action:String) {
        if action=="comment" {commentPost=post;continuation=nil;return}
        if action=="report" {reportPost=post;continuation=nil;return}
        Task {await client.perform {
            // Use the freshly fetched post and current server permissions.
            if action=="follow" {try await client.follow(pet:post.pet_id,enabled:true)}
            else {try await client.react(post:post.id,kind:action,enabled:true)}
            continuation=nil
        }}
    }

}


struct CloudBlockedPetsView:View {
    @ObservedObject var client:CloudFamilyClient
    var body:some View {
        List {
            Section {Text("相手が管理するすべてのPetに適用します。ここに表示する名前はブロック時点のものです。家族アルバムの権限は変わりません。").font(.footnote)}
            ForEach(client.blockedPets) {pet in HStack {Text(pet.name);Spacer();Button("解除する") {Task {await client.perform {try await client.block(pet:pet.id,enabled:false)}}}.disabled(client.busy)}}
            if client.blockedPets.isEmpty && !client.busy {Text("ブロックした相手はいません")}
            if client.busy {ProgressView()}
            if let error=client.error {Text(error).foregroundStyle(.red)}
        }.navigationTitle("ブロックした相手")
        .task {await client.perform {try await client.loadBlockedPets()}}
    }

}

struct CloudReportView:View {
    let post:CloudPublicPost
    @ObservedObject var client:CloudFamilyClient
    @Environment(\.dismiss) private var dismiss
    @State private var reason="spam"
    @State private var note=""
    @State private var key=UUID()
    @State private var submitted=false
    var body:some View {
        Form {
            Section {Text(post.name).font(.headline);Text(post.body)
                    if let tags=post.tags,!tags.isEmpty {Text(tags.map(\.name).joined(separator:" · ")).font(.caption).foregroundStyle(Theme.actionText)};Text("通報内容は運営確認用です。相手に通報者の情報は表示しません。").font(.footnote)}
            if submitted {Section {Text("通報を受け付けました").accessibilityIdentifier("cloud-report-success")}} else {
                Section("理由") {
                    Picker("通報理由",selection:$reason) {
                        Text("スパム").tag("spam");Text("嫌がらせ").tag("harassment");Text("動物福祉への懸念").tag("animal_welfare");Text("なりすまし").tag("impersonation");Text("著作権").tag("copyright");Text("その他").tag("other")
                    }
                    TextField("補足（任意・1000文字まで）",text:$note,axis:.vertical)
                    Button("通報を送信") {let selectedReason=reason;let text=note;let id=key;Task {await client.perform {try await client.report(post:post,reason:selectedReason,note:text,key:id);submitted=true}}}.disabled(client.busy || note.count>1000).accessibilityIdentifier("cloud-submit-report")
                }.disabled(client.busy)
            }
            if client.busy {ProgressView()}
            if let error=client.error {Text(error).foregroundStyle(.red)}
        }.navigationTitle("投稿を通報").toolbar {ToolbarItem(placement:.cancellationAction) {Button("閉じる") {dismiss()}}}
        .onChange(of:note) {_,_ in key=UUID()}.onChange(of:reason) {_,_ in key=UUID()}
    }
}


struct CloudModerationNoticesView:View {
    @ObservedObject var client:CloudFamilyClient
    @State private var selected:CloudModerationNotice?
    var body:some View {
        List {
            Text("運営の対応を確認できます。通報者の情報は表示しません。公開活動が停止中でも、私的写真の管理と同意撤回は利用できます。").font(.footnote)
            ForEach(client.moderationNotices) {notice in Section {
                Text(notice.note)
                if notice.decision=="hide_post" || notice.decision=="hide_comment" || notice.decision=="suspend_account" {Button("異議を申し立てる") {selected=notice}}
            }}
            if client.moderationNotices.isEmpty && !client.busy {Text("運営からの通知はありません")}
            if client.busy {ProgressView()}
            if let error=client.error {Text(error).foregroundStyle(.red)}
        }.navigationTitle("運営からの通知").task {await client.perform {try await client.loadModerationNotices()}}
        .onDisappear {client.moderationNotices=[]}
        .sheet(item:$selected) {notice in NavigationStack {CloudAppealView(notice:notice,client:client)}}
    }
}

struct CloudAppealView:View {
    let notice:CloudModerationNotice
    @ObservedObject var client:CloudFamilyClient
    @Environment(\.dismiss) private var dismiss
    @State private var note=""
    @State private var sent=false
    var body:some View {
        Form {
            Section {Text(notice.note)}
            if sent {Text("異議申し立てを受け付けました")} else {
                Section("確認してほしい内容") {
                    TextField("内容（1000文字まで）",text:$note,axis:.vertical)
                    Text("1件の対応について1回送信できます。運営が確認するまで公開状態は変わりません。").font(.caption)
                    Button("異議申し立てを送信") {let text=note;Task {await client.perform {try await client.appeal(report:notice.id,note:text);sent=true}}}.disabled(client.busy || note.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || note.count>1000)
                }.disabled(client.busy)
            }
            if client.busy {ProgressView()}
            if let error=client.error {Text(error).foregroundStyle(.red)}
        }.navigationTitle("異議申し立て").toolbar {ToolbarItem(placement:.cancellationAction) {Button("閉じる") {dismiss()}}}
    }
}

struct CloudCommentsView:View {
    let post:CloudPublicPost
    @ObservedObject var client:CloudFamilyClient
    @Environment(\.dismiss) private var dismiss
    @State private var records:[CloudComment]=[]
    @State private var speakers:[CloudBlockedPet]=[]
    @State private var name=""
    @State private var savedName=""
    @State private var text=""
    @State private var alias=""
    @State private var parent:CloudComment?
    @State private var key=UUID()
    @State private var reportTarget:CloudComment?
    @State private var deleteTarget:CloudComment?
    @State private var showingName=false
    @FocusState private var focused:Bool
    private func reload() async throws {
        records=try await client.comments(post:post.id)
        client.syncCommentCount(post:post.id,count:records.filter{!$0.deleted}.count)
    }
    var body:some View {
        ScrollView {
            LazyVStack(alignment:.leading,spacing:16) {
                HStack(spacing:8) {
                    Image(systemName:"pawprint.fill").foregroundStyle(Theme.accent)
                    Text(post.name).font(.subheadline.bold())
                    Spacer()
                    Text("コメント \(records.filter{!$0.deleted}.count)").font(.caption).foregroundStyle(Theme.secondaryText)
                }.padding(.bottom,5)
                if records.isEmpty && !client.busy {
                    VStack(spacing:9) {
                        Image(systemName:"bubble.left.and.heart.fill").font(.largeTitle).foregroundStyle(Theme.accent.opacity(0.7))
                        Text("最初のひとことを届けよう ♡").font(.subheadline.weight(.medium))
                    }.frame(maxWidth:.infinity).padding(.vertical,45)
                }
                ForEach(records) {comment in
                    HStack(alignment:.top,spacing:10) {
                        Image(systemName:"pawprint.fill").font(.caption).foregroundStyle(Theme.accent)
                            .frame(width:34,height:34).background(Theme.accent.opacity(0.1),in:Circle())
                        VStack(alignment:.leading,spacing:5) {
                            HStack {
                                Text(comment.display_name).font(.subheadline.bold())
                                Spacer()
                                Text(PostTime.label(comment.created_at)).font(.caption2).foregroundStyle(Theme.secondaryText)
                            }
                            Text(comment.deleted ? "コメントは削除されました" : comment.body).font(.subheadline)
                            if !comment.deleted {
                                HStack(spacing:17) {
                                    if comment.parent==nil {Button("返信") {parent=comment;focused=true}.accessibilityIdentifier("cloud-reply-comment")}
                                    Menu {
                                        if comment.mine {Button("削除",role:.destructive) {deleteTarget=comment}.accessibilityIdentifier("cloud-delete-comment")}
                                        Button("通報",systemImage:"flag") {reportTarget=comment}.accessibilityIdentifier("cloud-report-comment")
                                    } label: {Image(systemName:"ellipsis").frame(width:28,height:28)}
                                    .accessibilityLabel("コメントの操作")
                                }.font(.caption).foregroundStyle(Theme.secondaryText).buttonStyle(.plain)
                            }
                        }
                    }.padding(.leading,comment.parent==nil ? 0 : 28)
                }
                if client.busy {PawLoadingView(title:"送信中",compact:true)}
                if let error=client.error {Text(error).font(.caption).foregroundStyle(.red)}
            }.padding(16)
        }.background(Theme.background)
            .safeAreaInset(edge:.bottom,spacing:0) {
                VStack(spacing:7) {
                    if let parent {
                        HStack {Text(parent.display_name+"に返信").font(.caption);Spacer();Button("やめる") {self.parent=nil}.font(.caption)}
                            .foregroundStyle(Theme.actionText).padding(.horizontal,10)
                    }
                    HStack(alignment:.bottom,spacing:8) {
                        if !speakers.isEmpty {
                            Menu {
                                Button("自分の名前") {alias=""}
                                ForEach(speakers) {pet in Button(pet.name) {alias=pet.id}}
                            } label: {Image(systemName:"pawprint.fill").frame(width:38,height:40)}
                                .accessibilityIdentifier("cloud-comment-speaker")
                        }
                        TextField("コメントを入力…",text:$text,axis:.vertical)
                            .lineLimit(1...4).focused($focused)
                            .accessibilityIdentifier("cloud-comment-body")
                        Button {submit()} label: {Image(systemName:"arrow.up").font(.subheadline.bold())
                            .foregroundStyle(.white).frame(width:34,height:34)
                            .background(Theme.accent,in:Circle())}
                            .disabled(client.busy || text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || text.count>500)
                            .accessibilityLabel("コメントを送信").accessibilityIdentifier("cloud-send-comment")
                    }.padding(.horizontal,11).padding(.vertical,8)
                        .background(.white,in:RoundedRectangle(cornerRadius:23))
                        .overlay {RoundedRectangle(cornerRadius:23).stroke(Theme.accent.opacity(0.15))}
                }.padding(.horizontal,14).padding(.top,7).padding(.bottom,8).background(.regularMaterial)
            }
            .navigationTitle("コメント").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.topBarTrailing) {Button("閉じる") {dismiss()}}
                ToolbarItemGroup(placement:.keyboard) {Spacer();Button("完了") {focused=false}.accessibilityIdentifier("cloud-comment-done")}
            }
            .task {await client.perform {speakers=try await client.publicSpeakers();let identity=try await client.socialIdentity();name=identity?.name ?? "";savedName=name;alias=identity?.last_pet ?? "";try await reload()}}
            .onChange(of:text) {_,_ in key=UUID()}.onChange(of:alias) {_,_ in key=UUID()}.onChange(of:parent?.id) {_,_ in key=UUID()}
            .onChange(of:client.authenticated) {_,active in if !active {records=[];text="";dismiss()}}
            .sheet(isPresented:$showingName) {
                NavigationStack {
                    VStack(alignment:.leading,spacing:15) {
                        Text("コメントで使う名前").font(.title3.bold())
                        TextField("ニックネーム",text:$name).textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("cloud-social-name")
                        Text("メールアドレスは表示されません。いつでも変更できます。")
                            .font(.caption).foregroundStyle(Theme.secondaryText)
                        Button("この名前でコメントする") {showingName=false;sendComment()}
                            .buttonStyle(CoralButtonStyle())
                            .disabled(name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || name.count>40)
                        Spacer()
                    }.padding(22).navigationTitle("お名前")
                        .toolbar {ToolbarItem(placement:.topBarTrailing) {Button("閉じる") {showingName=false}}}
                }.presentationDetents([.medium])
            }
            .confirmationDialog("このコメントを削除しますか？",isPresented:Binding(get:{deleteTarget != nil},set:{if !$0 {deleteTarget=nil}}),titleVisibility:.visible) {
                if let target=deleteTarget {Button("コメントを削除",role:.destructive) {deleteTarget=nil;Task {await client.perform {try await client.deleteComment(target.id);try await reload()}}}}
            }
            .sheet(item:$reportTarget) {target in NavigationStack {CloudCommentReportView(comment:target,client:client)}}
    }
    private func submit() {
        if alias.isEmpty && name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {showingName=true;return}
        sendComment()
    }
    private func sendComment() {
        let body=text,reply=parent?.id,pet=alias.isEmpty ? nil : alias,requestKey=key
        let chosenName=name.trimmingCharacters(in:.whitespacesAndNewlines)
        Task {await client.perform {
            if pet==nil && chosenName != savedName {try await client.setSocialName(chosenName);savedName=chosenName}
            try await client.comment(post:post.id,body:body,parent:reply,aliasPet:pet,key:requestKey)
            text="";parent=nil;key=UUID();try await reload()
        }}
    }
}

struct CloudCommentReportView:View {
    let comment:CloudComment
    @ObservedObject var client:CloudFamilyClient
    @Environment(\.dismiss) private var dismiss
    @State private var reason="spam"
    @State private var note=""
    @State private var key=UUID()
    @State private var sent=false
    var body:some View {
        Form {
            Text(comment.display_name);Text(comment.body)
            Text("通報内容は運営確認用です。相手に通報者の情報は表示しません。").font(.footnote)
            if sent {Text("通報を受け付けました").accessibilityIdentifier("cloud-comment-report-success")} else {
                Picker("理由",selection:$reason) {Text("スパム").tag("spam");Text("嫌がらせ").tag("harassment");Text("動物福祉への懸念").tag("animal_welfare");Text("なりすまし").tag("impersonation");Text("著作権").tag("copyright");Text("その他").tag("other")}
                TextField("補足（任意・1000文字まで）",text:$note,axis:.vertical)
                Button("通報を送信") {let selected=reason;let body=note;let requestKey=key;Task {await client.perform {try await client.reportComment(comment.id,reason:selected,note:body,key:requestKey);sent=true}}}.disabled(client.busy || note.count>1000).accessibilityIdentifier("cloud-submit-comment-report")
            }
            if let error=client.error {Text(error).foregroundStyle(.red)}
        }.navigationTitle("コメントを通報").toolbar {ToolbarItem(placement:.cancellationAction) {Button("閉じる") {dismiss()}}}
        .onChange(of:note) {_,_ in key=UUID()}.onChange(of:reason) {_,_ in key=UUID()}
        .protectWhenInactive()
    }
}

struct CloudSocialNotificationsView:View {
    @ObservedObject var client:CloudFamilyClient
    @Environment(\.scenePhase) private var scenePhase
    @State private var records:[CloudSocialNotification]=[]
    @State private var family:[CloudFamilyNotification]=[]
    @State private var filter="all"
    private func reload() async throws {
        let freshRecords=try await client.socialNotifications()
        let freshFamily=try await client.familyNotifications()
        records=freshRecords;family=freshFamily
    }
    var body:some View {
        List {
            Text("アプリ内のお知らせです。端末へのプッシュ通知はまだ接続していません。").font(.footnote)
            NavigationLink("通知設定") {CloudNotificationSettingsView(client:client)}
            ScrollView(.horizontal,showsIndicators:false) {HStack {ForEach([("all","すべて"),("like","いいね"),("comment","コメント"),("follow","フォロー")],id:\.0) {value,title in Button {filter=value} label: {Text(title).font(.caption).padding(.horizontal,14).frame(minHeight:34).background(filter==value ? Theme.accent.opacity(0.12) : .white).clipShape(Capsule())}.buttonStyle(.borderless)}}}
            ForEach(records.filter{filter=="all" || $0.kind==filter || (filter=="comment" && $0.kind=="reply")}) {notice in HStack(spacing:12) {Image(systemName:notice.kind=="like" ? "heart.circle.fill" : notice.kind=="follow" ? "person.crop.circle.badge.plus" : "bubble.right.circle").font(.system(size:34)).foregroundStyle(Theme.actionText);VStack(alignment:.leading,spacing:5) {
                Text(notice.name).font(.headline)
                if let count=notice.count,count>1 {Text("同じ種類のお知らせ \(count)件").font(.caption)}
                Text(notice.kind=="like" ? "\(notice.pet_name)の投稿にいいねしました" : notice.kind=="follow" ? "\(notice.pet_name)をフォローしました" : notice.kind=="reply" ? "コメントに返信しました" : "\(notice.pet_name)の投稿にコメントしました")
                Text(notice.created_at).font(.caption).foregroundStyle(.secondary)
            };Spacer()}}
            if filter=="all" {ForEach(family) {notice in NavigationLink {CloudAlbumLibraryView()} label: {VStack(alignment:.leading) {Text(notice.pet_name).font(.headline);Text(notice.title);if notice.count>1 {Text("\(notice.count)件")}}}}}
            if records.isEmpty && family.isEmpty && !client.busy {Text("新しいお知らせはありません")}
            if client.busy {ProgressView()}
            if let error=client.error {Text(error).foregroundStyle(.red)}
        }.scrollContentBackground(.hidden).background(Theme.background).navigationTitle("通知").task {await client.perform {try await reload()}}
        .refreshable {await client.perform {try await reload()}}
        .onDisappear {records=[];family=[]}
        .onChange(of:client.authenticated) {_,authenticated in if !authenticated {records=[];family=[]}}
        .onChange(of:scenePhase) {_,phase in if phase == .active {Task {await client.perform {try await reload()}}}}
    }
}

struct CloudNotificationSettingsView:View {
    @ObservedObject var client:CloudFamilyClient
    @State private var preferences=CloudNotificationPreferences(like:true,comment:true,follow:true,twins:false)
    @State private var loaded=false
    @State private var saved=false
    var body:some View {
        Form {
            Text("アプリ内通知の表示を設定します。プッシュ通知はまだ接続していません。家族アルバムの通知設定は別です。").font(.footnote)
            Toggle("いいね",isOn:$preferences.like)
            Toggle("コメント・返信",isOn:$preferences.comment)
            Toggle("フォロー",isOn:$preferences.follow)
            Text("Twinsのクラウド通知は準備中です。").font(.footnote)
            Button("設定を保存") {let snapshot=preferences;Task {await client.perform {try await client.setNotificationPreferences(snapshot);saved=true}}}.disabled(client.busy || !loaded)
            if saved {Text("通知設定を保存しました")}
            if let error=client.error {Text(error).foregroundStyle(.red)}
        }.disabled(client.busy || !loaded).navigationTitle("通知設定")
        .task {await client.perform {preferences=try await client.notificationPreferences();loaded=true}}
        .onChange(of:preferences.like) {_,_ in saved=false}.onChange(of:preferences.comment) {_,_ in saved=false}.onChange(of:preferences.follow) {_,_ in saved=false}
    }
}

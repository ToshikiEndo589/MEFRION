import SwiftUI

struct DemoPost: Identifiable {
    let id: Int
    var name: String { ["こむぎ", "きなこ", "まる", "むぎ", "そら", "はな", "モカ", "ゆず", "ルカ", "りん"][id] }
    var asset: String { "pet-\(id)" }
}

struct PostCard: View {
    let post: DemoPost
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(post.asset).resizable().scaledToFill().frame(width: 38,height: 38).clipShape(Circle())
                VStack(alignment: .leading) { Text(post.name).font(.headline); Text("開発用の犬猫イラスト").font(.caption).foregroundStyle(Theme.secondaryText) }
                Spacer()
            }
            Image(post.asset).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 14))
                .accessibilityLabel("犬猫を描いた開発用イラスト")
            Text("かわいい毎日を、いっしょに。").font(.subheadline)
        }.padding(14).background(.white).clipShape(RoundedRectangle(cornerRadius: Theme.radius))
    }
}

struct HomeView: View {
    @StateObject private var client = SocialClient()
    @State private var discovery = true
    @Environment(\.rootTabSwipe) private var moveRootTab
    @State private var search = ""
    @FocusState private var searchFocused:Bool
    @State private var notificationSheet = false
    @State private var searchSheet=false
    @State private var speciesFilter = "all"
    var visible: [FeedPost] { client.posts.filter { !discovery || ((search.isEmpty || $0.name.localizedStandardContains(search)) && (speciesFilter == "all" || $0.species == speciesFilter)) } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                CompactHomeHeader {
                    Button {searchSheet=true} label: {Image(systemName:"magnifyingglass").font(.system(size:20)).frame(width:44,height:44)}.accessibilityLabel("検索").accessibilityIdentifier("home-search")
                    Button {notificationSheet=true} label: {Image(systemName:"bell").font(.system(size:20)).frame(width:44,height:44)}.accessibilityLabel("通知")
                }.foregroundStyle(Theme.text)

                HStack {
                    Button {discovery=true} label: {Label("おすすめ",systemImage:"pawprint.fill").frame(maxWidth:.infinity,minHeight:44).contentShape(Rectangle())}
                        .foregroundStyle(discovery ? Theme.actionText : Theme.text).accessibilityIdentifier("home-recommended").accessibilityValue(discovery ? "選択中" : "未選択")
                    Button {discovery=false} label: {Label("フォロー中",systemImage:"person.2").frame(maxWidth:.infinity,minHeight:44).contentShape(Rectangle())}
                        .foregroundStyle(discovery ? Theme.text : Theme.actionText).accessibilityIdentifier("home-following").accessibilityValue(discovery ? "未選択" : "選択中")
                }.font(.caption.weight(.semibold)).dynamicTypeSize(...DynamicTypeSize.xxxLarge).frame(minHeight:44)
                HStack(spacing:0) {
                    Capsule().fill(discovery ? Theme.accent : Color.clear)
                    Capsule().fill(discovery ? Color.clear : Theme.accent)
                }.frame(height:2)
                if client.loading { ProgressView().frame(maxWidth:.infinity) }
                if let error=client.error { Text(error).font(.footnote).foregroundStyle(.red); Button("再読み込み") { Task { await client.load(following:!discovery) } } }
                if let message=client.message { Text(message).font(.footnote) }
                if !client.loading && visible.isEmpty && client.error == nil {
                    ContentUnavailableView(discovery ? "見つかりませんでした" : "フォロー中のPetはまだいません",systemImage:"pawprint",description:Text("おすすめから、気になるPetをフォローできます。"))
                }
                ForEach(visible) { post in FeedCard(post:post,client:client) }
                NavigationLink("MEFRIONのコンテンツについて") {
                    Text("運営が選んだ参考写真を使う投稿が含まれる場合があります。投稿には撮影者と出典を表示し、実在するPetの記録とは区別します。反応数は実際の操作だけを数えます。")
                        .padding().navigationTitle("コンテンツについて")
                }.font(.footnote)
            }.padding(.horizontal,16).padding(.bottom,8)
        }.background(Theme.background).foregroundStyle(Theme.text)
        .navigationTitle("MEFRION").navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden,for:.navigationBar)
        .modifier(HorizontalTabSwipe {towardRight in
            if discovery == !towardRight {moveRootTab(towardRight)} else {discovery = !towardRight}
        })
        .sheet(isPresented:$notificationSheet) {NavigationStack {NotificationHubView()}}
        .sheet(isPresented:$searchSheet) {NavigationStack {PublicSearchView()}}
        .task { await client.load() }
        .onChange(of:discovery) { _,value in Task { await client.load(following:!value) } }
        .refreshable { await client.load(following:!discovery) }
    }
    private func filterChip(_ title:String,value:String)->some View {
        Button {speciesFilter=value} label: {
            Text(title).font(.caption.weight(.medium)).padding(.horizontal,16).frame(minHeight:36)
                .foregroundStyle(speciesFilter==value ? .white : Theme.text)
                .background(speciesFilter==value ? Theme.accent : .white)
                .clipShape(Capsule()).overlay(Capsule().stroke(Color(.systemGray5),lineWidth:speciesFilter==value ? 0 : 1))
        }.accessibilityValue(speciesFilter==value ? "選択中" : "未選択")
    }
}

struct DiscoveryTile:View {
    var accessibilityPrefix="feed-open-"
    let post:FeedPost
    @ObservedObject var client:SocialClient
    var body:some View {
        ZStack(alignment:.bottomLeading) {
            NavigationLink {PostDetailView(post:post,client:client)} label: {
                GeometryReader {geometry in
                    Image(post.asset).resizable().scaledToFill().frame(width:geometry.size.width,height:geometry.size.height).clipped()
                }.aspectRatio(0.92,contentMode:.fit)
            }.accessibilityLabel("\(post.name)の投稿を開く").accessibilityIdentifier(accessibilityPrefix+post.id)
            LinearGradient(colors:[.clear,.black.opacity(0.4)],startPoint:.center,endPoint:.bottom).allowsHitTesting(false)
            Button {Task {await client.react(post,kind:"like")}} label: {
                Label("\(post.likes)",systemImage:client.liked.contains(post.id) ? "heart.fill" : "heart")
                    .font(.caption.bold()).foregroundStyle(.white).padding(8)
            }.accessibilityLabel("いいね \(post.likes)件").accessibilityIdentifier("feed-like-"+post.id)
        }.clipShape(RoundedRectangle(cornerRadius:9))
    }
}

struct FeedCard: View {
    let post:FeedPost
    @ObservedObject var client:SocialClient
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                NavigationLink { PublicPetView(post:post,client:client) } label: {
                    HStack {
                        Image(post.asset).resizable().scaledToFill().frame(width:36,height:36).clipShape(Circle())
                        VStack(alignment:.leading,spacing:3) { Text(post.name).font(.subheadline.bold());Text(post.species == "dog" ? "犬" : "猫").font(.caption).foregroundStyle(Theme.secondaryText) }
                    }.foregroundStyle(Theme.text)
                }
                Spacer()
                Menu {
                    Button("通報する",systemImage:"flag") { Task { await client.report(post,reason:"other") } }
                    Button("この管理者をブロック",systemImage:"hand.raised",role:.destructive) { Task { await client.block(post) } }
                } label: { Image(systemName:"ellipsis").frame(width:44,height:44) }.accessibilityLabel("投稿のメニュー")
            }
            NavigationLink { PostDetailView(post:post,client:client) } label: {
                Image(post.asset).resizable().scaledToFill().frame(height:240).clipped().clipShape(RoundedRectangle(cornerRadius:10))
            }.accessibilityLabel("\(post.name)の投稿を開く").accessibilityIdentifier("feed-open-"+post.id)
            if !post.body.isEmpty { Text(post.body).font(.subheadline) }
            HStack(spacing:20) {
                Button { Task { await client.react(post,kind:"like") } } label: { Label("\(post.likes)",systemImage:client.liked.contains(post.id) ? "heart.fill" : "heart").frame(minWidth:44,minHeight:44) }
                    .accessibilityLabel("いいね \(post.likes)件").accessibilityIdentifier("feed-like-"+post.id)
                NavigationLink { PostDetailView(post:post,client:client) } label: { Label("\(post.comments)",systemImage:"bubble.right").frame(minWidth:44,minHeight:44) }.accessibilityLabel("コメント \(post.comments)件")
                Spacer()
                Button { Task { await client.react(post,kind:"save") } } label: { Image(systemName:client.saved.contains(post.id) ? "tray.and.arrow.down.fill" : "tray.and.arrow.down").frame(width:44,height:44) }.accessibilityLabel("投稿を保存")
            }.foregroundStyle(Theme.actionText).font(.subheadline)
        }.padding(10).background(.white).clipShape(RoundedRectangle(cornerRadius:14))
    }
}

struct PublicPetView:View {
    let post:FeedPost
    @ObservedObject var client:SocialClient
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:16) {
                Image(post.asset).resizable().scaledToFill().frame(height:210).clipped().clipShape(RoundedRectangle(cornerRadius:16))
                HStack(alignment:.bottom) {
                    Image(post.asset).resizable().scaledToFill().frame(width:82,height:82).clipShape(Circle()).overlay(Circle().stroke(.white,lineWidth:4)).padding(.top,-48)
                    Spacer()
                    Button(client.followed.contains(post.pet_id) ? "フォロー中" : "フォローする") {Task {await client.follow(post)}}
                        .buttonStyle(CoralButtonStyle()).accessibilityIdentifier("profile-follow")
                }
                VStack(alignment:.leading,spacing:4) {Text(post.name).font(.title2.bold());Text(post.species == "dog" ? "犬" : "猫").font(.caption).foregroundStyle(Theme.secondaryText)}
                Text("開発用イラストのPetです。人間の個人情報や家族アルバムは公開しません。").font(.footnote)
                Text("投稿").font(.headline)
                ForEach(client.posts.filter { $0.pet_id == post.pet_id }) { item in FeedCard(post:item,client:client) }
            }.padding()
        }.background(Theme.background).navigationTitle(post.name).navigationBarTitleDisplayMode(.inline).toolbar(.visible,for:.navigationBar)
    }
}

struct PostDetailView:View {
    let post:FeedPost
    @ObservedObject var client:SocialClient
    @State private var text=""
    @State private var reply:FeedComment?
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:16) {
                TabView { ForEach(Array(post.images.enumerated()),id:\.offset) { _,image in Image(image.asset).resizable().scaledToFit() } }
                    .tabViewStyle(.page).frame(height:350)
                Text(post.body).font(.subheadline)
                HStack(spacing:22) {
                    Button {Task {await client.react(post,kind:"like")}} label: {Label("\(post.likes)",systemImage:client.liked.contains(post.id) ? "heart.fill" : "heart")}
                    Spacer()
                    Button {Task {await client.react(post,kind:"save")}} label: {Image(systemName:client.saved.contains(post.id) ? "tray.and.arrow.down.fill" : "tray.and.arrow.down")}.accessibilityLabel("投稿を保存")
                    Menu {
                        Button("通報する",systemImage:"flag") {Task {await client.report(post,reason:"other")}}
                        Button("この管理者をブロック",systemImage:"hand.raised",role:.destructive) {Task {await client.block(post)}}
                    } label: {Image(systemName:"ellipsis")}.accessibilityLabel("投稿のメニュー")
                }.foregroundStyle(Theme.actionText).frame(minHeight:44)
                Divider()
                HStack { Text("コメント").font(.headline);Spacer();Text("\(client.comments.count)").foregroundStyle(Theme.secondaryText) }
                ForEach(client.comments) { comment in
                    VStack(alignment:.leading,spacing:6) {
                        Text(comment.display_name).font(.caption.bold());Text(comment.body)
                        if comment.parent == nil { Button("返信") { reply=comment }.font(.caption) }
                    }.padding().frame(maxWidth:.infinity,alignment:.leading).background(.white).clipShape(RoundedRectangle(cornerRadius:14))
                }
                if let reply { HStack { Text("返信先：\(reply.display_name)").font(.caption);Spacer();Button("取消") { self.reply=nil } } }
                TextField("コメントを入力（500文字まで）",text:$text,axis:.vertical).padding().background(.white).clipShape(RoundedRectangle(cornerRadius:14)).accessibilityIdentifier("comment-input")
                Button("送信する") { Task { if await client.comment(post.id,body:text,parent:reply?.id) { text="";reply=nil } } }.buttonStyle(CoralButtonStyle()).disabled(text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || text.count>500)
                if let error=client.error { Text(error).foregroundStyle(.red).font(.footnote) }
            }.padding()
        }.background(Theme.background).navigationTitle(post.name).navigationBarTitleDisplayMode(.inline).toolbar(.visible,for:.navigationBar).task { await client.loadComments(post.id) }
    }
}

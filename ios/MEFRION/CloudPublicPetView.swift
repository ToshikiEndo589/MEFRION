import SwiftUI

struct CloudPublicPetView:View {
    let petID:String
    @ObservedObject var client:CloudFamilyClient
    @State private var pet:CloudPublicPet?
    @State private var posts:[CloudPetRecentPost]=[]
    @State private var images:[String:UIImage]=[:]
    @State private var following=false
    @State private var authenticating=false
    @State private var blocking=false
    @State private var loading=true
    @State private var stamp=UUID()
    @Environment(\.scenePhase) private var phase
    private let columns=Array(repeating:GridItem(.flexible(),spacing:5),count:3)
    private var coverID:String? {posts.first?.media.first}
    private var cover:UIImage? {coverID.flatMap {images[$0] ?? client.publicImages[$0]}}
    var body:some View {
        ScrollView {
            if let pet {
                VStack(alignment:.leading,spacing:0) {
                    ZStack(alignment:.bottomLeading) {
                        Rectangle().fill(Theme.accent.opacity(0.1))
                        if let cover {Image(uiImage:cover).resizable().scaledToFill().frame(maxWidth:.infinity).frame(height:225).clipped()}
                        LinearGradient(colors:[.clear,.black.opacity(0.22)],startPoint:.center,endPoint:.bottom)
                        HStack(spacing:5) {
                            Image(systemName:"heart.fill").font(.caption2)
                            Text("good pet days").font(.caption.weight(.semibold))
                        }.foregroundStyle(.white).padding(12)
                    }.frame(height:225).clipped()
                    HStack(alignment:.bottom,spacing:12) {
                        ZStack {
                            Circle().fill(Theme.background)
                            if let icon=pet.icon {ProfileIconImage(encoded:icon,size:82)}
                            else if let cover {Image(uiImage:cover).resizable().scaledToFill().clipShape(Circle())}
                            else {Image(systemName:"pawprint.fill").font(.system(size:32)).foregroundStyle(Theme.accent)}
                        }.frame(width:82,height:82).overlay {Circle().stroke(.white,lineWidth:4)}
                            .shadow(color:Theme.accent.opacity(0.18),radius:8,y:4)
                        Spacer()
                        Button {
                            if client.authenticated {
                                Task {await client.perform {try await client.follow(pet:petID,enabled:!following);following.toggle()}}
                            } else {authenticating=true}
                        } label: {
                            Label(following ? "フォロー中" : "フォロー",systemImage:following ? "checkmark" : "heart.fill")
                                .font(.subheadline.bold()).foregroundStyle(following ? Theme.actionText : .white)
                                .padding(.horizontal,20).frame(minHeight:42)
                                .background(following ? Theme.accent.opacity(0.11) : Theme.accent,in:Capsule())
                        }.buttonStyle(.plain).disabled(client.busy)
                            .accessibilityIdentifier("public-pet-follow")
                    }.padding(.horizontal,18).padding(.top,-34)
                    VStack(alignment:.leading,spacing:8) {
                        HStack(alignment:.firstTextBaseline,spacing:8) {
                            Text(pet.name).font(.system(size:25,weight:.bold,design:.rounded)).foregroundStyle(Theme.text)
                            Image(systemName:"pawprint.fill").font(.caption).foregroundStyle(Theme.accent)
                        }
                        if let breed=visibleBreed(pet) {
                            Text(breed).font(.subheadline).foregroundStyle(Theme.secondaryText)
                        }
                        if !stockPet,let introduction=pet.introduction,!introduction.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {
                            Text(introduction).font(.subheadline).foregroundStyle(Theme.text).lineLimit(3)
                        }
                        HStack(spacing:5) {
                            Image(systemName:"square.grid.2x2.fill").foregroundStyle(Theme.accent)
                            Text("投稿  \(posts.count)").fontWeight(.semibold)
                        }.font(.caption).foregroundStyle(Theme.secondaryText).padding(.top,4)
                    }.padding(.horizontal,18).padding(.top,12).padding(.bottom,20)
                    HStack {
                        Text("この子の毎日 ♡").font(.headline).foregroundStyle(Theme.text)
                        Spacer()
                        Text("\(posts.count)件").font(.caption).foregroundStyle(Theme.secondaryText)
                    }.padding(.horizontal,18).padding(.bottom,10)
                    if posts.isEmpty {
                        ContentUnavailableView("投稿はまだありません",systemImage:"heart.text.square",description:Text("かわいい瞬間を待っています"))
                    } else {
                        LazyVGrid(columns:columns,spacing:5) {
                            ForEach(posts) {post in
                                NavigationLink {CloudDiscoveryView(client:client,detail:post.id,preview:post,profile:pet,previewImage:post.media.first.flatMap {images[$0] ?? client.publicImages[$0]})} label: {
                                    GeometryReader {geometry in
                                        ZStack {
                                            Rectangle().fill(Theme.accent.opacity(0.08))
                                            if let id=post.media.first,let image=images[id] ?? client.publicImages[id] {
                                                Image(uiImage:image).resizable().scaledToFill()
                                                    .frame(width:geometry.size.width,height:geometry.size.height).clipped()
                                            } else {Image(systemName:"pawprint.fill").font(.title2).foregroundStyle(Theme.accent.opacity(0.5))}
                                        }.frame(width:geometry.size.width,height:geometry.size.height)
                                            .clipShape(RoundedRectangle(cornerRadius:10))
                                    }.aspectRatio(1,contentMode:.fit)
                                }.buttonStyle(.plain).accessibilityLabel(pet.name+"の投稿を開く")
                                    .accessibilityIdentifier("public-pet-post-"+post.id)
                            }
                        }.padding(.horizontal,10)
                    }
                }.padding(.bottom,24)
            } else if loading {
                PawLoadingView(title:"プロフィールを開いています").padding(.top,100)
            } else {
                ContentUnavailableView("プロフィールを表示できません",systemImage:"pawprint",description:Text("公開状態を確認してください"))
            }
            if let error=client.error {Text(error).font(.footnote).foregroundStyle(.red).padding(18)}
        }.background(Theme.background).navigationTitle(pet?.name ?? "プロフィール")
            .navigationBarTitleDisplayMode(.inline).protectWhenInactive()
            .toolbar {if client.authenticated,pet != nil {
                Menu {Button("ブロック",systemImage:"person.crop.circle.badge.xmark",role:.destructive) {blocking=true}}
                label: {Image(systemName:"ellipsis").frame(width:36,height:36)}
                    .accessibilityLabel("プロフィールのメニュー")
            }}
        .task {await load()}
        .onChange(of:client.currentUserID) {_,_ in stamp=UUID();pet=nil;posts=[];images=[:];Task {await load()}}
        .onChange(of:phase) {_,p in if p == .active {Task {await load()}}}
        .onDisappear {stamp=UUID()}
        .sheet(isPresented:$authenticating) {AuthenticationSheet(client:client)}
        .confirmationDialog("相手のすべてのPetをブロックしますか？",isPresented:$blocking) {Button("ブロック",role:.destructive) {Task {await client.perform {try await client.block(pet:petID,enabled:true);stamp=UUID();pet=nil;posts=[];images=[:]}}}}
    }
    private var stockPet:Bool {pet?.name.hasPrefix("MEFRIONセレクト")==true || (posts.first.map {$0.body.hasPrefix("【MEFRION運営・検証投稿】") || $0.body.hasPrefix("運営セレクトの参考写真です。撮影:")} ?? false)}
    private func visibleBreed(_ pet:CloudPublicPet)->String? {
        guard let breed=pet.breed?.trimmingCharacters(in:.whitespacesAndNewlines),!breed.isEmpty,
              !["犬種未確認","猫種未確認","犬種未登録","猫種未登録"].contains(breed) else {return nil}
        return stockPet ? breed.replacingOccurrences(of:"（推定）",with:"") : breed
    }
    private func load() async {
        let current=UUID();stamp=current;loading=pet==nil
        do {
            async let profileTask=client.publicPet(petID)
            async let postsTask=client.petRecentPosts(petID)
            let (profile,recent)=try await (profileTask,postsTask)
            guard stamp==current else {return}
            pet=profile;posts=recent;loading=false
            following=client.publicPosts.first(where:{$0.pet_id==profile.id})?.following ?? following
            var seen=Set<String>()
            let mediaIDs=recent.compactMap{$0.media.first}.filter {seen.insert($0).inserted}
            for id in mediaIDs {if let cached=client.publicImages[id] {images[id]=cached}}
            if let coverID=mediaIDs.first,images[coverID]==nil,let image=try? await client.twinsImage(coverID),stamp==current {
                images[coverID]=image
            }
            await withTaskGroup(of:(String,UIImage?).self) {group in
                for id in mediaIDs where images[id]==nil {
                    group.addTask {let image=try? await client.twinsImage(id);return (id,image)}
                }
                for await (id,image) in group {
                    if let image,stamp==current {images[id]=image}
                }
            }
            let fresh=try await client.publicPet(petID)
            let currentPosts=try await client.petRecentPosts(petID)
            guard stamp==current else {return}
            let allowed=Set(currentPosts.compactMap{$0.media.first})
            images=images.filter{allowed.contains($0.key)}
            pet=fresh;posts=currentPosts
        } catch {
            guard stamp==current else {return}
            pet=nil;posts=[];images=[:];loading=false
        }
    }
}

struct CloudSharedPublicationView:View {
    let id:String
    let twins:Bool
    @ObservedObject var client:CloudFamilyClient
    @State private var ready=false
    @State private var message="写真を準備しています。しばらくしてからご確認ください。"
    @Environment(\.scenePhase) private var phase
    var body:some View {
        VStack(spacing:20) {
            Text("共有ページ").font(.title2.bold());Text(message)
            Button("公開状態を確認") {Task {await refresh()}}.buttonStyle(CoralButtonStyle())
            if ready,let url=client.sharedURL(id) {ShareLink("共有リンクを送る",item:url);Link("共有ページを開く",destination:url)}
            Text("家族の原本URLは共有しません。MEFRION管理下の共有は取り消せます。共有先に保存されたコピーは削除と連動しません。").font(.caption)
            Button("共有を取り消す",role:.destructive) {Task {await client.perform {if twins {try await client.stopTwinsShare(id)} else {try await client.stopPublication(id:id)};ready=false;message="共有を取り消しました。"}}}
            if let error=client.error {Text(error).foregroundStyle(.red)}
        }.padding(24).navigationTitle("共有確認").protectWhenInactive().task {await refresh()}
        .onChange(of:phase) {_,p in if p != .active {ready=false} else {Task {await refresh()}}}
        .onChange(of:client.currentUserID) {_,_ in ready=false}
    }
    private func refresh() async {ready=false;await client.perform {let projection=try await client.sharedProjection(id);ready=projection != nil;message=ready ? "共有する写真の準備ができたよ ♡" : "写真を準備中、または共有が終了しています。"}}
}

import SwiftUI
import Vision

private enum AlbumGestureKind:String,CaseIterable,Identifiable {
    case sleep,lick,sit,belly,run,look
    var id:String {rawValue}
    var title:String {
        switch self {
        case .sleep:"ねむねむ"
        case .lick:"ぺろっ"
        case .sit:"おすわり"
        case .belly:"ごろーん"
        case .run:"ダッシュ"
        case .look:"じーっ"
        }
    }
    var emoji:String {
        switch self {
        case .sleep:"💤"
        case .lick:"😋"
        case .sit:"🐾"
        case .belly:"♡"
        case .run:"✨"
        case .look:"👀"
        }
    }
    var tint:Color {
        switch self {
        case .sleep:Color(red:0.88,green:0.85,blue:1)
        case .lick:Color(red:1,green:0.88,blue:0.83)
        case .sit:Color(red:1,green:0.93,blue:0.78)
        case .belly:Color(red:1,green:0.85,blue:0.9)
        case .run:Color(red:0.85,green:0.94,blue:0.87)
        case .look:Color(red:0.84,green:0.93,blue:1)
        }
    }
}

private struct AlbumPetPicker:View {
    let pets:[CloudPet]
    @Binding var selected:String
    var body:some View {
        if pets.count>1 {
            ScrollView(.horizontal,showsIndicators:false) {
                HStack(spacing:8) {
                    ForEach(pets) {pet in
                        Button(pet.name) {selected=pet.id}
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(selected==pet.id ? .white : Theme.actionText)
                            .padding(.horizontal,16).frame(minHeight:36)
                            .background(selected==pet.id ? Theme.accent : .white,in:Capsule())
                    }
                }.padding(.horizontal,16)
            }.accessibilityIdentifier("album-feature-pet-picker")
        }
    }
}

private struct AlbumFeaturePhoto:View {
    let id:String
    let image:UIImage?
    let height:CGFloat
    var body:some View {
        GeometryReader {geometry in
            Group {
                if let image {Image(uiImage:image).resizable().scaledToFill()}
                else {Rectangle().fill(Theme.accent.opacity(0.09)).overlay {Image(systemName:"pawprint.fill").foregroundStyle(Theme.accent.opacity(0.5))}}
            }
            .frame(width:geometry.size.width,height:height).clipped()
        }
        .frame(height:height)
        .clipShape(RoundedRectangle(cornerRadius:16))
        .accessibilityIdentifier("album-feature-photo-"+id)
    }
}

struct CloudThenNowView:View {
    @ObservedObject private var client=CloudFamilyClient.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var petID=""
    @State private var photos:[CloudPhoto]=[]
    @State private var images:[String:UIImage]=[:]
    @State private var firstID=""
    @State private var secondID=""
    @State private var cards:[CloudCard]=[]
    @State private var choosingFirst=false
    @State private var choosingSecond=false
    @State private var loading=true
    @State private var saving=false
    @State private var saved:CloudCard?
    @State private var error:String?
    @State private var generation=UUID()
    private var pet:CloudPet? {client.pets.first {$0.id==petID}}
    private var stillPhotos:[CloudPhoto] {photos.filter {$0.media_kind != "video"}}
    private var first:CloudPhoto? {photos.first {$0.id==firstID}}
    private var second:CloudPhoto? {photos.first {$0.id==secondID}}
    private var sortedPhotos:[CloudPhoto] {
        stillPhotos.sorted {a,b in
            (a.captured ?? a.created_at ?? "") < (b.captured ?? b.created_at ?? "")
        }
    }
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:18) {
                VStack(alignment:.leading,spacing:5) {
                    Text("あの頃と今 ♡").font(.system(size:28,weight:.bold,design:.rounded)).foregroundStyle(Theme.actionText)
                    Text("小さかったあの日も、今日も、だいすき。")
                        .font(.subheadline).foregroundStyle(Theme.secondaryText)
                }.padding(.horizontal,16)
                AlbumPetPicker(pets:client.pets,selected:$petID)
                if loading {
                    PawLoadingView(title:"思い出を探しているよ",compact:true).padding(.top,40)
                } else if sortedPhotos.count<2 {
                    ContentUnavailableView("写真が2枚あると楽しめるよ",systemImage:"heart.text.square",description:Text("投稿タブからアルバムに残してね"))
                } else {
                    HStack(alignment:.top,spacing:10) {
                        memoryPhoto(first,caption:"あの頃",isFirst:true)
                        memoryPhoto(second,caption:"いま",isFirst:false)
                    }.padding(12).background(.white,in:RoundedRectangle(cornerRadius:24))
                        .padding(.horizontal,16)
                    if saved != nil {
                        Label("思い出カードに残したよ ♡",systemImage:"heart.fill")
                            .font(.subheadline.bold()).foregroundStyle(Theme.actionText)
                            .frame(maxWidth:.infinity)
                    } else {
                        Button {save()} label: {
                            Text(saving ? "保存中…" : "この2枚を残す ♡")
                                .font(.headline).foregroundStyle(.white)
                                .frame(maxWidth:.infinity,minHeight:50)
                                .background(Theme.accent.gradient,in:Capsule())
                        }.disabled(saving || firstID.isEmpty || secondID.isEmpty || firstID==secondID)
                            .padding(.horizontal,16).accessibilityIdentifier("then-now-save")
                    }
                    if let error {Text(error).font(.footnote).foregroundStyle(.red).padding(.horizontal,16)}
                    if let pet,!cards.isEmpty {
                        VStack(alignment:.leading,spacing:10) {
                            Text("残した思い出").font(.headline)
                            ForEach(cards) {card in
                                NavigationLink {
                                    CloudComparisonView(pet:pet,ids:[card.first,card.second],client:client,existing:card)
                                } label: {
                                    HStack {
                                        Image(systemName:"heart.text.square.fill").foregroundStyle(Theme.accent)
                                        Text(card.layout.text?.isEmpty == false ? card.layout.text! : "あの頃と今")
                                            .lineLimit(1)
                                        Spacer();Image(systemName:"chevron.right").font(.caption)
                                    }.foregroundStyle(Theme.text).padding(15)
                                        .background(.white,in:RoundedRectangle(cornerRadius:16))
                                }
                            }
                        }.padding(.horizontal,16)
                    }
                }
            }.padding(.vertical,14)
        }.background(Theme.background).navigationTitle("あの頃と今").navigationBarTitleDisplayMode(.inline)
            .task {await initialize()}
            .refreshable {if !petID.isEmpty {await reload(petID)}}
            .onChange(of:petID) {_,id in if !id.isEmpty {Task {await reload(id)}}}
            .onChange(of:client.currentUserID) {_,_ in clear();Task {await initialize()}}
            .onChange(of:scenePhase) {_,phase in if phase != .active {images=[:]} }
            .sheet(isPresented:$choosingFirst) {picker(isFirst:true)}
            .sheet(isPresented:$choosingSecond) {picker(isFirst:false)}
            .protectWhenInactive()
    }
    private func memoryPhoto(_ photo:CloudPhoto?,caption:String,isFirst:Bool)->some View {
        VStack(alignment:.leading,spacing:8) {
            if let photo {
                AlbumFeaturePhoto(id:photo.id,image:images[photo.id],height:190)
                    .task(id:photo.id) {await loadImage(photo.id)}
            } else {AlbumFeaturePhoto(id:"empty",image:nil,height:190)}
            Text(caption).font(.headline).foregroundStyle(Theme.actionText)
            Text(photo?.captured ?? "日付なし").font(.caption).foregroundStyle(Theme.secondaryText)
            Button("写真をかえる") {if isFirst {choosingFirst=true} else {choosingSecond=true}}
                .font(.caption.bold()).foregroundStyle(Theme.actionText)
                .frame(minHeight:36)
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
    private func picker(isFirst:Bool)->some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:10) {
                    ForEach(sortedPhotos) {photo in
                        Button {
                            if isFirst {firstID=photo.id;choosingFirst=false}
                            else {secondID=photo.id;choosingSecond=false}
                            saved=nil
                        } label: {
                            VStack(alignment:.leading,spacing:5) {
                                AlbumFeaturePhoto(id:photo.id,image:images[photo.id],height:150)
                                Text(photo.captured ?? "日付なし").font(.caption).foregroundStyle(Theme.secondaryText)
                            }
                        }.buttonStyle(.plain).task(id:photo.id) {await loadImage(photo.id)}
                    }
                }.padding(16)
            }.background(Theme.background).navigationTitle("写真をえらぶ")
                .toolbar {Button("閉じる") {choosingFirst=false;choosingSecond=false}}
        }.presentationDragIndicator(.visible)
    }
    private func clear() {
        generation=UUID();petID="";photos=[];images=[:];cards=[];firstID="";secondID="";saved=nil;error=nil;loading=true;saving=false
    }
    private func initialize() async {
        await client.restore()
        guard client.authenticated else {loading=false;return}
        if client.pets.isEmpty {try? await client.loadPets()}
        if petID.isEmpty {petID=client.pets.first?.id ?? ""}
    }
    private func reload(_ id:String) async {
        let stamp=UUID();generation=stamp
        loading=true;error=nil;photos=[];images=[:];cards=[];saved=nil;firstID="";secondID="";saving=false
        do {
            let loaded=try await client.albumPhotos(pet:id)
            let savedCards=(try? await client.cards(pet:id)) ?? []
            guard generation==stamp,petID==id else{return}
            photos=loaded;cards=savedCards
            let ordered=sortedPhotos
            if ordered.count>=2 {firstID=ordered.first!.id;secondID=ordered.last!.id}
            loading=false
            if ordered.count>=2 {await suggestSimilarPair(stamp:stamp)}
        } catch {
            guard generation==stamp else{return}
            self.error="思い出を読み込めなかったよ。下に引いてもう一度試してね。";loading=false
        }
    }
    private func loadImage(_ id:String) async {
        guard images[id]==nil,photos.contains(where:{$0.id==id}) else{return}
        let stamp=generation
        guard let image=try? await client.privatePhotoForDeviceSave(id),stamp==generation else{return}
        images[id]=image
    }
    private func suggestSimilarPair(stamp:UUID) async {
        let ordered=sortedPhotos
        let firstCandidates=Array(ordered.prefix(4))
        let lastCandidates=Array(ordered.suffix(4))
        for photo in firstCandidates+lastCandidates {
            guard stamp==generation else{return}
            await loadImage(photo.id)
        }
        guard stamp==generation,firstID==ordered.first?.id,secondID==ordered.last?.id else{return}
        var prints:[String:VNFeaturePrintObservation]=[:]
        for photo in firstCandidates+lastCandidates {
            guard let image=images[photo.id],let cg=image.cgImage else{continue}
            let request=VNGenerateImageFeaturePrintRequest()
            if (try? VNImageRequestHandler(cgImage:cg).perform([request])) != nil {
                prints[photo.id]=request.results?.first
            }
        }
        var best:Float = .greatestFiniteMagnitude
        var pair:(String,String)?
        for old in firstCandidates {
            for recent in lastCandidates where old.id != recent.id && old.captured != recent.captured {
                guard let a=prints[old.id],let b=prints[recent.id] else{continue}
                var distance:Float=0
                if (try? a.computeDistance(&distance,to:b)) != nil,distance<best {
                    best=distance;pair=(old.id,recent.id)
                }
            }
        }
        if let pair,stamp==generation {firstID=pair.0;secondID=pair.1}
    }
    private func save() {
        guard !saving,!firstID.isEmpty,!secondID.isEmpty,firstID != secondID else{return}
        saving=true;error=nil
        let pet=petID
        let oldPhoto=firstID
        let newPhoto=secondID
        Task {
            do {
                let id=try await client.saveCard(pet:pet,first:oldPhoto,second:newPhoto,text:"",zooms:[1,1],xs:[0.5,0.5],ys:[0.5,0.5],key:UUID())
                guard petID==pet else{return}
                if let refreshed=try? await client.cards(pet:pet) {cards=refreshed}
                saved=cards.first {$0.id==id} ?? CloudCard(
                    id:id,first:oldPhoto,second:newPhoto,
                    layout:CloudCardLayout(text:"",first_zoom:1,first_x:0.5,first_y:0.5,second_zoom:1,second_x:0.5,second_y:0.5),mine:true)
                if !cards.contains(where:{$0.id==id}),let saved {cards.insert(saved,at:0)}
            } catch {self.error="保存できなかったよ。もう一度試してね。"}
            saving=false
        }
    }
}

struct CloudGestureAtlasView:View {
    @ObservedObject private var client=CloudFamilyClient.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var petID=""
    @State private var photos:[CloudPhoto]=[]
    @State private var tags:[CloudAlbumGesture]=[]
    @State private var images:[String:UIImage]=[:]
    @State private var selected:AlbumGestureKind?
    @State private var busy:Set<String>=[]
    @State private var loading=true
    @State private var error:String?
    @State private var generation=UUID()
    private let columns=[GridItem(.flexible(),spacing:10),GridItem(.flexible(),spacing:10)]
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:16) {
                VStack(alignment:.leading,spacing:5) {
                    Text("うちの子しぐさ図鑑").font(.system(size:27,weight:.bold,design:.rounded)).foregroundStyle(Theme.actionText)
                    Text("かわいいしぐさ、集めちゃお ♡")
                        .font(.subheadline).foregroundStyle(Theme.secondaryText)
                }.padding(.horizontal,16)
                AlbumPetPicker(pets:client.pets,selected:$petID)
                if loading {PawLoadingView(title:"図鑑をひらいているよ",compact:true).padding(.top,36)}
                else {
                    Text("\(Set(tags.map(\.gesture)).count) / 6 しぐさ集まったよ")
                        .font(.subheadline.bold()).foregroundStyle(Theme.actionText).padding(.horizontal,16)
                    LazyVGrid(columns:columns,spacing:10) {
                        ForEach(AlbumGestureKind.allCases) {kind in
                            Button {selected=kind} label: {
                                VStack(alignment:.leading,spacing:8) {
                                    if let id=tags.first(where:{$0.gesture==kind.rawValue})?.photo_id {
                                        AlbumFeaturePhoto(id:id,image:images[id],height:140)
                                            .task(id:id) {await loadImage(id)}
                                    } else {
                                        ZStack {
                                            RoundedRectangle(cornerRadius:16).fill(kind.tint)
                                            Text(kind.emoji).font(.system(size:48))
                                        }.frame(height:140)
                                    }
                                    HStack {
                                        Text(kind.title).font(.headline)
                                        Spacer()
                                        Text("\(tags.filter{$0.gesture==kind.rawValue}.count)枚")
                                            .font(.caption.bold()).foregroundStyle(Theme.actionText)
                                    }
                                }.padding(8).background(.white,in:RoundedRectangle(cornerRadius:21))
                            }.buttonStyle(.plain).foregroundStyle(Theme.text)
                                .accessibilityIdentifier("gesture-category-"+kind.rawValue)
                        }
                    }.padding(.horizontal,12)
                    if photos.isEmpty {
                        Text("投稿タブからアルバムに残すと、ここで集められるよ。")
                            .font(.subheadline).foregroundStyle(Theme.secondaryText).padding(.horizontal,16)
                    }
                    if let error {Text(error).font(.footnote).foregroundStyle(.red).padding(.horizontal,16)}
                }
            }.padding(.vertical,14)
        }.background(Theme.background).navigationTitle("しぐさ図鑑").navigationBarTitleDisplayMode(.inline)
            .task {await initialize()}
            .refreshable {if !petID.isEmpty {await reload(petID)}}
            .onChange(of:petID) {_,id in if !id.isEmpty {Task {await reload(id)}}}
            .onChange(of:client.currentUserID) {_,_ in clear();Task {await initialize()}}
            .onChange(of:scenePhase) {_,phase in if phase != .active {images=[:]} }
            .sheet(item:$selected) {kind in categorySheet(kind)}
            .protectWhenInactive()
    }
    private func categorySheet(_ kind:AlbumGestureKind)->some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:12) {
                    Text(kind.emoji+" "+kind.title).font(.system(size:27,weight:.bold,design:.rounded))
                        .foregroundStyle(Theme.actionText)
                    Text("写真をタップして、図鑑に入れよう ♡")
                        .font(.subheadline).foregroundStyle(Theme.secondaryText)
                    if photos.isEmpty {Text("写真はまだないよ。投稿タブからアルバムに残してね。")}
                    LazyVGrid(columns:columns,spacing:10) {
                        ForEach(photos) {photo in
                            let checked=tags.contains {$0.photo_id==photo.id && $0.gesture==kind.rawValue}
                            Button {toggle(photo:photo,kind:kind,checked:checked)} label: {
                                AlbumFeaturePhoto(id:photo.id,image:images[photo.id],height:155)
                                    .overlay(alignment:.topTrailing) {
                                        Image(systemName:checked ? "checkmark.circle.fill" : "circle.fill")
                                            .font(.title2).foregroundStyle(checked ? Theme.accent : .white)
                                            .padding(8)
                                    }
                                    .opacity(busy.contains(photo.id) ? 0.55 : 1)
                            }.buttonStyle(.plain).disabled(busy.contains(photo.id))
                                .task(id:photo.id) {await loadImage(photo.id)}
                                .accessibilityLabel((checked ? "図鑑から外す、" : "図鑑に入れる、")+(photo.title.isEmpty ? "写真" : photo.title))
                        }
                    }
                    if let error {Text(error).font(.footnote).foregroundStyle(.red)}
                }.padding(16)
            }.background(Theme.background).navigationTitle(kind.title)
                .toolbar {Button("できた") {selected=nil}.fontWeight(.semibold)}
        }.presentationDragIndicator(.visible)
    }
    private func clear() {
        generation=UUID();petID="";photos=[];tags=[];images=[:];selected=nil;busy=[];loading=true;error=nil
    }
    private func initialize() async {
        await client.restore()
        guard client.authenticated else {loading=false;return}
        if client.pets.isEmpty {try? await client.loadPets()}
        if petID.isEmpty {petID=client.pets.first?.id ?? ""}
    }
    private func reload(_ id:String) async {
        let stamp=UUID();generation=stamp;loading=true;error=nil;photos=[];tags=[];images=[:]
        do {
            let loaded=try await client.albumPhotos(pet:id)
            let labels=try await client.albumGestures(pet:id)
            guard stamp==generation,petID==id else{return}
            photos=loaded.sorted {($0.captured ?? $0.created_at ?? "") > ($1.captured ?? $1.created_at ?? "")}
            tags=labels;loading=false
        } catch {
            guard stamp==generation else{return}
            self.error="図鑑を読み込めなかったよ。下に引いてもう一度試してね。";loading=false
        }
    }
    private func loadImage(_ id:String) async {
        guard images[id]==nil,photos.contains(where:{$0.id==id}) else{return}
        let stamp=generation
        guard let image=try? await client.privatePhotoForDeviceSave(id),stamp==generation else{return}
        images[id]=image
    }
    private func toggle(photo:CloudPhoto,kind:AlbumGestureKind,checked:Bool) {
        let id=photo.id,pet=petID,code=kind.rawValue
        guard !busy.contains(id) else{return}
        busy.insert(id);error=nil
        Task {
            do {
                try await client.setAlbumGesture(pet:pet,photo:id,gesture:code,enabled:!checked)
                guard pet==petID else{return}
                if checked {tags.removeAll {$0.photo_id==id && $0.gesture==code}}
                else {tags.insert(CloudAlbumGesture(photo_id:id,gesture:code),at:0)}
            } catch {self.error="保存できなかったよ。もう一度タップしてね。"}
            busy.remove(id)
        }
    }
}

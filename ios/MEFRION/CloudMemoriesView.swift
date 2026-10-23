import SwiftUI
import Photos

struct CloudMemoriesView:View {
    let pet:CloudPet
    @ObservedObject var client:CloudFamilyClient
    @State private var selected:[String]=[]
    @State private var cards:[CloudCard]=[]
    @State private var sameDay=false
    @Environment(\.scenePhase) private var phase
    private var visible:[CloudPhoto] {
        guard sameDay else{return client.photos}
        let today=DateFormatter();today.dateFormat="MM-dd";let suffix=today.string(from:Date())
        return client.photos.filter{($0.captured?.count ?? 0)==10 && $0.captured!.suffix(5)==suffix}
    }
    var body:some View {
        ScrollView {VStack(alignment:.leading,spacing:16) {
            Toggle("今日と同じ月日の思い出",isOn:$sameDay)
            if sameDay {Text("日付まで分かる写真から選びます。年・月だけの写真は同じ日として扱いません。").font(.caption)}
            LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible()),GridItem(.flexible())]) {ForEach(visible) {photo in Button {
                if selected.contains(photo.id) {selected.removeAll{$0==photo.id}} else if selected.count<2 {selected.append(photo.id)}
            } label: {VStack {if let image=client.images[photo.id] {Image(uiImage:image).resizable().scaledToFill().frame(height:110).clipped().overlay(alignment:.topTrailing) {if selected.contains(photo.id) {Image(systemName:"checkmark.circle.fill").foregroundStyle(Theme.accent).padding(5)}}};Text(photo.captured ?? "日付不明").font(.caption)}}.accessibilityIdentifier("cloud-memory-photo-"+photo.id)}}
            if selected.count==2 {NavigationLink("2枚で思い出カードを作る") {CloudComparisonView(pet:pet,ids:selected,client:client)}}
            Text("保存した思い出カード・家族内のみ").font(.headline)
            ForEach(cards) {card in NavigationLink("あの頃と今") {CloudComparisonView(pet:pet,ids:[card.first,card.second],client:client,existing:card)}}
            if let error=client.error {Text(error).foregroundStyle(.red)}
        }.padding(16)}.background(Theme.background).navigationTitle("振り返り・あの頃と今").protectWhenInactive()
        .task {await client.performRefresh {try await client.loadAlbum(pet:pet.id);cards=try await client.cards(pet:pet.id)}}
        .onChange(of:client.currentUserID) {_,_ in selected=[];cards=[]}
        .onChange(of:phase) {_,p in if p != .active {selected=[];cards=[];client.clearPrivateViews()} else {Task {await client.perform {try await client.loadAlbum(pet:pet.id);cards=try await client.cards(pet:pet.id)}}}}
    }
}

struct CloudComparisonView:View {
    let pet:CloudPet;let ids:[String]
    @ObservedObject var client:CloudFamilyClient
    var existing:CloudCard?=nil
    @State private var zooms=[1.0,1.0]
    @State private var xs=[0.5,0.5]
    @State private var ys=[0.5,0.5]
    @State private var text=""
    @State private var key=UUID()
    @State private var savedID:String?
    @State private var message:String?
    @State private var confirmExport=false
    @State private var confirmPage=false
    @State private var sharedID:String?
    @State private var shareKey=UUID()
    @State private var exported:UIImage?
    @State private var sharing=false
    @State private var deleting=false
    @State private var loading=true
    @Environment(\.scenePhase) private var phase
    private var photos:[CloudPhoto] {ids.compactMap{id in client.photos.first{$0.id==id}}}
    private var cropped:[UIImage] {ids.enumerated().compactMap {index,id in guard index<2,let image=client.images[id] else{return nil};return try? PrivateImageCrop.crop(image,zoom:zooms[index],x:xs[index],y:ys[index])}}
    private var layout:some View {
        VStack(spacing:18) {
            Text("あの頃と今").font(.system(size:30,weight:.bold)).foregroundStyle(Theme.accent)
            Text("ずっと、いっしょに。♡").foregroundStyle(Theme.accent)
            Text(pet.name).font(.headline)
            Spacer(minLength:8)
            HStack(spacing:12) {ForEach(Array(cropped.enumerated()),id:\.offset) {index,image in VStack(spacing:8) {
                Image(uiImage:image).resizable().scaledToFill().frame(width:140,height:210).clipped()
                Text(photos.indices.contains(index) ? (photos[index].captured ?? "日付不明") : "日付不明").font(.caption)
            }.padding(8).background(.white).rotationEffect(.degrees(index==0 ? -3 : 3)).shadow(color:Theme.accent.opacity(0.12),radius:4,y:3)}}
            Spacer(minLength:8);Text(text).font(.subheadline).multilineTextAlignment(.center).lineLimit(5)
            Spacer(minLength:8);Text("MEFRION").font(.headline).foregroundStyle(Theme.accent)
        }.padding(20).frame(width:360,height:640).background(Theme.background)
    }
    var body:some View {
        ScrollView {VStack(spacing:16) {
            if photos.count==2 && cropped.count==2 {layout.scaleEffect(0.9).frame(height:590)} else {Text("写真を読み込めません。削除・家族権限の変更を確認してください。").foregroundStyle(.secondary)}
            ForEach(0..<2,id:\.self) {i in VStack(alignment:.leading) {Text("写真\(i+1)の調整");Slider(value:$zooms[i],in:1...3);Slider(value:$xs[i],in:0...1);Slider(value:$ys[i],in:0...1)}}
            TextField("短い文章（200字まで）",text:$text,axis:.vertical)
            Button("家族内にカードを保存") {Task {await client.perform {guard ids.count==2 else{return};savedID=try await client.saveCard(pet:pet.id,first:ids[0],second:ids[1],text:text,zooms:zooms,xs:xs,ys:ys,key:key);message="家族内のみで保存しました。"}}}.buttonStyle(CoralButtonStyle()).disabled(client.busy || photos.count != 2 || text.count>200).accessibilityIdentifier("cloud-card-save")
            if pet.role=="owner",savedID != nil {Button("写真保存・共有の確認へ") {confirmExport=true}.disabled(client.busy)}
            if pet.role=="owner",savedID != nil {Button("公開共有ページを作る") {confirmPage=true};if let sharedID {NavigationLink("共有ページの状態・取消") {CloudSharedPublicationView(id:sharedID,twins:false,client:client)}}}
            if let image=exported {Text("\(Int(image.size.width * image.scale)) × \(Int(image.size.height * image.scale))").accessibilityIdentifier("cloud-card-output-size");HStack {
                Button("写真に保存する") {Task {let status=await PHPhotoLibrary.requestAuthorization(for:.addOnly);guard status == .authorized || status == .limited else {message="写真への保存を許可すると利用できます。";return};do {try await PHPhotoLibrary.shared().performChanges {PHAssetChangeRequest.creationRequestForAsset(from:image)};message="写真に保存しました。"} catch {message="写真を保存できませんでした。"}}}
                Button("共有シートを開く") {sharing=true}
            }}
            if existing?.mine==true {Button("このカードを削除",role:.destructive) {deleting=true}}
            if let message {Text(message)};if let error=client.error {Text(error).foregroundStyle(.red)}
        }.padding(16)}.background(Theme.background).navigationTitle("思い出カード").protectWhenInactive()
        .task {text=existing?.layout.text ?? "";savedID=existing?.id;if let l=existing?.layout {zooms=[l.first_zoom ?? 1,l.second_zoom ?? 1];xs=[l.first_x ?? 0.5,l.second_x ?? 0.5];ys=[l.first_y ?? 0.5,l.second_y ?? 0.5]};await client.performRefresh {try await client.loadAlbum(pet:pet.id)};loading=false}
        .onChange(of:text) {_,_ in invalidate()}.onChange(of:zooms) {_,_ in invalidate()}.onChange(of:xs) {_,_ in invalidate()}.onChange(of:ys) {_,_ in invalidate()}
        .onChange(of:phase) {_,p in if p != .active {exported=nil;sharing=false} else {Task {await client.perform {try await client.loadAlbum(pet:pet.id)}}}}
        .onChange(of:client.currentUserID) {_,_ in exported=nil;sharing=false;savedID=nil}
        .sheet(isPresented:$sharing) {if let image=exported {NativeImageShare(image:image)}}
        .confirmationDialog("選んだ2枚を端末へ書き出しますか？提供者の外部共有同意を再確認します。保存・共有先の画像は、MEFRIONでの削除と連動しません。",isPresented:$confirmExport,titleVisibility:.visible) {Button("同意を確認して書き出す") {Task {await client.perform {
            guard let id=savedID else{return};try await client.authorizeCardExport(id:id);try await client.loadAlbum(pet:pet.id)
            guard photos.count==2,cropped.count==2 else {throw CocoaError(.fileReadNoSuchFile)}
            let renderer=ImageRenderer(content:layout);renderer.scale=3;exported=renderer.uiImage;message="9:16のカードを作成しました。"
        }}}}
        .confirmationDialog("2枚を公開共有ページに掲載しますか？公開Petプロフィールと全提供者の外部共有同意が必要です。家族原本は非公開のままです。",isPresented:$confirmPage,titleVisibility:.visible) {Button("同意を確認して共有ページを作る") {Task {await client.perform {guard let id=savedID else{return};let result=try await client.shareCard(id:id,key:shareKey);sharedID=result.id;message="共有を受け付けました。状態を確認できます。"}}}}
        .confirmationDialog("家族内のカードを削除しますか？",isPresented:$deleting) {Button("削除",role:.destructive) {Task {await client.perform {if let id=existing?.id {try await client.deleteCard(id:id);savedID=nil;message="カードを削除しました。"}}}}}
    }
    private func invalidate() {guard !loading else{return};key=UUID();savedID=nil;exported=nil;sharedID=nil;shareKey=UUID()}
}
struct NativeImageShare:UIViewControllerRepresentable {
    let image:UIImage
    func makeUIViewController(context:Context)->UIActivityViewController {UIActivityViewController(activityItems:[image],applicationActivities:nil)}
    func updateUIViewController(_ controller:UIActivityViewController,context:Context) {}
}

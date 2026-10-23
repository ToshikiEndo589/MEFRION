import SwiftUI
import PhotosUI
import CryptoKit
import ImageIO
import AVFoundation

struct CloudTwinsView:View {
    @Environment(\.scenePhase) private var phase
    @ObservedObject private var client=CloudFamilyClient.shared
    @State private var image:UIImage?
    @State private var picker:PhotosPickerItem?
    @State private var species="dog"
    @State private var loading=false
    @State private var state=""
    @State private var message:String?
    @State private var candidates:[CloudTwinCandidate]=[]
    @State private var images:[String:UIImage]=[:]
    @State private var generation=UUID()
    @State private var key=UUID()
    @State private var deadline:Date?
    @State private var authenticating=false
    @State private var showCamera=false
    @State private var cameraSession=false
    @State private var pendingCamera=false
    @State private var pendingCaptured:UIImage?
    @State private var cameraFailure:String?
    @State private var cameraNeedsSettings=false
    @State private var crop:Crop?
    @State private var history:[CloudTwinsHistory]=[]
    @State private var searchID:String?
    @State private var selectedProfile:CloudTwinCandidate?
    @State private var albumPicking=false
    @State private var queryPhoto:CloudPhoto?
    @State private var queryPet:CloudPet?
    @State private var confirmShare=false
    @State private var sharedID:String?
    @State private var shareKey=UUID()
    private let engine=VisionPetRanker()
    private struct Crop:Identifiable {let id=UUID();let image:UIImage}
    var body:some View {
        ScrollView {VStack(spacing:18) {
            HStack {Label("そっくり",systemImage:"pawprint.fill").font(.headline).accessibilityIdentifier("twins-compact-heading").foregroundStyle(Theme.actionText);Spacer();Button("検索履歴") {if client.authenticated {Task {await client.perform {history=try await client.twinsHistory()}}} else {authenticating=true}}.frame(minWidth:44,minHeight:44).contentShape(Rectangle())}
            PhotoHero(image:image ?? UIImage(named:"pet-0")!,height:250)
            HStack {
                PhotosPicker(selection:$picker,matching:.images) {Label("写真を選ぶ",systemImage:"photo")}.buttonStyle(CoralButtonStyle())
                Button("写真を撮る",systemImage:"camera") {openCamera()}.buttonStyle(CoralButtonStyle())
            }.disabled(loading)
            if client.authenticated {Button("うちの子のアルバムから選ぶ") {albumPicking=true}}
            Button("所有イラストで試す") {replace(UIImage(named:species=="dog" ? "pet-0" : "pet-1"))}.accessibilityIdentifier("cloud-twins-demo")
            if let image {Button("写真を確認・切り抜く") {crop=Crop(image:image)}}
            Picker("犬・猫を確認・修正",selection:$species) {Text("犬").tag("dog");Text("猫").tag("cat")}.pickerStyle(.segmented).disabled(loading)
            Text("犬・猫の領域を確認し、写真の特徴を端末内で比較します。血縁や同じ個体の判定ではありません。実写真での類似品質は評価待ちです。").font(.caption)
            Text("「この写真で検索する」を押すと、入力画像は端末内で比較します。画像そのものはサーバーへ送信しません。10分経過・画面終了・アプリがバックグラウンドへ移った際に破棄します。公開候補を取得し、検索記録には候補IDと状態を保存します。ゲスト初回1回・会員5回/日（日本時間・暫定）。").font(.caption)
            Button(state=="failure" ? "この入力で再試行" : "この写真で検索する") {Task {await search()}}.buttonStyle(CoralButtonStyle()).disabled(image==nil || loading).accessibilityIdentifier("cloud-twins-search")
            if loading {ProgressView("そっくりな子を探しています")}
            if state=="results",let main=candidates.first,let candidateImage=images[main.id] {
                VStack(spacing:14) {Text("似ている候補が見つかりました").font(.headline);PhotoHero(image:candidateImage,height:300).frame(maxWidth:.infinity);if let image {HStack(spacing:10) {Image(uiImage:image).resizable().scaledToFill().frame(width:64,height:64).clipped().clipShape(RoundedRectangle(cornerRadius:12));Image(systemName:"heart.fill").foregroundStyle(Theme.actionText);Text("うちの子と似ている子").font(.subheadline.bold());Spacer()}};Text(main.name).font(.title3.bold());Text("類似度をパーセントに換算して表示しません。").font(.caption)}.padding(16).frame(maxWidth:.infinity).background(Theme.accent.opacity(0.07)).clipShape(RoundedRectangle(cornerRadius:20)).accessibilityIdentifier("cloud-twins-main")
                if main.demo_only==true {Text("権利確認済みの検証イラストです。実在のPetの類似品質を示しません。").font(.caption)}
                Button("公開プロフィール・最近の投稿") {selectedProfile=main}
                HStack {Button("似ている") {Task {await feedback(true,candidate:main.id)}};Button("ちょっと違う") {Task {await feedback(false,candidate:main.id)}}}
                if client.authenticated,queryPhoto != nil,searchID != nil {Button("この結果の共有を確認") {confirmShare=true}}
                if let sharedID {NavigationLink("共有の状態・取消") {CloudSharedPublicationView(id:sharedID,twins:true,client:client)}}
                HStack {ForEach(Array(candidates.dropFirst().prefix(2))) {candidate in VStack {if let image=images[candidate.id] {PhotoHero(image:image,height:185)};Button(candidate.name) {selectedProfile=candidate}}.frame(maxWidth:.infinity)}}
            } else if state=="insufficient" {ContentUnavailableView("そっくりな子が見つかりませんでした",systemImage:"pawprint",description:Text("公開候補が足りない場合もあります。別の写真でお試しください。"))}
            if let message {Text(message).foregroundStyle(.secondary)}
            if !client.authenticated {Button("ログインして続ける") {authenticating=true}}
            Button("入力と結果を破棄") {replace(nil)}
            if !history.isEmpty {Text("検索履歴").font(.headline);ForEach(history) {record in VStack(alignment:.leading) {Text(record.created_at.prefix(10));Text(record.state);Text(record.candidates.isEmpty ? record.state=="results" ? "掲載終了：公開候補は現在表示できません" : "現在表示できる公開候補はありません" : record.candidates.map(\.name).joined(separator:"・"))}.frame(maxWidth:.infinity,alignment:.leading)}}
            if let error=client.error {Text(error).foregroundStyle(.red)}
        }.padding(.horizontal,16).padding(.top,0).padding(.bottom,8)}.navigationTitle("そっくり").toolbar(.hidden,for:.navigationBar).background(Theme.background).protectWhenInactive()
        .sheet(isPresented:$authenticating) {AuthenticationSheet(client:client)}
        .sheet(item:$selectedProfile) {candidate in NavigationStack {CloudPublicPetView(petID:candidate.pet_id,client:client)}}
        .sheet(isPresented:$albumPicking) {NavigationStack {CloudTwinsAlbumPicker(client:client) {photo,pet,image in replace(image);queryPhoto=photo;queryPet=pet;albumPicking=false}}}
        .confirmationDialog("自分のPetプロフィールと選んだ写真を公開共有に使いますか？自分が提供した写真の外部共有同意を記録します。相手の外部共有同意も必要です。",isPresented:$confirmShare,titleVisibility:.visible) {Button("明示同意して共有を作る") {Task {await client.perform {guard let searchID,let queryPhoto,let queryPet,let candidate=candidates.first else{return};if queryPhoto.mine {try await client.consent(photo:queryPhoto.id,purpose:"external_share",allowed:true)};try await client.setPublicProfile(pet:queryPet.id,enabled:true,explicit:true);let result=try await client.shareTwins(search:searchID,query:queryPhoto.id,candidate:candidate.id,key:shareKey);sharedID=result.id;message="共有を受け付けました。"}}}}
        .sheet(item:$crop) {input in NavigationStack {PrivateCropView(image:input.image) {replace($0)}}}
        .fullScreenCover(isPresented:$showCamera,onDismiss:{if let captured=pendingCaptured {replace(captured)};pendingCaptured=nil;cameraSession=false}) {
            PrivateCameraCapture(onCapture:{pendingCaptured=$0;showCamera=false},onCancel:{showCamera=false})
                .ignoresSafeArea()
                .background(.black)
                .protectWhenInactive()
        }
        .alert("カメラを開けません",isPresented:Binding(get:{cameraFailure != nil},set:{if !$0 {cameraFailure=nil}})) {
            if cameraNeedsSettings {Button("設定を開く") {if let url=URL(string:UIApplication.openSettingsURLString) {UIApplication.shared.open(url)}}}
            Button("閉じる",role:.cancel) {cameraFailure=nil}
        } message: {Text(cameraFailure ?? "")}
        .onChange(of:picker) {_,item in guard let item else{return};let stamp=UUID();generation=stamp;Task {if let data=try? await item.loadTransferable(type:Data.self),data.count<=PrototypePolicy.imageBytes,let source=CGImageSourceCreateWithData(data as CFData,nil),let decoded=CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:PrototypePolicy.thumbnailPixels,kCGImageSourceCreateThumbnailWithTransform:true] as CFDictionary) {guard stamp==generation else{return};replace(UIImage(cgImage:decoded))} else {guard stamp==generation else{return};message="画像を読み込めません。20MB以内の画像を選んでください。"}}}
        .onChange(of:species) {_,_ in key=UUID();generation=UUID();state="";candidates=[];images=[:];searchID=nil;sharedID=nil}
        .onChange(of:client.currentUserID) {_,next in history=[];generation=UUID();key=UUID();searchID=nil;sharedID=nil;if next==nil {candidates=[];images=[:];state=""} else {let stamp=generation;Task {do {let current=try await client.twinsCandidates(species:species);guard stamp==generation else{return};let ids=Set(current.map(\.id));candidates=candidates.filter{ids.contains($0.id)};images=images.filter{ids.contains($0.key)};if state=="results" && candidates.isEmpty {state="insufficient"}
                    if ["results","insufficient"].contains(state),let data=image?.jpegData(compressionQuality:0.9) {let hash=SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined();let saved=try await client.beginTwins(key:key,hash:hash,species:species);guard stamp==generation else{return};try await client.finishTwins(id:saved.id,state:state,candidates:candidates.map(\.id));guard stamp==generation else{return};searchID=saved.id;message="入力と結果を保持し、会員の検索記録に保存しました（1回分）。"}
                } catch {if stamp==generation {message="結果は保持していますが、会員記録を保存できませんでした："+error.localizedDescription}}}}}
        .onDisappear {if !cameraSession {replace(nil);history=[]}}
        .task {while !Task.isCancelled {do {try await Task.sleep(for:.seconds(15))} catch {return};if let deadline,Date()>=deadline {replace(nil);message="入力の保持時間が終了しました。"} else if state=="results" {let stamp=generation;if let visible=try? await client.twinsCandidates(species:species),stamp==generation {let valid=Set(visible.map(\.id));candidates=candidates.filter{valid.contains($0.id)};images=images.filter{valid.contains($0.key)};if candidates.isEmpty {state="insufficient"}} else if stamp==generation {candidates=[];images=[:];state="failure";key=UUID();searchID=nil;sharedID=nil;shareKey=UUID();message="公開状態を確認できないため結果を非表示にしました。再検索してください。"}}}}
        .onChange(of:phase) {_,next in if next == .background {replace(nil);history=[]} else if next == .active && pendingCamera {pendingCamera=false;showCamera=true}}
    }
    private func openCamera() {
        if [.denied,.restricted].contains(AVCaptureDevice.authorizationStatus(for:.video)) {cameraNeedsSettings=true;cameraFailure="MEFRIONのカメラ使用が許可されていません。iPhoneの設定でカメラを許可してください。";return}
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {cameraNeedsSettings=false;cameraFailure="カメラを利用できません。ほかのアプリが使用中の場合は閉じてからお試しください。写真を選ぶこともできます。";return}
        switch AVCaptureDevice.authorizationStatus(for:.video) {
        case .authorized:presentCamera()
        case .notDetermined:Task {if await AVCaptureDevice.requestAccess(for:.video) {presentCamera()} else {cameraNeedsSettings=true;cameraFailure="MEFRIONのカメラ使用が許可されていません。iPhoneの設定でカメラを許可してください。"}}
        case .denied,.restricted:cameraNeedsSettings=true;cameraFailure="MEFRIONのカメラ使用が許可されていません。iPhoneの設定でカメラを許可してください。"
        @unknown default:cameraNeedsSettings=false;cameraFailure="カメラを利用できません。写真を選んでください。"
        }
    }
    private func presentCamera() {cameraSession=true;message=nil;if phase == .active {showCamera=true} else {pendingCamera=true}}
    private func replace(_ value:UIImage?) {generation=UUID();key=UUID();image=value?.normalizedForTwins();deadline=value==nil ? nil : Date().addingTimeInterval(600);state="";images=[:];candidates=[];message=nil;loading=false;searchID=nil;queryPhoto=nil;queryPet=nil;sharedID=nil;shareKey=UUID()}
    private func feedback(_ similar:Bool,candidate:String) async {guard client.authenticated else {authenticating=true;return};guard let searchID else {message="ログイン後にこの写真で検索し、結果を保存してください。";return};await client.perform {try await client.twinsFeedback(search:searchID,candidate:candidate,similar:similar);message="評価を保存しました。"}}
    private func search() async {
        guard let cg=image?.cgImage,let deadline,deadline>Date(),let data=image?.jpegData(compressionQuality:0.9) else{return}
        let stamp=generation;loading=true;message=nil
        var requestID:String?
        do {
            let hash=SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()
            let started=try await client.beginTwins(key:key,hash:hash,species:species);requestID=started.id;searchID=client.authenticated ? started.id : nil
            let all=try await client.twinsCandidates(species:species)
            let cloud=client
            let ids=try await engine.rankStream(image:cg,candidateIDs:all.map(\.id),species:species) {id in
                let active=await MainActor.run {stamp==generation};guard active else {throw CancellationError()}
                return try await cloud.twinsImage(id).cgImage
            }
            var loaded:[String:UIImage]=[:]
            for id in ids {guard stamp==generation else{return};loaded[id]=try await client.twinsImage(id)}
            guard stamp==generation else{return};let current=try await client.twinsCandidates(species:species);let validIDs=Set(current.map(\.id));let valid=ids.filter{validIDs.contains($0)};let next=valid.isEmpty ? "insufficient" : "results"
            try await client.finishTwins(id:started.id,state:next,candidates:valid)
            guard stamp==generation else{return};candidates=valid.compactMap{id in current.first{$0.id==id}};images=loaded.filter{valid.contains($0.key)};state=next
        } catch {
            guard stamp==generation else{return};if let error=error as? PetVisualError {switch error {case .photo,.species:state="poor_photo";case .index,.processing:state="failure"}} else {state="failure"};message=error.localizedDescription
            if let requestID {try? await client.finishTwins(id:requestID,state:state,candidates:[])}
        }
        if stamp==generation {loading=false}
    }
}
private struct CloudTwinsAlbumPicker:View {
    @ObservedObject var client:CloudFamilyClient
    let choose:(CloudPhoto,CloudPet,UIImage)->Void
    @State private var petID=""
    var body:some View {Form {
        Picker("うちの子",selection:$petID) {Text("選択してください").tag("");ForEach(client.pets.filter{$0.role=="owner"}) {Text($0.name).tag($0.id)}}
        ForEach(client.photos) {photo in if let pet=client.pets.first(where:{$0.id==petID}),let image=client.images[photo.id] {Button {choose(photo,pet,image)} label: {HStack {Image(uiImage:image).resizable().scaledToFill().frame(width:70,height:70).clipped();Text(photo.title.isEmpty ? (photo.captured ?? "日付不明") : photo.title)}}}}
        if let error=client.error {Text(error).foregroundStyle(.red)}
    }.navigationTitle("家族アルバムから選ぶ").protectWhenInactive().task {await client.performRefresh {try await client.loadPets()}}
    .onChange(of:petID) {_,id in if !id.isEmpty {Task {await client.performRefresh {try await client.loadAlbum(pet:id)}}}}
    }
}

import SwiftUI
import PhotosUI
import ImageIO
import AVFoundation
import UIKit

#if DEBUG
/// Explicit developer-only probe; reads stock photos, never private state.
struct TwinsVisionSelfCheckView:View {
    @State private var status="犬猫の端末内認識を検証中"
    var body:some View {Text(status).padding().task {
        do {
            let serverMode=ProcessInfo.processInfo.arguments.contains("--server-reference-probe")
            let fixture=ReferenceTwinsEngine()
            for species in ["dog","cat"] {
                let summary:ReferenceServerSummary
                if serverMode {summary=try await ReferenceTwinsService.shared.summary(species:species)}
                else {let assets=try await fixture.assets(species:species);summary=ReferenceServerSummary(count:assets.count,assets:assets)}
                guard let sample=summary.assets.first,let image=(serverMode ? ReferenceTwinsService.shared.image(sample) : fixture.image(sample))?.cgImage else {throw PetVisualError.index}
                let feature=try PetVisualFeature.extract(image,species:species)
                print("TWINS_DEVICE_CHECK species=\(species) feature_elements=\(feature.count) FEATURE_PASS")
                if serverMode {
                    let descriptor=try await ReferenceQueryEncoder().encode(image,species:species)
                    print("TWINS_DEVICE_CHECK algorithm=\(PetResemblance.algorithm) elements=\(descriptor.resemblance.count) crop=\(descriptor.cropKind)")
                }
                let candidates:[ReferencePetAsset]
                if serverMode {candidates=try await ReferenceTwinsService.shared.search(image:image,species:species,consent:true,request:UUID())}
                else {candidates=try await fixture.search(image:image,species:species)}
                print("TWINS_DEVICE_CHECK species=\(species) server=\(serverMode) corpus=\(summary.count) candidates=\(candidates.count) self_excluded=\(!candidates.contains(where:{$0.id==sample.id}))")
                guard !candidates.isEmpty,candidates.count<=3,!candidates.contains(where:{$0.id==sample.id}),candidates.allSatisfy({$0.species==species}) else {throw PetVisualError.index}
            }
            status="犬・猫の認識と検索：成功";print("TWINS_DEVICE_CHECK COMPLETE PASS");fflush(stdout)
        } catch {status="実機検証失敗："+error.localizedDescription;print("TWINS_DEVICE_CHECK COMPLETE FAIL: \(error.localizedDescription)");fflush(stdout)}
    }}
}
#endif

struct ReferenceTwinsView:View {
    @EnvironmentObject private var store:PrototypeStore
    @Environment(\.scenePhase) private var phase
    @ObservedObject private var client=CloudFamilyClient.shared
    @State private var image:UIImage?
    @State private var picker:PhotosPickerItem?
    @State private var species="dog"
    @State private var working=false
    @State private var state=""
    @State private var message:String?
    @State private var results:[ReferencePetAsset]=[]
    @State private var available:[ReferencePetAsset]=[]
    @State private var requestID=UUID()
    @State private var task:Task<Void,Never>?
    @State private var generation=UUID()
    @State private var expires:Date?
    @State private var camera=false
    @State private var cameraSession=false
    @State private var pendingCamera=false
    @State private var pendingCaptured:UIImage?
    @State private var cameraFailure:String?
    @State private var cameraNeedsSettings=false
    @State private var crop:Crop?
    @State private var publicPets=false
    @State private var showingDetails=false
    @State private var auth=false
    @State private var saved=false
    @State private var sharing=false
    private let engine=ReferenceTwinsService.shared
    private struct Crop:Identifiable {let id=UUID();let image:UIImage}
    var body:some View {
        GeometryReader {geometry in
        let contentWidth=max(0,geometry.size.width-36)
        VStack(spacing:0) {
            HStack {
                Label("そっくり",systemImage:"pawprint.fill")
                    .font(.system(size:20,weight:.bold,design:.rounded)).foregroundStyle(Theme.actionText)
                Spacer()
                optionsMenu
            }.padding(.horizontal,18).frame(width:geometry.size.width,height:48)
            ScrollView {
                VStack(spacing:18) {
                    if state=="results",let main=results.first,let mainImage=engine.image(main) {
                        resultPanel(main:main,image:mainImage,width:contentWidth)
                    } else if let image {
                        twinsPhoto(image,width:contentWidth,height:270)
                            .overlay(alignment:.bottomTrailing) {
                                Text("うちの子 🐾").font(.caption.bold()).foregroundStyle(Theme.actionText)
                                    .padding(.horizontal,12).padding(.vertical,8)
                                    .background(.white,in:Capsule()).padding(12)
                            }
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius:28).fill(
                                LinearGradient(colors:[Theme.accent.opacity(0.17),Color(red:1,green:0.91,blue:0.83)],startPoint:.topLeading,endPoint:.bottomTrailing))
                            Image(systemName:"pawprint.fill").font(.system(size:88,weight:.thin))
                                .foregroundStyle(Theme.accent.opacity(0.58))
                            Image(systemName:"sparkle").font(.system(size:29)).foregroundStyle(.white)
                                .offset(x:-82,y:-56)
                            Image(systemName:"sparkle").font(.system(size:20)).foregroundStyle(.white)
                                .offset(x:91,y:55)
                        }.frame(width:contentWidth,height:270).accessibilityLabel("そっくり検索")
                    }
                    actionPanel.frame(width:contentWidth)
                    if working {PawLoadingView(title:"そっくりな子を探してるよ",compact:true)
                        .accessibilityIdentifier("reference-twins-progress")}
                    if let message {Text(message).font(.subheadline).foregroundStyle(Theme.actionText)
                        .frame(maxWidth:.infinity,alignment:.leading).accessibilityIdentifier("reference-twins-message")}
                    if state=="insufficient" {
                        ContentUnavailableView("見つからなかったよ",systemImage:"pawprint",description:Text("別の写真でもう一度試してね"))
                    }
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--ui-stock-twins") {
                        Button("テスト写真を使う") {
                            if let sample=available.first {replace(ReferenceTwinsEngine.shared.image(sample))}
                        }
                            .accessibilityIdentifier("reference-twins-sample")
                    }
                    #endif
                }.frame(width:contentWidth).padding(.horizontal,18).padding(.bottom,16)
            }.frame(width:geometry.size.width)
        }.frame(width:geometry.size.width)
        }.background(Theme.background).foregroundStyle(Theme.text).toolbar(.hidden,for:.navigationBar)
        .task {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--appstore-screenshots"),image==nil {
                image=UIImage(named:"appstore-dog-one")
                expires=Date().addingTimeInterval(600)
            }
            if ProcessInfo.processInfo.arguments.contains("--ui-stock-twins") {
                do {available=Array((try await ReferenceTwinsEngine.shared.assets(species:"dog")).prefix(1))}
                catch {message=error.localizedDescription}
            }
            #endif
        }
        .onChange(of:picker) {_,item in guard let item else{return};cancel();let stamp=generation;working=true
            task=Task {
                guard let data=try? await item.loadTransferable(type:Data.self),data.count<=PrototypePolicy.imageBytes,
                      let source=CGImageSourceCreateWithData(data as CFData,nil),
                      let thumbnail=CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:2048,kCGImageSourceCreateThumbnailWithTransform:true] as CFDictionary) else {if stamp==generation {working=false;message="写真を読み込めません。20MB以内の画像を選んでください。"};return}
                guard stamp==generation,!Task.isCancelled else{return};replace(UIImage(cgImage:thumbnail))
            }
        }
        .sheet(item:$crop) {item in NavigationStack {PrivateCropView(image:item.image) {replace($0)}}}
        .fullScreenCover(isPresented:$camera,onDismiss:{if let captured=pendingCaptured {replace(captured)};pendingCaptured=nil;cameraSession=false}) {
            PrivateCameraCapture(onCapture:{pendingCaptured=$0;camera=false},onCancel:{camera=false})
                .ignoresSafeArea()
                .background(.black)
                .protectWhenInactive()
        }
        .alert("カメラを開けません",isPresented:Binding(get:{cameraFailure != nil},set:{if !$0 {cameraFailure=nil}})) {
            if cameraNeedsSettings {Button("設定を開く") {if let url=URL(string:UIApplication.openSettingsURLString) {UIApplication.shared.open(url)}}}
            Button("閉じる",role:.cancel) {cameraFailure=nil}
        } message: {Text(cameraFailure ?? "")}
        .sheet(isPresented:$auth) {AuthenticationSheet(client:client)}
        .sheet(isPresented:$publicPets) {NavigationStack {CloudTwinsView()}}
        .sheet(isPresented:$showingDetails) {NavigationStack {
            ScrollView {Text("検索すると、写真の特徴データをサーバーへ送ります。写真そのものは送信・保存しません。候補はPexelsの写真で、同じ個体や血縁を判定する機能ではありません。入力写真は10分後、画面終了時、またはアプリを離れたときに破棄します。結果の履歴は自分で保存した場合のみ、候補IDを端末に24時間保持します。")
                .font(.subheadline).padding(20)}
            .navigationTitle("そっくりについて").toolbar {Button("閉じる") {showingDetails=false}}
        }}
        .sheet(isPresented:$sharing) {if let image,let main=results.first,let candidate=engine.image(main) {ReferenceShareView(query:image,candidate:candidate,credit:main.credit)}}
        .onChange(of:phase) {_,next in
            if next == .background {erase()}
            else if next == .active && pendingCamera {pendingCamera=false;camera=true}
        }
        .onChange(of:client.currentUserID) {old,next in if let old,old != next {try? store.eraseReferenceHistory(owner:old)}}
        .onReceive(Timer.publish(every:5,on:.main,in:.common).autoconnect()) {_ in if let expires,expires<=Date() {erase()}}
        .onDisappear {if !cameraSession {erase()}}
    }
    private var optionsMenu:some View {
        Menu {
            Button("公開Petから探す",systemImage:"pawprint") {publicPets=true}
            if let image {
                Button("写真を調整",systemImage:"crop") {crop=Crop(image:image)}
                    .accessibilityIdentifier("reference-twins-crop")
                Button("入力写真を削除",systemImage:"trash",role:.destructive) {erase()}
                    .accessibilityIdentifier("reference-twins-discard")
            }
            if state=="results" {
                Button(saved ? "履歴に保存済み" : "結果を履歴に保存",systemImage:"bookmark") {saveResult()}
                    .disabled(saved).accessibilityIdentifier("reference-twins-save")
                Button("共有カードを見る",systemImage:"square.and.arrow.up") {sharing=true}
                    .accessibilityIdentifier("reference-twins-share")
            }
            Button("この機能について",systemImage:"info.circle") {showingDetails=true}
        } label: {
            Image(systemName:"ellipsis").font(.system(size:21,weight:.semibold))
                .foregroundStyle(Theme.text).frame(width:44,height:44)
        }.accessibilityLabel("その他").accessibilityIdentifier("reference-twins-more")
    }
    private var actionPanel:some View {
        VStack(spacing:12) {
            HStack(spacing:12) {
                PhotosPicker(selection:$picker,matching:.images) {
                    Label("写真を選ぶ",systemImage:"photo.on.rectangle.angled")
                        .font(.system(size:15,weight:.semibold)).frame(maxWidth:.infinity,minHeight:56)
                        .foregroundStyle(Theme.actionText)
                        .background(Theme.accent.opacity(0.12),in:RoundedRectangle(cornerRadius:18))
                }.buttonStyle(.plain).accessibilityIdentifier("reference-twins-picker")
                Button(action:openCamera) {
                    Label("写真を撮る",systemImage:"camera.fill")
                        .font(.system(size:15,weight:.semibold)).frame(maxWidth:.infinity,minHeight:56)
                        .foregroundStyle(.white)
                        .background(Theme.accent.gradient,in:RoundedRectangle(cornerRadius:18))
                }.buttonStyle(.plain).accessibilityIdentifier("reference-twins-camera")
            }.disabled(working)
            Button(action:search) {
                Text("この写真で検索する").font(.system(size:16,weight:.bold))
                    .frame(maxWidth:.infinity,minHeight:54)
                    .foregroundStyle(image==nil || working ? Theme.secondaryText : .white)
                    .background(image==nil || working ? Theme.accent.opacity(0.16) : Theme.actionText,in:Capsule())
            }.buttonStyle(.plain).disabled(image==nil || working)
                .accessibilityIdentifier("reference-twins-search")
        }
    }
    private func twinsPhoto(_ image:UIImage,width:CGFloat,height:CGFloat)->some View {
        Image(uiImage:image).resizable().scaledToFill()
            .frame(width:max(0,width),height:height).clipped()
            .clipShape(RoundedRectangle(cornerRadius:18))
    }
    private func resultPanel(main:ReferencePetAsset,image mainImage:UIImage,width:CGFloat)->some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                Text("そっくりな子、見つけた！").font(.system(size:21,weight:.bold,design:.rounded))
                Spacer()
                Image(systemName:"heart.fill").foregroundStyle(Theme.accent)
            }
            twinsPhoto(mainImage,width:width-28,height:330)
                .accessibilityLabel("一番似ている写真")
                .overlay(alignment:.bottomLeading) {
                    if let image {
                        Image(uiImage:image).resizable().scaledToFill().frame(width:72,height:72)
                            .clipped().clipShape(RoundedRectangle(cornerRadius:16))
                            .overlay(RoundedRectangle(cornerRadius:16).stroke(.white,lineWidth:3))
                            .padding(12).accessibilityLabel("うちの子の写真")
                    }
                }
            credit(main)
            Button {sharing=true} label: {
                Label("そっくりカードをシェア",systemImage:"square.and.arrow.up.fill")
                    .font(.system(size:16,weight:.bold,design:.rounded))
                    .frame(maxWidth:.infinity,minHeight:52)
                    .foregroundStyle(.white)
                    .background(Theme.accent.gradient,in:Capsule())
            }.buttonStyle(.plain).accessibilityIdentifier("reference-twins-share")
            if results.count>1 {
                HStack(spacing:10) {
                    ForEach(Array(results.dropFirst())) {asset in
                        VStack(alignment:.leading,spacing:4) {
                            if let image=engine.image(asset) {
                                twinsPhoto(image,width:(width-38)/2,height:155)
                            }
                            credit(asset)
                        }.frame(width:max(0,(width-38)/2),alignment:.topLeading)
                    }
                }
            }
        }.padding(14).frame(width:width)
            .background(.white,in:RoundedRectangle(cornerRadius:24))
            .accessibilityElement(children:.contain)
            .accessibilityIdentifier("reference-twins-main")
    }
    private func saveResult() {
        guard let owner=client.currentUserID,client.authenticated else {auth=true;return}
        do {try store.saveReferenceSearch(owner:owner,species:species,candidates:results.map(\.id));saved=true}
        catch {message=error.localizedDescription}
    }
    private func openCamera() {
        if [.denied,.restricted].contains(AVCaptureDevice.authorizationStatus(for:.video)) {cameraNeedsSettings=true;cameraFailure="MEFRIONのカメラ使用が許可されていません。iPhoneの設定でカメラを許可してください。";return}
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {cameraNeedsSettings=false;cameraFailure="カメラを利用できません。ほかのアプリが使用中の場合は閉じてからお試しください。写真を選ぶこともできます。";return}
        switch AVCaptureDevice.authorizationStatus(for:.video) {
        case .authorized:presentCamera()
        case .notDetermined:
            Task {if await AVCaptureDevice.requestAccess(for:.video) {presentCamera()}
                  else {cameraNeedsSettings=true;cameraFailure="MEFRIONのカメラ使用が許可されていません。iPhoneの設定でカメラを許可してください。"}}
        case .denied,.restricted:cameraNeedsSettings=true;cameraFailure="MEFRIONのカメラ使用が許可されていません。iPhoneの設定でカメラを許可してください。"
        @unknown default:cameraNeedsSettings=false;cameraFailure="カメラを利用できません。写真を選んでください。"
        }
    }
    private func presentCamera() {
        cameraSession=true;message=nil
        if phase == .active {camera=true} else {pendingCamera=true}
    }
    private func credit(_ asset:ReferencePetAsset)->some View {
        Group {if let url=URL(string:asset.source) {Link(asset.credit,destination:url)
            .font(.caption2).foregroundStyle(Theme.secondaryText).lineLimit(1)}}
    }
    private func cancel() {task?.cancel();task=nil;generation=UUID();working=false}
    private func erase() {cancel();requestID=UUID();image=nil;results=[];state="";message=nil;expires=nil;picker=nil;crop=nil;sharing=false;saved=false}
    private func replace(_ next:UIImage?) {cancel();requestID=UUID();image=next?.normalizedForTwins();results=[];state="";message=nil;expires=Date().addingTimeInterval(600);saved=false}
    private func search() {
        guard let cg=image?.cgImage,let expires,expires>Date() else{return}
        cancel();let stamp=generation;working=true;message=nil;results=[];state="";saved=false
        task=Task {
            do {
                let detectedSpecies=try await PetSpeciesDetection.shared.detect(cg)
                guard stamp==generation,!Task.isCancelled else{return}
                species=detectedSpecies
                let found=try await engine.search(image:cg,species:detectedSpecies,consent:true,request:requestID)
                guard stamp==generation,!Task.isCancelled else{return}
                results=found;state=found.isEmpty ? "insufficient" : "results"
            }
            catch {guard stamp==generation,!Task.isCancelled else{return};if let error=error as? PetVisualError {switch error {case .photo,.species:state="poor_photo";case .index,.processing:state="failure"}} else {state="failure"};message=error.localizedDescription}
            if stamp==generation {working=false}
        }
    }
}

struct ReferenceHistoryView:View {
    @EnvironmentObject var store:PrototypeStore
    @ObservedObject private var client=CloudFamilyClient.shared
    @State private var assets:[ReferencePetAsset]=[]
    @State private var error:String?
    private var records:[ReferenceSearchRecord] {
        guard let owner=client.currentUserID,client.authenticated else{return []}
        return store.referenceTwinsHistory.filter{$0.owner==owner && Date().timeIntervalSince($0.created)>=0 && Date().timeIntervalSince($0.created)<86400}
            .sorted{$0.created>$1.created}
    }
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:18) {
                if !client.authenticated {
                    ContentUnavailableView("ログインすると見られるよ",systemImage:"pawprint",description:Text("保存したそっくりをここに集めよう ♡"))
                } else if records.isEmpty {
                    VStack(spacing:12) {
                        Image(systemName:"pawprint.fill").font(.system(size:52)).foregroundStyle(Theme.accent)
                        Text("まだ履歴はないよ ♡").font(.title3.bold()).foregroundStyle(Theme.actionText)
                        Text("そっくりの結果を保存すると、ここに並ぶよ")
                            .font(.subheadline).foregroundStyle(Theme.secondaryText)
                    }.frame(maxWidth:.infinity).padding(.vertical,60)
                        .background(.white,in:RoundedRectangle(cornerRadius:24))
                } else {
                    ForEach(records) {record in
                        VStack(alignment:.leading,spacing:12) {
                            HStack {
                                Label(record.created.formatted(date:.abbreviated,time:.shortened),systemImage:"heart.fill")
                                    .font(.subheadline.bold()).foregroundStyle(Theme.actionText)
                                Spacer()
                                Button(role:.destructive) {remove(record.id)} label: {
                                    Image(systemName:"trash").font(.subheadline).frame(width:36,height:36)
                                }.accessibilityLabel("この検索履歴を削除")
                            }
                            HStack(spacing:8) {
                                ForEach(record.candidates,id:\.self) {id in
                                    candidatePhoto(id)
                                }
                            }
                        }.padding(14).background(.white,in:RoundedRectangle(cornerRadius:22))
                    }
                    Button("履歴をすべて削除",role:.destructive) {
                        guard let owner=client.currentUserID else{return}
                        do {try store.eraseReferenceHistory(owner:owner)} catch {self.error=error.localizedDescription}
                    }.frame(maxWidth:.infinity).padding(.top,8)
                }
                Text("写真は保存せず、結果だけを24時間残します。")
                    .font(.caption).foregroundStyle(Theme.secondaryText).frame(maxWidth:.infinity)
                if let error {Text(error).font(.footnote).foregroundStyle(.red)}
            }.padding(16)
        }.background(Theme.background).navigationTitle("そっくりの履歴")
            .task {do {let ids=records.flatMap(\.candidates);assets=try await ReferenceTwinsService.shared.lookup(ids:ids)} catch {self.error=error.localizedDescription}}
    }
    @ViewBuilder private func candidatePhoto(_ id:String)->some View {
        if let asset=assets.first(where:{$0.id==id}),let image=ReferenceTwinsService.shared.image(asset) {
            Image(uiImage:image).resizable().scaledToFill()
                .frame(maxWidth:.infinity).frame(height:150).clipped()
                .clipShape(RoundedRectangle(cornerRadius:14))
        } else {
            RoundedRectangle(cornerRadius:14).fill(Theme.accent.opacity(0.08))
                .frame(maxWidth:.infinity).frame(height:150)
                .overlay(Image(systemName:"pawprint").foregroundStyle(Theme.accent))
        }
    }
    private func remove(_ id:UUID) {
        do {try store.persistMutation {store.referenceTwinsHistory.removeAll{$0.id==id}}}
        catch {self.error=error.localizedDescription}
    }
}

private struct ReferenceShareView:View {
    @Environment(\.dismiss) private var dismiss
    let query:UIImage
    let candidate:UIImage
    let credit:String
    @State private var rendered:UIImage?
    @State private var renderedPost:UIImage?
    @State private var shareError:String?
    @State private var selectedFormat=0
    var body:some View {NavigationStack {ScrollView {VStack(spacing:18) {
        HStack(spacing:6) {
            formatButton("ストーリー",index:0)
            formatButton("X ポスト",index:1)
        }.padding(4).background(Theme.accent.opacity(0.1),in:Capsule())
        Group {
            if selectedFormat==0 {storyCard(width:300)}
            else {postCard(width:300)}
        }.clipShape(RoundedRectangle(cornerRadius:25))
            .shadow(color:Theme.accent.opacity(0.13),radius:16,y:7)
        Text(selectedFormat==0 ? "ストーリーにぴったりのカード ♡" : "Xでも見やすいカード ♡")
            .font(.system(size:18,weight:.bold,design:.rounded)).foregroundStyle(Theme.actionText)
        if selectedFormat==1,let renderedPost {
            Button {shareToX(image:renderedPost)} label: {
                Label("Xでポストを作る",systemImage:"arrow.up.right")
                    .font(.headline).frame(maxWidth:.infinity,minHeight:54)
                    .foregroundStyle(.white).background(Theme.accent.gradient,in:Capsule())
            }.buttonStyle(.plain).accessibilityIdentifier("reference-twins-x-share")
            Text("カードをコピーしてXを開くよ。画像を貼り付けて投稿してね。")
                .font(.caption).foregroundStyle(Theme.secondaryText)
        }
        if selectedFormat==0,let rendered {
            Button {shareToInstagramStories(image:rendered)} label: {
                Label("Instagramストーリーを作る",systemImage:"sparkles.tv.fill")
                    .font(.headline).frame(maxWidth:.infinity,minHeight:54)
                    .foregroundStyle(.white).background(Theme.accent.gradient,in:Capsule())
            }.buttonStyle(.plain).accessibilityIdentifier("reference-twins-instagram-story")
        } else if selectedFormat==0 || renderedPost==nil {
            PawLoadingView(title:"カードを作っているよ",compact:true)
        }
        Text("どちらのカードも、共有先で確定するまで公開されません。")
            .font(.caption).foregroundStyle(Theme.secondaryText)
        if let shareError {Text(shareError).font(.caption).foregroundStyle(.red)}
    }.padding(18)}.background(Theme.background).navigationTitle("そっくりカード")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {ToolbarItem(placement:.topBarTrailing) {Button("閉じる") {dismiss()}}}
        .task {rendered=renderStory();renderedPost=renderPost()}}}
    private func formatButton(_ title:String,index:Int)->some View {
        Button(title) {selectedFormat=index}
            .font(.system(size:14,weight:.bold,design:.rounded))
            .foregroundStyle(selectedFormat==index ? Theme.actionText : Theme.secondaryText)
            .frame(maxWidth:.infinity,minHeight:36)
            .background(selectedFormat==index ? Color.white : Color.clear,in:Capsule())
            .buttonStyle(.plain)
    }
    private func storyCard(width:CGFloat)->some View {
        let scale=width/360
        return VStack(spacing:0) {
            Text("MEFRION  🐾").font(.system(size:23*scale,weight:.heavy,design:.rounded))
                .foregroundStyle(Theme.actionText).padding(.top,66*scale)
            Text("そっくりな子、見つけた ♡")
                .font(.system(size:23*scale,weight:.bold,design:.rounded))
                .foregroundStyle(Theme.text).padding(.top,27*scale)
            Text("うちの子に似てる子、どこかにいるかも")
                .font(.system(size:11*scale,weight:.medium,design:.rounded))
                .foregroundStyle(Theme.secondaryText).padding(.top,7*scale)
            HStack(spacing:6*scale) {
                sharePhoto(query,label:"うちの子",scale:scale)
                    .rotationEffect(.degrees(-4))
                Image(systemName:"heart.fill")
                    .font(.system(size:19*scale)).foregroundStyle(Theme.accent)
                sharePhoto(candidate,label:"そっくりな子",scale:scale)
                    .rotationEffect(.degrees(4))
            }.padding(.top,54*scale)
            Text("似てる？ 会ってみたいね ✨")
                .font(.system(size:17*scale,weight:.bold,design:.rounded))
                .foregroundStyle(Theme.actionText).padding(.top,35*scale)
            Spacer(minLength:0)
            Text("MEFRIONでそっくり探し 🐾")
                .font(.system(size:14*scale,weight:.bold,design:.rounded))
                .foregroundStyle(Theme.actionText)
                .padding(.horizontal,18*scale).padding(.vertical,9*scale)
                .background(.white.opacity(0.85),in:Capsule())
            Text(credit).font(.system(size:8*scale)).foregroundStyle(Theme.secondaryText)
                .lineLimit(2).multilineTextAlignment(.center).padding(.top,14*scale)
            Text("写真の見た目を比べた結果です。血縁の判定ではありません。")
                .font(.system(size:8*scale)).foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center).padding(.top,4*scale).padding(.bottom,28*scale)
        }.padding(.horizontal,18*scale).frame(width:width,height:width*16/9)
            .background(LinearGradient(colors:[Color(red:1,green:0.975,blue:0.96),Color(red:1,green:0.88,blue:0.89)],startPoint:.topLeading,endPoint:.bottomTrailing))
            .overlay(alignment:.topLeading) {Image(systemName:"sparkle").font(.system(size:29*scale)).foregroundStyle(Theme.accent.opacity(0.55)).padding(.leading,27*scale).padding(.top,165*scale)}
            .overlay(alignment:.bottomTrailing) {Image(systemName:"pawprint.fill").font(.system(size:38*scale)).foregroundStyle(Theme.accent.opacity(0.18)).padding(.trailing,21*scale).padding(.bottom,93*scale)}
    }
    private func sharePhoto(_ photo:UIImage,label:String,scale:CGFloat)->some View {
        VStack(spacing:8*scale) {
            Image(uiImage:photo).resizable().scaledToFill()
                .frame(width:133*scale,height:235*scale).clipped()
                .clipShape(RoundedRectangle(cornerRadius:15*scale))
            Text(label).font(.system(size:13*scale,weight:.bold,design:.rounded)).foregroundStyle(Theme.text)
        }.padding(7*scale).background(.white,in:RoundedRectangle(cornerRadius:19*scale))
            .shadow(color:Theme.accent.opacity(0.14),radius:7*scale,y:4*scale)
    }
    private func postCard(width:CGFloat)->some View {
        let scale=width/360
        return VStack(spacing:0) {
            Text("MEFRION  🐾").font(.system(size:20*scale,weight:.heavy,design:.rounded))
                .foregroundStyle(Theme.actionText).padding(.top,30*scale)
            Text("そっくりな子、見つけた ♡")
                .font(.system(size:21*scale,weight:.bold,design:.rounded))
                .foregroundStyle(Theme.text).padding(.top,15*scale)
            HStack(spacing:8*scale) {
                postPhoto(query,label:"うちの子",scale:scale)
                Image(systemName:"heart.fill").font(.system(size:18*scale)).foregroundStyle(Theme.accent)
                postPhoto(candidate,label:"そっくりな子",scale:scale)
            }.padding(.top,23*scale)
            Text("似てる？ 会ってみたいね ✨")
                .font(.system(size:16*scale,weight:.bold,design:.rounded))
                .foregroundStyle(Theme.actionText).padding(.top,19*scale)
            Spacer(minLength:0)
            Text("あなたのそっくりも、MEFRIONで 🐾")
                .font(.system(size:12*scale,weight:.semibold,design:.rounded))
                .foregroundStyle(Theme.actionText)
            Text(credit).font(.system(size:8*scale)).foregroundStyle(Theme.secondaryText)
                .lineLimit(2).multilineTextAlignment(.center).padding(.top,8*scale)
            Text("写真の見た目の比較です。血縁の判定ではありません。")
                .font(.system(size:8*scale)).foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center).padding(.top,3*scale).padding(.bottom,16*scale)
        }.padding(.horizontal,15*scale).frame(width:width,height:width*4/3)
            .background(LinearGradient(colors:[Color(red:1,green:0.97,blue:0.96),Color(red:1,green:0.88,blue:0.89)],startPoint:.topLeading,endPoint:.bottomTrailing))
            .overlay(alignment:.topTrailing) {Image(systemName:"sparkle").font(.system(size:23*scale)).foregroundStyle(Theme.accent.opacity(0.5)).padding(22*scale)}
    }
    private func postPhoto(_ photo:UIImage,label:String,scale:CGFloat)->some View {
        VStack(spacing:6*scale) {
            Image(uiImage:photo).resizable().scaledToFill()
                .frame(width:137*scale,height:205*scale).clipped()
                .clipShape(RoundedRectangle(cornerRadius:14*scale))
            Text(label).font(.system(size:12*scale,weight:.bold,design:.rounded)).foregroundStyle(Theme.text)
        }.padding(6*scale).background(.white,in:RoundedRectangle(cornerRadius:18*scale))
    }
    @MainActor private func renderStory()->UIImage? {
        let renderer=ImageRenderer(content:storyCard(width:360))
        renderer.scale=3
        return renderer.uiImage
    }
    @MainActor private func renderPost()->UIImage? {
        let renderer=ImageRenderer(content:postCard(width:360))
        renderer.scale=3
        return renderer.uiImage
    }
    private var instagramURL:URL? {
        let appID=Bundle.main.object(forInfoDictionaryKey:"MEFRIONMetaAppID") as? String ?? ""
        let source=appID.isEmpty ? (Bundle.main.bundleIdentifier ?? "com.mefrion.app") : appID
        return URL(string:"instagram-stories://share?source_application=\(source)")
    }
    private func shareToInstagramStories(image:UIImage) {
        guard let url=instagramURL,UIApplication.shared.canOpenURL(url) else {shareError="Instagramアプリを入れてから試してね。";return}
        guard let data=image.pngData() else {shareError="カードを作れませんでした。もう一度お試しください。";return}
        UIPasteboard.general.setItems([["com.instagram.sharedSticker.backgroundImage":data]],options:[.expirationDate:Date().addingTimeInterval(300)])
        UIApplication.shared.open(url) {opened in
            if !opened {shareError="Instagramを開けませんでした。アプリの設定を確認してね。"}
        }
    }
    private func shareToX(image:UIImage) {
        guard let data=image.pngData() else {shareError="カードを作れませんでした。もう一度お試しください。";return}
        UIPasteboard.general.setItems([["public.png":data]],options:[.expirationDate:Date().addingTimeInterval(300)])
        let message="うちの子のそっくり、見つけたよ 🐾 #MEFRION"
        let encoded=message.addingPercentEncoding(withAllowedCharacters:.urlQueryAllowed) ?? ""
        guard let appURL=URL(string:"twitter://post?message=\(encoded)"),
              let webURL=URL(string:"https://x.com/intent/tweet?text=\(encoded)") else {return}
        UIApplication.shared.open(UIApplication.shared.canOpenURL(appURL) ? appURL : webURL) {opened in
            if !opened {shareError="Xを開けませんでした。アプリの設定を確認してね。"}
        }
    }
}

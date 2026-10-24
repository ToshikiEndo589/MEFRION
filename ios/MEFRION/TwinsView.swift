import SwiftUI
import PhotosUI
import ImageIO
import AVFoundation

struct TwinsView: View {
    @EnvironmentObject var store: PrototypeStore
    @ObservedObject private var cloud=CloudFamilyClient.shared
    @State private var authenticating=false
    private struct CropInput:Identifiable {let id=UUID();let image:UIImage}
    @State private var cropInput:CropInput?
    @State private var showCamera=false
    @State private var pendingCaptured:UIImage?
    @State private var cameraError:String?
    @State private var inputGeneration=UUID()
    @State private var ownedDemoID:Int?
    @State private var species = Species.dog
    @State private var scenario = "local"
    @State private var matches: [TwinsMatch] = []
    @State private var resultState = ""
    private let engine = DemoTwinsEngine()
    @State private var searched = false
    @State private var feedback: String?
    @State private var image: UIImage?
    @State private var picker: PhotosPickerItem?
    @State private var consent = false
    @State private var loading = false
    @State private var loadError: String?
    @State private var duration = 0.0
    let cases = ["local", "results", "insufficient", "poor_photo", "failure"]
    let labels = ["端末内の画像比較", "固定の結果", "候補不足", "写真不良", "処理失敗"]
    init(reviewState:String?=nil) {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-test-isolated"),ProcessInfo.processInfo.arguments.contains("--ui-reference-gallery"),let state=reviewState {
            _image=State(initialValue:UIImage(named:"pet-0"));_searched=State(initialValue:true);_resultState=State(initialValue:state)
            _matches=State(initialValue:state=="results" ? [2,4,6].map{TwinsMatch(id:$0,distance:0)} : [])
        }
        #endif
    }
    @State private var showingHistory=false
    var body: some View {
        VStack(spacing:0) {
HStack {Label("そっくり",systemImage:"pawprint.fill").font(.headline).accessibilityIdentifier("twins-compact-heading").foregroundStyle(Theme.actionText);Spacer();Button {showingHistory=true} label: {Text("検索履歴").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text).frame(minWidth:44,minHeight:44).contentShape(Rectangle())}.accessibilityIdentifier("twins-history")}.padding(.horizontal,16)
        ScrollView {
            VStack(spacing: Theme.spacing) {
                Image(uiImage:image ?? UIImage(named:"pet-0")!).resizable().scaledToFill().frame(height:250).clipped().clipShape(RoundedRectangle(cornerRadius:16))
                    .overlay(alignment:.bottomLeading) {
                        Text("うちの子に、似ている子を見つけよう。")
                            .font(.headline).foregroundStyle(.white).padding(16).frame(maxWidth:.infinity,alignment:.leading)
                            .background(LinearGradient(colors:[.clear,.black.opacity(0.5)],startPoint:.top,endPoint:.bottom))
                    }.clipShape(RoundedRectangle(cornerRadius:16)).accessibilityLabel("そっくり検索のイメージ・開発用イラスト")
                Text("端末内で、所有テストイラストとの色・輪郭を比較します。犬猫の種別は本人が選択します。実写真の犬猫認識と似ている品質は未検証です。血縁や同一個体の判定ではありません。")
                Text("入力写真は端末内メモリのみで使い、破棄ボタンやアプリ終了で破棄します。サーバー・外部AIへ送信せず、候補DBにも追加しません。")
                    .font(.footnote).foregroundStyle(Theme.text)
                PhotosPicker(selection: $picker, matching: .images) { Label("アルバムから選ぶ", systemImage: "photo") }.buttonStyle(CoralButtonStyle())
                Button("所有テストイラストで試す") {let id=species == .dog ? 0 : 1;replaceInput(UIImage(named:"pet-\(id)"),demoID:id)}.accessibilityIdentifier("twins-demo-image")
                Button("写真を撮る",systemImage:"camera") {
                    guard UIImagePickerController.isSourceTypeAvailable(.camera) else {cameraError="この端末ではカメラを利用できません。アルバムから写真を選んでください。";return}
                    Task {let allowed=await AVCaptureDevice.requestAccess(for:.video);if allowed {showCamera=true} else {cameraError="カメラへのアクセスが許可されていません。設定アプリで変更するか、アルバムから写真を選んでください。"}}
                }.buttonStyle(CoralButtonStyle()).disabled(loading).accessibilityIdentifier("twins-camera")
                if let cameraError {Text(cameraError).foregroundStyle(.red).accessibilityIdentifier("twins-camera-error");Button("カメラの案内を閉じる") {self.cameraError=nil}}
                if let image {Button("写真を切り抜く",systemImage:"crop") {cropInput=CropInput(image:image)}.disabled(loading).accessibilityIdentifier("twins-crop")}
                if loading { ProgressView("選択画像を読み込み中") }
                if let image { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 220).accessibilityLabel("そっくりの入力写真・端末内のみ") }
                if let loadError { Text(loadError).foregroundStyle(.red) }
                Picker("対象を確認・修正", selection: $species) { ForEach(Species.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented).disabled(loading)
                Picker("デモの検索状態", selection: $scenario) { ForEach(Array(zip(cases,labels)), id: \.0) { Text($0.1).tag($0.0) } }.disabled(loading)
                Toggle("端末内でのテストに同意する", isOn: $consent).accessibilityIdentifier("twins-consent")
                Button("デモ検索を開始・再試行") {
                    let start = Date()
                    searched = false; feedback = nil; store.searches += 1; loading = true
                    let requestedScenario=scenario;let requestedImage=image?.cgImage;let requestedSpecies=species;let excluded=ownedDemoID;let stamp=inputGeneration
                    Task {
                        if requestedScenario == "local", let cgImage=requestedImage {
                            do {
                                let found=try await engine.search(image:cgImage,species:requestedSpecies,excluding:excluded)
                                guard stamp==inputGeneration else {return};matches=found
                                resultState = matches.isEmpty ? "insufficient" : "results"
                            } catch {
                                guard stamp==inputGeneration else {return}
                                matches = []
                                if error is DemoTwinsError { resultState = "poor_photo" }
                                else { resultState = "failure"; store.failures += 1 }
                                loadError = error.localizedDescription
                            }
                        } else {
                            matches = (requestedSpecies == .dog ? [2,4,6] : [3,5,7]).map { TwinsMatch(id: $0, distance: 0) }
                            resultState = requestedScenario
                            if requestedScenario == "failure" { store.failures += 1 }
                        }
                        guard stamp==inputGeneration else {return}
                        duration = Date().timeIntervalSince(start) * 1000
                        do {try store.recordTwinsSearch(species:requestedSpecies,state:resultState,mode:requestedScenario=="local" ? "local" : "fixture",candidates:resultState=="results" ? matches.map(\.id) : [])} catch {loadError=error.localizedDescription}
                        searched = true; loading = false
                    }
                }.buttonStyle(CoralButtonStyle()).disabled(!consent || image == nil || loading).frame(minHeight: 44).accessibilityIdentifier("twins-search")
                if searched {
                    if resultState == "results" {
                        if let main=matches.first {
                            VStack(spacing:16) {
                                HStack(spacing:10) {
                                    VStack {if let image {Image(uiImage:image).resizable().scaledToFill().frame(width:115,height:115).clipShape(Circle())};Text("うちの子").font(.caption)}
                                    Image(systemName:"heart").font(.title).foregroundStyle(Theme.actionText)
                                    VStack {Image("pet-\(main.id)").resizable().scaledToFill().frame(width:115,height:115).clipShape(Circle());Text(DemoPost(id:main.id).name).font(.caption.bold())}
                                }
                                Text("似ている候補が見つかりました").font(.headline)
                                Text("所有デモ候補です。血縁や同じ個体の判定ではありません。").font(.caption).foregroundStyle(.secondary)
                            }.padding(16).frame(maxWidth:.infinity).background(Theme.accent.opacity(0.07)).clipShape(RoundedRectangle(cornerRadius:20)).accessibilityIdentifier("twins-main-result")
                            if matches.count>1 {
                                Text("他に似ている候補").font(.headline)
                                HStack(spacing:12) {ForEach(Array(matches.dropFirst().prefix(2)),id:\.id) {match in VStack {Image("pet-\(match.id)").resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius:12));Text(DemoPost(id:match.id).name).font(.caption)}.frame(maxWidth:.infinity)}}
                            }
                        }
                        HStack {
                            Button("似てる") { store.feedback.append("similar"); feedback = "評価を端末内に記録しました。" }
                            Button("ちょっと違う") { store.feedback.append("different"); feedback = "評価を端末内に記録しました。" }
                        }.disabled(feedback != nil)
                        if let feedback { Text(feedback) }
                    } else if resultState == "insufficient" {ContentUnavailableView("そっくりな子が見つかりませんでした",systemImage:"pawprint",description:Text("別の写真でも試してみてください。候補が不足している場合は件数を水増ししません。"))}
                    else if resultState == "poor_photo" { Text("対象の顔を明るく大きく写し、複数匹なら対象を選んでください。入力写真を保持しています。") }
                    else { Text("検索処理に失敗しました。入力写真を保持して再試行できます。候補不足とは別の状態です。") }
                    Text("試作処理 \(duration, specifier: "%.2f")ms / 外部費用0円（犬猫の類似品質は未検証）").font(.caption).accessibilityIdentifier("twins-processing-duration")
                    if !cloud.authenticated {Button("ログインしてこの結果へ戻る") {authenticating=true}.accessibilityIdentifier("twins-auth-resume")}
                    Button("入力と結果を破棄") {replaceInput(nil);picker=nil;consent=false}.accessibilityIdentifier("twins-discard")
                }
            }.padding(.horizontal,16).padding(.bottom,8)
        }
        }.background(Theme.background).foregroundStyle(Theme.text).navigationTitle("そっくり").toolbar(.hidden,for:.navigationBar)
        .navigationDestination(isPresented:$showingHistory) {TwinsHistoryView().toolbar(.visible,for:.navigationBar)}
        .sheet(isPresented:$authenticating) {AuthenticationSheet(client:cloud)}
        .sheet(item:$cropInput) {input in NavigationStack {PrivateCropView(image:input.image) {cropped in replaceInput(cropped,demoID:ownedDemoID)}}}
        .fullScreenCover(isPresented:$showCamera,onDismiss:{if let captured=pendingCaptured {cropInput=CropInput(image:captured)};pendingCaptured=nil}) {
            PrivateCameraCapture(onCapture:{captured in replaceInput(captured);pendingCaptured=captured;showCamera=false},onCancel:{showCamera=false})
                .ignoresSafeArea()
                .background(.black)
                .protectWhenInactive()
        }
        .onChange(of: species) {_,_ in inputGeneration=UUID();loading=false;searched=false;matches=[]}
        .onChange(of: scenario) {_,_ in inputGeneration=UUID();loading=false;searched=false;matches=[]}
        .onChange(of: picker) { _, item in
            guard let item else {return};inputGeneration=UUID();let stamp=inputGeneration;loading=true;searched=false;matches=[];ownedDemoID=nil
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), data.count <= PrototypePolicy.imageBytes,
                   let source = CGImageSourceCreateWithData(data as CFData, nil),
                   let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0,
                      [kCGImageSourceCreateThumbnailFromImageAlways: true,
                       kCGImageSourceThumbnailMaxPixelSize: PrototypePolicy.thumbnailPixels,
                       kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) {
                    guard stamp==inputGeneration else {return}
                    image = UIImage(cgImage: thumb); loadError = nil
                } else {guard stamp==inputGeneration else {return};image = nil; loadError = "画像を読み込めません。20MB以内の画像を選んでください。" }
                loading = false
            }
        }
    }
    private func replaceInput(_ newImage:UIImage?,demoID:Int?=nil) {
        inputGeneration=UUID();image=newImage;ownedDemoID=demoID;searched=false;matches=[];feedback=nil;loadError=nil;loading=false
    }
}

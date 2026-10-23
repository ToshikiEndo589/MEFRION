import SwiftUI
import UIKit

// Images stay in memory; this input/crop layer has no network or photo-library save.
enum PrivateImageCrop {
    static func normalized(_ image:UIImage)->UIImage {
        let scale=min(1,1600/max(image.size.width,image.size.height))
        let size=CGSize(width:max(1,image.size.width*scale),height:max(1,image.size.height*scale))
        let format=UIGraphicsImageRendererFormat();format.scale=1;format.opaque=true
        return UIGraphicsImageRenderer(size:size,format:format).image {_ in image.draw(in:CGRect(origin:.zero,size:size))}
    }
    static func crop(_ image:UIImage,zoom:Double,x:Double,y:Double)throws->UIImage {
        guard (1...3).contains(zoom),(0...1).contains(x),(0...1).contains(y),let cg=normalized(image).cgImage else {throw PrototypeError(message:"切り抜き位置を確認してください。")}
        let width=Double(cg.width),height=Double(cg.height),side=floor(min(width,height)/zoom)
        let rect=CGRect(x:floor((width-side)*x),y:floor((height-side)*y),width:side,height:side)
        guard side>=Double(DemoTwinsPolicy.minimumPixels),let result=cg.cropping(to:rect) else {throw PrototypeError(message:"対象が小さすぎます。拡大を減らして試してください。")}
        return UIImage(cgImage:result)
    }
}

struct PrivateCropView:View {
    let image:UIImage
    let onApply:(UIImage)->Void
    @Environment(\.dismiss) private var dismiss
    @State private var zoom=1.0
    @State private var x=0.5
    @State private var y=0.5
    @State private var error:String?
    private var preview:UIImage? {try? PrivateImageCrop.crop(image,zoom:zoom,x:x,y:y)}
    var body:some View {
        ScrollView {VStack(spacing:18) {
            Text("対象の顔が中央に入るように調整してください。複数匹なら1匹を選びます。").font(.footnote)
            if let preview {Image(uiImage:preview).resizable().scaledToFit().frame(maxHeight:350).overlay {
                GeometryReader {geometry in Path {path in
                    for fraction in [1.0/3,2.0/3] {
                        path.move(to:CGPoint(x:geometry.size.width*fraction,y:0));path.addLine(to:CGPoint(x:geometry.size.width*fraction,y:geometry.size.height))
                        path.move(to:CGPoint(x:0,y:geometry.size.height*fraction));path.addLine(to:CGPoint(x:geometry.size.width,y:geometry.size.height*fraction))
                    }
                }.stroke(.white.opacity(0.65),lineWidth:1)}
            }.overlay(Rectangle().stroke(.white,lineWidth:3)).background(.black.opacity(0.1)).accessibilityIdentifier("twins-crop-preview")}
            VStack(alignment:.leading) {
                Text("拡大");Slider(value:$zoom,in:1...3).accessibilityLabel("切り抜きの拡大")
                Text("左右の位置");Slider(value:$x,in:0...1).accessibilityLabel("切り抜きの左右")
                Text("上下の位置");Slider(value:$y,in:0...1).accessibilityLabel("切り抜きの上下")
            }
            if let error {Text(error).foregroundStyle(.red)}
            Button("この切り抜きを使う") {do {let cropped=try PrivateImageCrop.crop(image,zoom:zoom,x:x,y:y);onApply(cropped);dismiss()} catch {self.error=error.localizedDescription}}.buttonStyle(CoralButtonStyle()).accessibilityIdentifier("twins-apply-crop")
            Text("元のアルバム写真は変更しません。検索用の切り抜きは端末内だけで使用します。").font(.caption)
        }.padding(20)}.background(Theme.background).protectWhenInactive().navigationTitle("写真の確認")
        .toolbar {ToolbarItem(placement:.cancellationAction) {Button("キャンセル") {dismiss()}}}
    }
}

struct PrivateCameraCapture:UIViewControllerRepresentable {
    let onCapture:(UIImage)->Void
    let onCancel:()->Void
    func makeCoordinator()->Coordinator {Coordinator(parent:self)}
    func makeUIViewController(context:Context)->UIImagePickerController {
        let camera=UIImagePickerController()
        camera.sourceType = .camera
        camera.mediaTypes=["public.image"]
        camera.delegate=context.coordinator
        camera.modalPresentationStyle = .fullScreen
        // The system camera leaves space around its preview. Match that space to
        // the camera controls rather than the app's light sheet background.
        camera.view.backgroundColor = .black
        camera.view.isOpaque = true
        return camera
    }
    func updateUIViewController(_ uiViewController:UIImagePickerController,context:Context) {}
    final class Coordinator:NSObject,UIImagePickerControllerDelegate,UINavigationControllerDelegate {
        let parent:PrivateCameraCapture
        init(parent:PrivateCameraCapture) {self.parent=parent}
        func imagePickerControllerDidCancel(_ picker:UIImagePickerController) {parent.onCancel()}
        func imagePickerController(_ picker:UIImagePickerController,didFinishPickingMediaWithInfo info:[UIImagePickerController.InfoKey:Any]) {
            guard let image=info[.originalImage] as? UIImage else {parent.onCancel();return}
            parent.onCapture(PrivateImageCrop.normalized(image))
        }
    }
}


struct TwinsHistoryView:View {
    @EnvironmentObject var store:PrototypeStore
    @State private var clearing=false
    @State private var error:String?
    var body:some View {
        List {
            Text("入力写真は保存しません。所有デモ候補と検索状態の履歴だけを、この端末の保護領域に最大20件保存します。24時間を過ぎた履歴は表示せず、次回読み込み・保存時に除外します。").font(.footnote)
            ForEach(PrototypeStore.recentTwinsHistory(store.twinsHistory)) {record in
                Section {
                    HStack {Text(record.species.title);Spacer();Text(record.created,format:.dateTime.month().day().hour().minute()).font(.caption)}
                    Text(record.mode=="local" ? "端末内の画像比較" : "固定状態のデモ")
                    if record.state=="results" {
                        ScrollView(.horizontal) {HStack {ForEach(record.candidateIDs,id:\.self) {id in Image("pet-\(id)").resizable().scaledToFill().frame(width:72,height:72).clipped().clipShape(RoundedRectangle(cornerRadius:10))}}}
                        Text("所有デモ候補 \(record.candidateIDs.count)件。類似品質は未検証です。").font(.caption)
                    } else {Text(record.state=="insufficient" ? "候補が見つかりませんでした" : record.state=="poor_photo" ? "写真の確認が必要です" : "処理に失敗しました")}
                }.accessibilityIdentifier("twins-history-record")
            }
            if PrototypeStore.recentTwinsHistory(store.twinsHistory).isEmpty {Text("検索履歴はありません").accessibilityIdentifier("twins-history-empty")}
            if let error {Text(error).foregroundStyle(.red)}
            if !store.twinsHistory.isEmpty {Button("履歴をすべて削除",role:.destructive) {clearing=true}.accessibilityIdentifier("twins-clear-history")}
        }.scrollContentBackground(.hidden).background(Theme.background).navigationTitle("検索履歴").navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("この端末のTwins検索履歴を削除しますか？",isPresented:$clearing,titleVisibility:.visible) {Button("検索履歴を削除する",role:.destructive) {do {try store.clearTwinsHistory()} catch {self.error=error.localizedDescription}}}
    }
}

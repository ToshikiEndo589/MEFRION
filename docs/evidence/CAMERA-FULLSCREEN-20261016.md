# そっくりカメラの全画面表示 — 2026-10-16

## 報告と変更

ユーザー提供のiPhone画面では、システムの撮影UIの外側に白い上端・下端が見えた。`PrivateCameraCapture` は `UIImagePickerController` を SwiftUI の全画面カバーに載せていたが、カメラとカバーに黒背景・安全領域をまたぐ表示指定がなかった。カメラ本体を黒の全画面表示に設定し、参考写真検索・公開Pet検索・旧デモ画面の呼び出し側を画面端まで広げた。旧デモ画面はシートから全画面カバーへ変更した。撮影画像の正規化、検索への引き渡し、非アクティブ時のプライバシー保護は維持した。

## 実行した確認

- `xcodebuild ... -destination 'platform=iOS Simulator,id=4F89959B-BD92-42D9-BBFB-DFD0F86318B8' ... build CODE_SIGNING_ALLOWED=NO`: `BUILD SUCCEEDED`。
- `xcodebuild ... -destination 'generic/platform=iOS' ... build -quiet`: 終了コード0。
- `codesign --verify --deep --strict /tmp/mefrion-camera-device/Build/Products/Debug-iphoneos/MEFRION.app`: 終了コード0。
- `testReferenceTwinsCameraCapture` の Simulator UI試験を開始したが、Xcodeがテストセッション開始時に停止。約4分後に中断。結果は未確定であり、合格として扱わない。
- `xcrun devicectl list devices`: 物理iPhone `00008140-001A74A22E90401C` は `unavailable`。実機インストール・カメラ画面の実写確認は未実施。

## 残る確認

実機が再接続されたらビルド済みのアプリを上書きインストールし、「そっくり → 写真を撮る」で上下が黒くつながって見えるか、撮影・使用・検索への復帰が成立するかを確認する。Simulatorではカメラ映像を表示できないため、今回のビルド結果だけで見た目の修正完了とは断定しない。

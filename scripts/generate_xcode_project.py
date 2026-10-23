"""Preserve the maintained Xcode project instead of regenerating an unsafe legacy template."""

from pathlib import Path

project = Path(__file__).resolve().parents[1] / "ios/MEFRION.xcodeproj/project.pbxproj"
if not project.is_file():
    raise SystemExit("Xcodeプロジェクトがありません。Gitからios/MEFRION.xcodeprojを復元してください。")
print("既存のXcodeプロジェクトを保持しました。再生成は行いません。")

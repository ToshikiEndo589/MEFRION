"""Copy only the appropriate public Supabase configuration into an iOS build.

The publishable key is designed to be in a client app. Never put a service-role
key or any other server secret in either configuration file.
"""

import argparse
import json
import re
import shutil
from pathlib import Path
from urllib.parse import urlsplit


DEVELOPMENT_HOST = "pmrvzpuznwzuejbuhaqm.supabase.co"


def validate_production(source: Path) -> None:
    try:
        configuration = json.loads(source.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        raise ValueError("本番の公開設定JSONを読み取れません。") from exc
    if not isinstance(configuration, dict) or set(configuration) != {"url", "anon_key"}:
        raise ValueError("本番の公開設定は url と anon_key の2項目だけにしてください。")
    address, key = configuration["url"], configuration["anon_key"]
    if not isinstance(address, str) or not isinstance(key, str):
        raise ValueError("本番の公開設定値が不正です。")
    try:
        parsed = urlsplit(address)
        hostname, port = parsed.hostname, parsed.port
    except ValueError as exc:
        raise ValueError("本番URLの形式が不正です。") from exc
    if (
        parsed.scheme != "https"
        or not re.fullmatch(r"[a-z0-9-]+\.supabase\.co", hostname or "")
        or hostname == DEVELOPMENT_HOST
        or port is not None
        or parsed.username is not None
        or parsed.password is not None
        or parsed.path not in ("", "/")
        or parsed.query
        or parsed.fragment
    ):
        raise ValueError("開発用とは別のSupabase本番HTTPS URLを指定してください。")
    if not key.startswith("sb_publishable_") or len(key) < 32 or any(ch.isspace() for ch in key):
        raise ValueError("anon_key には本番の publishable key を指定してください。")


def copy_configuration(source_dir: Path, destination_dir: Path, configuration: str, action: str, bundle_id: str) -> None:
    development = destination_dir / "DevelopmentPublicConfiguration.json"
    production = destination_dir / "ProductionPublicConfiguration.json"
    destination_dir.mkdir(parents=True, exist_ok=True)
    if configuration == "Debug":
        production.unlink(missing_ok=True)
        source = source_dir / development.name
        if not source.is_file():
            raise ValueError("開発用の公開設定が見つかりません。")
        shutil.copyfile(source, development)
        return

    development.unlink(missing_ok=True)
    production.unlink(missing_ok=True)
    source = source_dir / production.name
    if not source.is_file():
        raise ValueError("Releaseには本番の公開設定が必要です。docs/operations/PRODUCTION-IOS-CONFIG.mdを確認してください。")
    validate_production(source)
    if action == "install" and bundle_id.startswith("dev.local."):
        raise ValueError("ArchiveにはApp Store用のBundle IDが必要です。開発用Bundle IDでは申請できません。")
    shutil.copyfile(source, production)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-dir", type=Path, required=True)
    parser.add_argument("--destination-dir", type=Path, required=True)
    parser.add_argument("--configuration", required=True)
    parser.add_argument("--action", required=True)
    parser.add_argument("--bundle-id", required=True)
    args = parser.parse_args()
    try:
        copy_configuration(args.source_dir, args.destination_dir, args.configuration, args.action, args.bundle_id)
    except ValueError as exc:
        parser.exit(1, f"MEFRION設定エラー: {exc}\n")

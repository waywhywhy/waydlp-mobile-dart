"""Validate Obtainium distribution metadata using only the Python standard library."""
import argparse
import json
from pathlib import Path
import re
from urllib.parse import quote

ROOT = Path(__file__).resolve().parents[1]


def load_config():
    config = json.loads((ROOT / "obtainium.json").read_text(encoding="utf-8"))
    if len(config["apps"]) != 1 or config["settings"] is not None:
        raise ValueError("Export must contain only waydlp and no global settings")
    app = config["apps"][0]
    gradle = (ROOT / "android/app/build.gradle.kts").read_text(encoding="utf-8")
    if f'applicationId = "{app["id"]}"' not in gradle:
        raise ValueError("Obtainium app ID differs from Android applicationId")
    if app["url"] != "https://github.com/waywhywhy/waydlp-mobile-dart":
        raise ValueError("Obtainium must use the official Android repository")
    settings = json.loads(app["additionalSettings"])
    if settings["includePrereleases"] or not settings["verifyLatestTag"]:
        raise ValueError("Obtainium must track the latest stable release")
    return app, re.compile(settings["apkFilterRegEx"])


def import_link(app):
    payload = quote(json.dumps(app, separators=(",", ":")), safe="")
    return "https://apps.obtainium.imranr.dev/redirect?r=obtainium://app/" + payload


def select_apk(names, pattern):
    matches = [name for name in names if pattern.search(name)]
    if len(matches) != 1 or not matches[0].endswith("-android-universal.apk"):
        raise ValueError(f"Obtainium must select exactly one universal APK, got {matches}")
    return matches[0]


def version_code(pubspec):
    match = re.search(r"^version:\s*\S+\+(\d+)\s*$", pubspec, re.MULTILINE)
    if not match or int(match[1]) < 1:
        raise ValueError("pubspec version must include a positive Android version code")
    return int(match[1])


def check_upgrade(current, previous):
    if version_code(current) <= version_code(previous):
        raise ValueError("Increase pubspec.yaml's +build number for Android/Obtainium updates")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--print-link", action="store_true")
    parser.add_argument("--release-json", type=Path)
    parser.add_argument("--release-dir", type=Path)
    parser.add_argument("--previous-pubspec", type=Path)
    args = parser.parse_args()
    app, pattern = load_config()
    if args.print_link:
        print(import_link(app))
        return
    link = import_link(app)
    for path in (ROOT / "README.md", ROOT / "docs/OBTAINIUM.md"):
        if link not in path.read_text(encoding="utf-8"):
            raise ValueError(f"{path.name}: import link differs from obtainium.json")
    current = (ROOT / "pubspec.yaml").read_text(encoding="utf-8")
    version_code(current)
    if args.previous_pubspec:
        check_upgrade(current, args.previous_pubspec.read_text(encoding="utf-8"))
    if args.release_json:
        release = json.loads(args.release_json.read_text(encoding="utf-8-sig"))
        if release["draft"] or release["prerelease"]:
            raise ValueError("Expected a published stable release")
        print("Selected:", select_apk([a["name"] for a in release["assets"]], pattern))
    if args.release_dir:
        print("Selected:", select_apk([p.name for p in args.release_dir.iterdir()], pattern))
    print("Obtainium configuration and import links validated.")


if __name__ == "__main__":
    main()

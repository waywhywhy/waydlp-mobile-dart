import json
import unittest
from urllib.parse import unquote

from check_obtainium import check_upgrade, import_link, load_config, select_apk


class ObtainiumTests(unittest.TestCase):
    def test_import_link_preserves_nested_json_and_apk_filter(self):
        app, _ = load_config()
        payload = import_link(app).split("obtainium://app/", 1)[1]
        self.assertEqual(json.loads(unquote(payload)), app)
        self.assertFalse(json.loads(app["additionalSettings"])["includePrereleases"])

    def test_selects_only_universal_apk_across_versions(self):
        _, pattern = load_config()
        for version in ("0.1.0", "0.2.0", "1.10.12"):
            names = [f"waydlp-{version}-android-{arch}.apk" for arch in ("arm64", "armv7", "x64", "universal")]
            names += [f"waydlp-{version}-android-universal.aab", "SHA256SUMS.txt", "app-debug.apk"]
            self.assertEqual(select_apk(names, pattern), f"waydlp-{version}-android-universal.apk")

    def test_missing_or_ambiguous_apk_is_rejected(self):
        _, pattern = load_config()
        for names in ([], ["waydlp-1.0.0-android-arm64.apk"], ["waydlp-1.0.0-android-universal.apk", "waydlp-2.0.0-android-universal.apk"]):
            with self.assertRaises(ValueError):
                select_apk(names, pattern)

    def test_update_requires_increasing_android_version_code(self):
        check_upgrade("version: 0.2.0+2\n", "version: 0.1.0+1\n")
        for current in ("version: 0.2.0+1\n", "version: 0.2.0+0\n", "version: 0.2.0\n"):
            with self.assertRaises(ValueError):
                check_upgrade(current, "version: 0.1.0+1\n")


if __name__ == "__main__":
    unittest.main()

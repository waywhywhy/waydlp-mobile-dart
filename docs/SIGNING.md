# Release signing

Android only installs updates that are signed with the same key as the installed app, so **keep the release key safe and never commit it**. `.gitignore` excludes `*.jks`, `*.keystore` and `android/key.properties`.

## Create a key (once)

```bash
keytool -genkeypair -v -keystore waydlp-release.jks -keyalg RSA -keysize 4096 -validity 10000 -alias waydlp
```

Back it up in a password manager or other secure place. If it's lost, existing users can't update without uninstalling first.

## Local builds

Create `android/key.properties` (it's ignored by git):

```properties
storeFile=/absolute/path/waydlp-release.jks
storePassword=…
keyAlias=waydlp
keyPassword=…
```

Then `flutter build apk --release --split-per-abi`. Without a key, release builds are signed with the debug key. Those builds are fine for testing but must **not** be published.

## CI (GitHub Actions)

Add these repository secrets:

| Secret | Value |
|---|---|
| `WAYDLP_KEYSTORE_BASE64` | `base64 -w0 waydlp-release.jks` |
| `WAYDLP_KEYSTORE_PASSWORD` | store password |
| `WAYDLP_KEY_ALIAS` | `waydlp` |
| `WAYDLP_KEY_PASSWORD` | key password |

`release.yml` refuses to publish if they are missing. It verifies the signatures with `apksigner` and creates a **draft** release.

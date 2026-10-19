# Vaultify

Offline password generator and keeper for Windows, macOS, Android and iOS, from
one Flutter codebase. The vault is encrypted with a PIN or master password and
never leaves the device: no network access, no analytics, no crash reporting.

`SPEC.md` is the source of truth for what the app does and how it is built.

## Developing

```bash
flutter pub get
flutter run -d windows        # or: macos, or a device id from `flutter devices`
flutter analyze
flutter test
```

App icons are generated from `assets/icon/`:

```bash
flutter test tool/make_icon.dart      # redraws the icon sources
dart run flutter_launcher_icons       # writes them into each platform folder
```

## Releasing

Pushing a version tag builds every platform and drafts a GitHub Release with
the files attached. The workflow is `.github/workflows/build.yml`.

```bash
# Set the version in pubspec.yaml first (1.0.0+1 style), commit, then:
git tag v1.0.0
git push origin v1.0.0
```

It runs `flutter analyze` and `flutter test` first and packages nothing if
either fails. The tag sets the version, so `v1.0.0` builds version 1.0.0 with
the Actions run number as the build number. The release is left as a **draft**
so the download page can be checked before anyone sees it.

What comes out:

| Platform | File | Notes |
| --- | --- | --- |
| Windows | `Vaultify-Setup.exe` | Inno Setup installer, per-user by default |
| macOS | `Vaultify.dmg` | Drag to Applications |
| Android | `Vaultify-<version>.apk` | Direct install and sharing |
| Android | `Vaultify-<version>.aab` | Play Store upload |
| iOS | `Vaultify-ios-unsigned.zip` | Unsigned build; not installable as is |

The Actions tab can also run the workflow by hand ("Build" > Run workflow),
which produces the same files as downloadable artifacts without making a
release.

### Building the Windows installer locally

Needs [Inno Setup 6](https://jrsoftware.org/isdl.php):

```bash
flutter build windows --release
iscc windows/packaging/vaultify.iss /DAppVersion=1.0.0
# writes build/installer/Vaultify-Setup.exe
```

### Signing

Nothing is signed yet, which is fine for sharing directly but not for the
stores. Until certificates are bought:

- **Windows:** the installer runs, but SmartScreen warns on first download.
  A code-signing certificate removes that.
- **macOS:** the first open needs right-click > Open, because the app is not
  notarized. An Apple Developer account ($99/year) fixes this and also covers
  iOS.
- **Android:** builds are signed with debug keys unless the upload key is
  configured, below. Debug-signed APKs install for testing; the Play Store
  rejects them.
- **iOS:** CI builds without signing, which only proves the build compiles.

**Adding the Android upload key.** Generate a keystore once and keep it safe —
losing it means the Play Store will not accept further updates:

```bash
keytool -genkey -v -keystore upload-keystore.jks -storetype JKS \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

For local release builds, put the keystore next to `android/` and create
`android/key.properties` (git-ignored; paths are relative to `android/`):

```properties
storeFile=upload-keystore.jks
storePassword=...
keyAlias=upload
keyPassword=...
```

For CI, add these repository secrets instead — the workflow writes the same
file and deletes it afterwards:

| Secret | Value |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | `base64 -w0 upload-keystore.jks` |
| `ANDROID_KEYSTORE_PASSWORD` | the store password |
| `ANDROID_KEY_ALIAS` | `upload` |
| `ANDROID_KEY_PASSWORD` | the key password |

With no `ANDROID_KEYSTORE_BASE64` secret set, CI falls back to debug keys and
says so in the log.

### Still to prepare for the stores

A privacy policy page stating that Vaultify collects no data, phone-sized
screenshots, the App Store privacy label ("Data not collected") and the Google
Play Data safety form (nothing collected or shared).

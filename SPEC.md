# Vaultify — Build Brief for Claude Code

Oct 11, 2026 · @ICT4

Vaultify is a small, beautiful, offline password generator and keeper for Windows, macOS, Android and iOS, built from one Flutter codebase. This brief is written to be handed to Claude Code to build it milestone by milestone.

## How to use this brief

Save this brief as `SPEC.md` in an empty project folder, add the `CLAUDE.md` below, then ask Claude Code to build one milestone at a time.

1. Export this doc as Markdown and save it as `SPEC.md` in a new folder, e.g. `vaultify/`.
2. Create `CLAUDE.md` in the same folder with the starter text below.
3. Install Flutter (stable channel) and, for each platform you'll build: Visual Studio with "Desktop development with C++" (Windows), Xcode (macOS and iOS, on a Mac), Android Studio (Android). Run `flutter doctor` until it is clean.
4. Open Claude Code in the folder and say: *"Read SPEC.md and CLAUDE.md, then do Milestone 1 only. Stop and show me when its done-check passes."*
5. Review, run the app, commit, then ask for the next milestone.

**Starter CLAUDE.md**

```markdown
# Vaultify

Offline password generator and keeper. Flutter, one codebase for
Windows, macOS, Android and iOS. Full spec: SPEC.md (source of truth).

## Rules
- Build one milestone from SPEC.md at a time; stop when its done-check passes.
- Never log, print or write passwords, PINs or keys anywhere.
- Never use dart:math Random for secrets; use Random.secure().
- No network access, analytics or crash reporting. The app is offline.
- Crypto code lives only in lib/core/crypto/ and must have unit tests.
- Keep UI code out of lib/core/; core must be testable without Flutter widgets.
- Run `flutter analyze` and `flutter test` before saying a milestone is done.
- Ask before adding any package not listed in SPEC.md.

## Commands
- Run desktop: flutter run -d windows | macos
- Run mobile: flutter run -d <device id>
- Tests: flutter test
```

## Product and scope

v1 generates passwords, saves them under a name, and keeps them encrypted on each device, unlocked by a PIN or master password (plus fingerprint or Face ID on phones).

**Who it's for:** everyday people, shared freely with friends and family. No account, no internet, no ads.

**In v1**

- Generator: uppercase, lowercase, numbers, symbols, custom characters; length; strength meter
- Save with name and optional username
- Saved list: search, show, copy password or username, delete
- PIN or master password; biometric unlock on Android and iOS
- Auto-lock, clipboard auto-clear, wrong-attempt delays
- Light and dark theme following the device

**Not in v1**

- Sync between devices. Each device has its own separate vault in v1; this must be stated clearly in the app's About text.
- Edit, categories, notes, passphrases, history, export/import, browser autofill (see Later versions)
- Recovering a forgotten PIN or password: impossible by design

## Platforms and tech stack

Flutter is chosen because one Dart codebase builds native apps for all four platforms with the same polished UI.

| Platform | Minimum version | Built on |
| --- | --- | --- |
| Windows | 10, 64-bit | Windows PC or GitHub Actions |
| macOS | 12 Monterey | Mac or GitHub Actions |
| Android | 10 (API 29) | Any OS |
| iOS | 15 | Mac only (Xcode), or a cloud Mac in CI |

**Packages (ask before adding others)**

| Need | Package |
| --- | --- |
| Encryption: Argon2id and AES-256-GCM | `cryptography` + `cryptography_flutter` (native speed-ups) |
| App data folder | `path_provider` |
| State management | `flutter_riverpod` |
| Biometric unlock (mobile) | `local_auth` |
| Key storage for biometric unlock | `flutter_secure_storage` (Keychain / Keystore) |
| Desktop window size and position | `window_manager` |
| Display sizes, so a remembered window can't open off screen | `screen_retriever` |
| Backup export / import: system Save and Open windows | `file_picker` |
| Fonts bundled offline | Inter and JetBrains Mono as asset files (no `google_fonts` network loading) |
| Icons | Material Symbols (built into Flutter) |
| App icons | `flutter_launcher_icons` (dev only) |
| Tests | `flutter_test`, `mocktail` |

Clipboard uses Flutter's built-in `Clipboard`. Android screenshot blocking uses a small platform channel setting `FLAG_SECURE` (no extra package).

**Expected size:** about 15–25 MB on desktop, 10–20 MB on phones.

## Security requirements

The PIN or password is never stored; it is stretched into the key that encrypts the vault, and everything else follows from that.

**Unlock secret** (chosen at first launch, changeable in Options)

- PIN: digits only, 6–12 digits; setup recommends 8 or more
- Master password: at least 10 characters
- Setup shows the no-recovery warning with an "I understand" checkbox

**Key derivation:** Argon2id, memory 19 MiB (19456 KiB), 2 iterations, parallelism 1, 32-byte output, random 16-byte salt per vault. Unlock must take under 1 second on a mid-range Android phone; if it is slower, report it before changing parameters.

**Encryption:** AES-256-GCM over the whole entry list, fresh random 12-byte nonce on every save. A wrong PIN is detected by the GCM authentication failure; nothing else is stored to compare against.

**Randomness:** passwords, salts and nonces use a cryptographically secure source only (`Random.secure()` or the `cryptography` package).

**Wrong attempts:** after 5 failures, wait 30 s; then 1 min, 5 min, 15 min for each further failure. The counter and wait end time are saved in settings so restarting the app doesn't reset them.

**Biometric unlock (Android, iOS):** offered after the first successful PIN unlock. When enabled, the vault key is stored in `flutter_secure_storage` and only read after a successful `local_auth` check. The PIN is still required after 5 failed biometric tries, after changing the PIN, and at least every 7 days.

**Auto-lock:** after 5 minutes idle (Options: 1, 5, 15, 30 min, never); immediately when the mobile app goes to the background (Options: immediately, 30 s, 1 min); and on the Lock button or Ctrl/Cmd+L. Locking drops the key and decrypted entries from memory and returns to Unlock.

**Clipboard:** after copying a password, clear it after 30 s (Options: 15, 30, 60 s, off), only if the clipboard still holds that value. On Android 13+ mark the clip as sensitive so it isn't shown in the clipboard preview. On iOS, clearing only happens while the app is open; the Options text says so.

**Screen privacy:** Android sets `FLAG_SECURE` (blocks screenshots and hides the app-switcher preview). iOS shows a plain Vaultify cover when the app goes to the background.

**Never:** log secrets, send anything over the network, include analytics, or keep decrypted data on disk.

## Features

Three areas, Generator, Saved and Options, behave the same everywhere; only touch versus mouse details differ.

### Generator

| Option | Characters | Default |
| --- | --- | --- |
| Uppercase | A–Z | On |
| Lowercase | a–z | On |
| Numbers | 0–9 | On |
| Symbols | `! @ # $ & %` | On |
| Custom | Typed characters, up to 256, duplicates ignored | Off |

- Length: slider 4–64 with − and + buttons beside it; typing in the number allows up to 128. Default 16.
- Every selected set appears at least once, then the result is shuffled with a secure random source.
- No set selected: tapping Generate shows "Pick at least one character type" under the checkboxes.
- A new password is generated when the app opens and whenever an option changes.
- The password box is editable, so an existing password can be pasted in and saved.
- Strength = length × log2(pool size) in bits: under 40 Weak (red), 40–59 Fair (amber), 60–79 Strong (green), 80+ Very strong (green, full bar).
- Save panel: Name (required, max 64), Username (optional), "Save to vault". Duplicate name asks Replace or Keep both (adds "(2)"). After saving: a "Saved" toast and the name fields clear.

### Saved

- Search box filters by name or username as you type; a count reads "4 saved" or "2 of 4".
- Each row: letter badge, name, username (or "No username") with saved date, masked password `••••••`.
- Sort: A–Z by default; option for newest first.
- Actions: show (re-hides after 10 s), copy password, copy username, delete (asks "Delete Gmail? This can't be undone.").
- Empty state: "Save your first password" with a button to the Generator.

### Options

- Change PIN or password; switch between PIN and password
- Biometric unlock on/off (mobile)
- Auto-lock time; background lock delay (mobile)
- Clipboard clear time
- Default generator settings
- Backup: Export backup, Import backup (see "Backup export and import")
- About: version, "Your vault lives only on this device", data folder path (desktop) with an Open folder button

### Desktop versus mobile

|  | Desktop | Mobile |
| --- | --- | --- |
| Navigation | Tabs under the title bar | Bottom navigation bar |
| Row actions | Icons always visible on each row | Tap row → bottom sheet with Show, Copy password, Copy username, Delete; long-press copies password |
| Shortcuts | Ctrl/Cmd+G generate, Ctrl/Cmd+L lock, Ctrl/Cmd+F search | None |
| Unlock | PIN or password | PIN or password, then biometrics if enabled |
| PIN entry | Keyboard | Large on-screen number pad |

## UI design

The approved look is small, calm and clean: white or near-black surfaces, one green accent, thin borders, generous spacing, and the password itself as the hero.

**Principles**

- One strong button per screen (Generate on the Generator). Everything else is outlined or plain.
- The password is the largest thing on the Generator screen, in a monospace font.
- No shadows or gradients; separation comes from 1 px borders and spacing.
- Follow the device's light or dark setting automatically.
- Sentence case for all labels ("Save to vault", not "Save To Vault"); no exclamation marks.

**Colour tokens** (define once in `lib/ui/theme.dart`)

| Token | Light | Dark |
| --- | --- | --- |
| primary (brand green) | `#1A9E5B` | `#3DBE7A` |
| onPrimary | `#FFFFFF` | `#08210F` |
| primarySoft (badges, selected) | `#DCF2E5` | `#173B28` |
| background | `#FFFFFF` | `#111315` |
| surface (password box, cards) | `#F5F6F7` | `#1B1E21` |
| border | `#E3E5E8` | `#2C3034` |
| text | `#16181A` | `#ECEEF0` |
| textSecondary | `#5F6368` | `#A0A6AC` |
| weak / fair / strong | `#D93F3F` / `#D9902B` / primary | `#F26B6B` / `#E8A94E` / primary |

**Type and shape**

- Font: Inter, regular 400 and medium 500 only. Sizes: 12 captions, 13 body, 15 titles, 18 headings.
- Password font: JetBrains Mono, 18 on desktop, 20 on mobile.
- Corners: 8 for controls, 12 for cards and sheets. Spacing on an 8-point grid.
- Touch targets at least 44 × 44 on mobile.

**Generator screen, top to bottom**

1. Title bar: shield-lock icon in green + "Vaultify"; lock icon on the right.
2. Tabs (desktop) or nothing (mobile uses the bottom bar).
3. Password box: surface colour, monospace password, copy icon on the right.
4. Strength bar (4 px, full width, coloured) with the label on the right.
5. Checkboxes in two columns: Uppercase, Lowercase, Numbers, Symbols, Custom (custom field appears under it when ticked).
6. Length row: label, slider, − / + buttons, number.
7. Generate: full-width filled green button with a refresh icon.
8. Divider, then Name field, Username field, outlined "Save to vault" button.

**Saved screen**

1. Search field.
2. Count caption ("4 saved").
3. Rows separated by 1 px lines: 30 × 30 rounded letter badge (primarySoft fill, primary letter), name (medium) over username · date (secondary), masked password, then eye, copy and trash icons (desktop).
4. Status line at the bottom: "Clipboard clears in 24s" on the left, "Locks after 5 min" on the right.

**Unlock and setup screens:** centred column, shield icon, one heading ("Unlock Vaultify" / "Create your PIN"), the field or number pad, one filled button, and the attempts or wait message under it in secondary text.

**Window and layout sizes**

- Desktop window: 420 × 680 by default, minimum 380 × 560, remembers size and position.
- Mobile: full screen, content width capped at 600 and centred on tablets.
- App icon: white shield with a keyhole on a green rounded square.

## Data model and storage

Each device keeps one encrypted vault file and one plain settings file in the app's private support folder from `path_provider` (`getApplicationSupportDirectory()`).

| File | Contents | Secret? |
| --- | --- | --- |
| `vault.vfy` | Encrypted entry list plus the header below | Yes (ciphertext) |
| `vault.vfy.bak` | Previous good save | Yes |
| `settings.json` | Unlock type, auto-lock, clipboard time, generator defaults, failed-attempt counter and wait end time, sort order | No |

**Vault file, format version 1** (JSON):

```json
{
  "format": "vaultify",
  "version": 1,
  "unlock": "pin",
  "kdf": { "alg": "argon2id", "salt": "<base64>", "memoryKiB": 19456, "iterations": 2, "parallelism": 1 },
  "cipher": "aes-256-gcm",
  "nonce": "<base64>",
  "ciphertext": "<base64, includes GCM tag>"
}
```

**Decrypted payload:** `{ "entries": [Entry, …] }`

```dart
class Entry {
  final String id;         // random 16-byte hex
  final String name;       // 1–64 chars
  final String username;   // may be empty
  final String password;
  final DateTime created;  // UTC
  final DateTime updated;  // UTC
}
```

**Saving rules**

- Write to `vault.vfy.tmp`, flush, then rename over `vault.vfy`; copy the old file to `.bak` first.
- Every add or delete saves immediately.
- On load, if `vault.vfy` fails to parse (not a wrong PIN), offer to restore from `.bak`.
- Changing the PIN or password re-derives the key with a new salt and re-encrypts.
- Keep the KDF parameters in the file so future versions can strengthen them and migrate on unlock.

**Backup export and import** (added after M7, pulled forward from Later versions)

- Export (Options): current PIN or password (counts toward wrong tries), then a backup password typed twice (12+ characters, separate from the PIN), then the system Save window. File name `vaultify-backup-YYYY-MM-DD.vaultify`.
- File: same layout as the vault file but `"format": "vaultify-backup"`, an `"exported"` UTC date and no unlock type; Argon2id 64 MiB, 3 iterations, fresh salt and nonce; payload `{ "entries": [...] }`.
- Import (Options): pick a file, enter its backup password (wrong tries don't count toward the PIN lockout), then merge: exact duplicates (name ignoring case, username, password) are skipped; a taken name becomes "Name (2)"; nothing already saved is changed or removed. Files asking for more than 256 MiB / 10 iterations / parallelism 4 are refused.
- Background lock is paused only while Vaultify's own Save / Open window is open.
- No cloud backup of the vault itself: Android `allowBackup="false"`; iOS marks the app support folder excluded from backup.

## Project structure

Core logic (crypto, generator, vault) is pure Dart with no Flutter widgets, so it can be unit-tested on its own.

```text
vaultify/
  CLAUDE.md
  SPEC.md
  pubspec.yaml
  assets/fonts/            Inter, JetBrains Mono
  assets/icon/             app icon source (1024 px)
  lib/
    main.dart
    app.dart               theme, routing, lock gate
    core/
      crypto/              kdf.dart, cipher.dart
      generator/           generator.dart, strength.dart
      vault/               entry.dart, vault_file.dart, vault_repository.dart
      settings/            settings.dart, settings_store.dart
      security/            lockout.dart, auto_lock.dart, clipboard_guard.dart
    ui/
      theme.dart           colour tokens, text styles
      widgets/             password_box, strength_bar, entry_row, number_pad
      screens/             setup, unlock, generator, saved, options
      shell/               desktop_shell.dart (tabs), mobile_shell.dart (bottom bar)
    platform/              biometrics.dart, secure_flag.dart, window.dart
  test/
    core/                  one test file per core file
    ui/                    widget tests for each screen
  .github/workflows/       build.yml
```

The shell is picked at start-up: desktop shell on Windows and macOS, mobile shell on Android and iOS.

## Build milestones

Build in this order, one milestone per Claude Code session; each ends with a done-check you can run yourself.

1. **Project setup.** Create the Flutter project for all four platforms, add the listed packages, fonts, theme tokens and folder structure. *Done when:* `flutter analyze` is clean and an empty themed window runs on your computer in light and dark mode.
2. **Core logic, no UI.** Generator, strength, Argon2id key derivation, AES-GCM encrypt/decrypt, vault file read/write with safe saving, settings store, lockout timing. *Done when:* `flutter test` passes, including: every selected set appears; wrong PIN fails; a tampered file fails; a crash mid-save leaves a readable vault.
3. **Setup and unlock.** First-launch setup (PIN or password, confirm, warning), unlock screen, number pad on mobile, wrong-attempt delays. *Done when:* you can create a PIN, quit, reopen and unlock; 5 wrong tries show the wait.
4. **Generator screen.** Full layout from the UI design section, live strength, copy, save panel. *Done when:* a generated password saves under a name and survives a restart.
5. **Saved screen.** List, search, sort, show, copy, delete; desktop row icons and mobile bottom sheet. *Done when:* every action in the Features section works on desktop and on a phone or emulator.
6. **Options and protection.** Options screen, auto-lock, clipboard clearing, change PIN/password, keyboard shortcuts. *Done when:* the Security behaviour checks in Testing pass.
7. **Mobile extras.** Biometric unlock, background lock, `FLAG_SECURE`, iOS privacy cover, sensitive clipboard flag. *Done when:* fingerprint or Face ID unlocks; screenshots are blocked on Android.
8. **Polish.** App icons, window size memory, empty states, toasts, accessibility labels on icon buttons, final pass against the UI design section. *Done when:* the full acceptance checklist passes on at least one desktop and one phone.
9. **TOTP codes.** Store a TOTP secret on an entry, show the live 6-digit code with its countdown, copy it, and add a secret by scanning a QR code on the phone or by pasting an `otpauth://` link or key on any platform. *Done when:* a code Vaultify shows matches the one another authenticator app shows for the same account at the same moment.
10. **Packaging and CI.** GitHub Actions builds Windows installer, macOS DMG, Android AAB/APK and iOS build on a version tag. *Done when:* a tag produces downloadable files for all four platforms.

## Testing and acceptance

v1 ships when every item passes on Windows 11, macOS 14, one Android phone (Android 13+) and one iPhone (iOS 17+).

**Setup and unlock**

- [ ] PIN rules (6–12 digits) and password rule (10+ characters) are enforced
- [ ] Warning must be ticked before setup completes
- [ ] Correct PIN unlocks; wrong PIN never shows the list
- [ ] 5 wrong tries → 30 s wait, surviving an app restart
- [ ] Changing the PIN re-encrypts; the old PIN stops working
- [ ] Unlock takes under 1 s on a mid-range Android phone

**Generator**

- [ ] Each set alone gives only its characters; all selected sets appear at length 4
- [ ] Length limits 4–128 hold; no set selected shows the hint
- [ ] Strength labels match the bit thresholds
- [ ] Pasted passwords can be saved

**Saved**

- [ ] New entries appear masked; Show re-hides after 10 s
- [ ] Search filters by name and username
- [ ] Duplicate names offer Replace or Keep both
- [ ] Delete asks first; entries survive restart

**Security behaviour**

- [ ] Clipboard clears after 30 s unless something else was copied
- [ ] Idle auto-lock and Ctrl/Cmd+L work on desktop
- [ ] Mobile locks when sent to the background
- [ ] Biometric unlock works; PIN required after 7 days or 5 failed scans
- [ ] Android screenshots are blocked; app-switcher previews are hidden on both phones
- [ ] Opening `vault.vfy` in a text editor shows no names or passwords
- [ ] Killing the app mid-save leaves a vault that opens
- [ ] With network turned off, everything works; with it on, the app makes no requests

**Look and install**

- [ ] Light and dark mode follow the device and match the colour tokens
- [ ] Icon buttons have screen-reader labels
- [ ] Installs and runs on a clean machine or phone with no developer tools

## Release and distribution

Android and Windows can be shared cheaply right away; iOS needs a paid Apple account, which also covers signing the Mac app.

| Platform | Package | How people get it | Account needed |
| --- | --- | --- | --- |
| Windows | `Vaultify-Setup.exe` (Inno Setup) | Website or GitHub Releases; Microsoft Store optional | None to share; a code-signing certificate removes the SmartScreen warning |
| macOS | `Vaultify.dmg` | Website or GitHub Releases | Apple Developer Program ($99/year) to sign and notarize |
| Android | `.aab` for Play Store; `.apk` for direct sharing | Google Play, or APK download | Google Play developer account (one-time $25) |
| iOS | `.ipa` | App Store; TestFlight for testers | Apple Developer Program (same account as macOS) |

**Store requirements to prepare**

- A privacy policy page stating that Vaultify collects no data (both stores require one)
- Store screenshots for phone sizes, using the approved UI
- App Store privacy label: "Data not collected"
- Google Play Data safety form: no data collected or shared

**Versioning:** `1.0.0+1` style in `pubspec.yaml`; a git tag `v1.0.0` triggers the CI build.

## Later versions and open decisions

**Planned after v1**, roughly in priority order:

1. ~~Encrypted export and import~~ (built after M7; see "Backup export and import")
2. Edit an entry; website and notes fields
3. Categories or tags
4. Passphrase mode, e.g. `river-candle-orbit-42`
5. Recently generated history
6. Exclude look-alike characters (`0 O l 1 I`)
7. Old-password warning (over a year)
8. Optional sync between devices (needs its own security design)
9. Linux build; autofill on Android and iOS

**Decided 2026-10-16:** TOTP codes are now milestone 9 (after Polish). Secrets can be added by QR scan on phones, which will need a camera package and camera permission — to be confirmed when that milestone starts.

**Open decisions**

- [ ] Check that the name "Vaultify" and a domain like vaultify.app are free, and that no store app already uses it
- [ ] Pay for signing and store accounts now, or share Android APK and Windows installer first?
- [ ] Minimum PIN length: 6 or 8 digits
- [ ] Where the download page lives: GitHub Releases or a simple website

The earlier PassKeeper/Vaultify product spec used Python for desktop only; this brief replaces it as the source of truth now that mobile is in scope.

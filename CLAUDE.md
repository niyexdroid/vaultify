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

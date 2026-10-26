# Publishing Vaultify

How Vaultify reaches people, in the order it is being done. Build and release
mechanics are in [README.md](README.md); this file covers the accounts, stores
and signing around them.

Current state: **Windows installer and Android APK, direct from GitHub Releases.**
Nothing is code-signed yet. The Play Store, Apple platforms and code signing are
the tracks below.

## Track 1: direct downloads (live)

No accounts, no fees, no review. A version tag builds everything and drafts a
release; publishing that draft is the whole distribution step.

- Download page: <https://niyexdroid.github.io/vaultify/> (GitHub Pages, from `docs/`)
- Privacy policy: <https://niyexdroid.github.io/vaultify/privacy.html>

If Pages is not switched on yet: repository **Settings → Pages → Source: Deploy
from a branch → `main` / `/docs`**. One click, then the two URLs above work.

People installing this way meet a SmartScreen warning on Windows and an
"install unknown apps" prompt on Android. Both are explained on the download
page, which is why that page exists.

## Track 2: Google Play

**Cost:** $25 one-time. **Realistic lead time: three weeks or more**, because of
the testing requirement below, not because of the build.

### Before anything else: the upload key

Android release builds are currently **debug-signed**, which Play rejects. The
workflow signs properly as soon as the four repository secrets exist;
"Signing" in [README.md](README.md#signing) has the `keytool` command and the
exact secret names. Generate the key yourself, so the password is never typed
into a tool that might log it.

Two warnings that matter more for Play than for local builds:

- **Back the keystore up somewhere you will still have in five years.** Lose it
  and you can no longer update the app under the same listing without asking
  Google to reset the key.
- **Never commit it.** `android/.gitignore` already excludes `key.properties`,
  `*.jks` and `*.keystore` — keep it that way.

### The 12-tester requirement

Personal developer accounts created after 13 November 2023 must run a **closed
test with at least 12 testers opted in continuously for 14 days** before they can
even apply for production access. Internal testing does not count, and meeting
the bar does not guarantee approval — Google also asks what the testing changed.

Practical consequences:

- Line up 12 people with Google accounts *before* paying the $25, or the clock
  cannot start.
- Each tester must stay opted in; someone who opts out and back in restarts
  their own 14 days.
- Plan for the closed test to find real bugs. That is what it is for.

### Listing material to prepare

- [ ] Privacy policy URL — done, see Track 1
- [ ] App icon 512×512, and a 1024×500 feature graphic
- [ ] Phone screenshots: at least 2, 16:9 or 9:16, from the real app
- [ ] Short description (80 characters) and full description (4000)
- [ ] Category: Tools. Contains ads: No. In-app purchases: No
- [ ] Content rating questionnaire
- [ ] Target audience and content declarations

### Data safety form answers

Vaultify's answers are all negative, which is unusual and worth getting exactly
right:

| Question | Answer |
| --- | --- |
| Does your app collect or share any of the required user data types? | **No** |
| Is all data encrypted in transit? | Not applicable — the app makes no network connections |
| Do you provide a way for users to request data deletion? | Not applicable — no data is collected; uninstalling removes everything |
| Does your app contain ads? | No |
| Does your app use a third-party SDK that collects data? | No |

The camera permission needs an explanation in the listing, because reviewers ask:
it is used only to scan a two-factor QR code on the device, and no image is
stored or transmitted.

### One decision that cannot be undone

`applicationId` is `app.vaultify.vaultify` (in `android/app/build.gradle.kts`).
**After the first Play upload this can never change** — a different id is a
different app with a different listing and no upgrade path. Settle it, along with
whether the name "Vaultify" and the `vaultify.app` domain are actually free,
before the first upload. Both are still open questions in SPEC.md.

## Track 3: Windows code signing

Signing removes the SmartScreen warning that every first-time Windows user
currently sees. Options, cheapest first:

| Option | Cost | Catch |
| --- | --- | --- |
| **SignPath Foundation** | Free | Open-source projects only, by application, at their discretion |
| Azure Artifact Signing | about $9.99/month | Individuals only in the US and Canada |
| OV certificate | $150–300/year | Available anywhere |
| EV certificate | $400+/year | No longer buys an instant SmartScreen pass, so rarely worth it |

SignPath Foundation is the one to try first, now that Vaultify is Apache-2.0
licensed. Their conditions require:

- An OSI-approved license with no commercial dual-licensing — **done** (Apache-2.0)
- No proprietary components beyond system libraries — true of Vaultify
- An actively maintained project that is **already released** in the form to be
  signed — so apply *after* the first public release, not before
- Builds produced by the project's own CI, from its own source — true; the
  workflow is public
- Multi-factor authentication on the source repository — check this is on for
  the GitHub account before applying

Note that no certificate makes the warning vanish immediately: SmartScreen
reputation accumulates as a signed binary is downloaded over time.

## Track 4: Apple (macOS and iOS)

Blocked on an Apple Developer account ($99/year), which covers both. Before
spending it, note that neither the Mac app nor the iOS build has ever been run on
real hardware — only compiled in CI. The acceptance checklist in SPEC.md should
pass on a Mac and an iPhone first; the account is what turns those builds into
something installable and notarized, and it cannot fix a bug nobody has seen yet.

# OmniVoice V3 Release Checklist

## Required Before Tagging

- `swift test`
- `engine/.venv/bin/python -m pytest engine/tests`
- `git diff --check`
- `./script/build_and_run.sh --verify`
- `curl -fsS http://127.0.0.1:8765/health`

## Required For Local DMG

- `./script/build_and_run.sh --dmg`
- `/usr/bin/codesign --verify --deep --strict --verbose=2 dist/OmniVoice.app`
- `/usr/bin/hdiutil verify dist/OmniVoice.dmg`
- `/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' dist/OmniVoice.app/Contents/Info.plist`

## Required For Public Distribution

- Build with a Developer ID Application certificate through `OMNIVOICE_CODESIGN_IDENTITY`.
- Confirm hardened runtime and entitlement requirements.
- Submit the DMG to Apple notarization.
- Staple the notarization ticket.
- Re-run Gatekeeper validation on a clean machine.

## Auto-Update Release (Sparkle)

Updates ship via Sparkle: the app reads `SUFeedURL`
(`https://github.com/MichaelDanCurtis/OmniVoice/releases/latest/download/appcast.xml`)
and `SUPublicEDKey` from `Info.plist`, then downloads, verifies the EdDSA signature **and**
Apple notarization, installs, and relaunches. The in-app updater (`UpdaterViewModel`, the
menu's "Check for Updates…") and the Sparkle key pair are already in place — the public key
in `Info.plist` matches the private key in the login keychain.

### One-time prerequisites (account holder only — these cannot be scripted)

1. **Developer ID Application certificate** — Xcode → Settings → Accounts → (team
   `P7R2A675CN`) → Manage Certificates → `+` → **Developer ID Application**. Verify:
   ```
   security find-identity -v -p codesigning ~/Library/Keychains/login.keychain-db | grep "Developer ID Application"
   ```
2. **Notary profile** (uses an app-specific password from appleid.apple.com — keep it off
   the agent):
   ```
   xcrun notarytool store-credentials omnivoice-notary \
     --apple-id michaeldancurtis@gmail.com --team-id P7R2A675CN --password <app-specific-password>
   ```
3. **Back up the Sparkle private key** (login keychain, service `https://sparkle-project.org`).
   Losing it means existing installs can never be updated again.

> Until 1 and 2 exist, auto-update cannot ship: Sparkle requires the update to be
> Developer-ID-signed **and** notarized, and Gatekeeper blocks anything less.

### Cut a release (one command once the prerequisites exist)

```
OMNIVOICE_APP_VERSION=<x.y.z> ./script/build_and_run.sh --dmg        # build the .app + .dmg
OMNIVOICE_APP_VERSION=<x.y.z> OMNIVOICE_PUBLISH=1 ./script/sign_and_notarize.sh
```

The second command signs (Sparkle helpers inside-out, hardened runtime, entitlements),
notarizes + staples the app and DMG, EdDSA-signs the DMG, writes `dist/appcast.xml`, and —
with `OMNIVOICE_PUBLISH=1` — creates/updates the `v<x.y.z>` GitHub release (marked **latest**)
with both `OmniVoice.dmg` and `appcast.xml`. Release notes come from
`docs/V3_RELEASE_NOTES.md` (override with `OMNIVOICE_RELEASE_NOTES=<path>`). Omit
`OMNIVOICE_PUBLISH` to upload the two assets to the release manually instead.

Bump `OMNIVOICE_APP_VERSION` for every release so `CFBundleShortVersionString` exceeds the
installed build — Sparkle compares versions to decide whether to offer the update.

## Local Runtime Packaging

The local DMG bundles the Swift app, engine source launcher, embedded Python runtime, and a Python wheelhouse for the normal core/ASR/MLX runtime packages. First launch creates the engine venv under `~/Library/Application Support/OmniVoice` from bundled resources.

Model weights are still external by design. Users download or select models through the app or engine dashboard.

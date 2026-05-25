# Release process

Mullion ships as a notarized, stapled DMG with Sparkle 2 auto-updates.
This document covers the **one-time setup** (the things you only do
once, ever) and the **per-release flow** (run `make release`).

## One-time setup

### 1. Apple Developer Program

You need an active [Apple Developer Program](https://developer.apple.com/programs/)
membership ($99/yr) to issue a **Developer ID Application** certificate.
Mullion is distributed outside the App Store, so a Developer ID cert is
required for notarization.

In Xcode → Settings → Accounts:
- Sign in with your Apple ID
- Manage Certificates… → + → "Developer ID Application"
- Verify the cert is installed in Keychain Access (login keychain)

Find the cert's full common name; you'll need it for env vars:

```sh
security find-identity -v -p codesigning | grep "Developer ID Application"
```

It looks like: `Developer ID Application: Your Name (ABC1234567)`.

### 2. Notarization credentials

Generate an [App Store Connect API key](https://appstoreconnect.apple.com/access/api)
with the **Developer** role. Download the `.p8` file once — Apple won't
let you re-download it.

Store the credentials in a keychain profile so `notarytool` can find them:

```sh
xcrun notarytool store-credentials mullion-notary \
  --key /path/to/AuthKey_XXXXXXXX.p8 \
  --key-id XXXXXXXX \
  --issuer YOUR_ISSUER_UUID
```

The profile name (`mullion-notary`) is what you'll pass as
`NOTARY_KEYCHAIN_PROFILE`.

### 3. Sparkle EdDSA keypair

Sparkle signs every release with an EdDSA private key; the public key is
embedded in the app's Info.plist. Generate the keypair once and **never
rotate it** unless absolutely necessary (every installed Mullion needs
the matching public key to accept updates).

The `generate_keys` tool ships with the Sparkle SPM package. After the
first build, find it in DerivedData:

```sh
find ~/Library/Developer/Xcode/DerivedData -name generate_keys -type f | head -1
```

Run it once:

```sh
./path/to/generate_keys
```

It stores the private key in your login Keychain (item name
`https://sparkle-project.org/...`) and prints the public key. Paste the
public key into `Mullion/Resources/Info.plist`:

```xml
<key>SUPublicEDKey</key>
<string>(paste the public key here)</string>
```

**Back up the private key.** Keychain → File → Export Items… → password-
protected .p12. Store it somewhere durable (1Password, encrypted backup).
Losing the private key means every installed Mullion stops auto-updating
permanently.

### 4. Feed URL

Decide where to host `appcast.xml`. Two reasonable choices:

- **GitHub Pages** (recommended): enable Pages on the repo, source =
  `main` branch / `/docs` folder. The feed URL becomes
  `https://<owner>.github.io/<repo>/appcast.xml`.
- **Raw GitHub**: `https://raw.githubusercontent.com/<owner>/<repo>/main/docs/appcast.xml`.
  Easier (no Pages enablement) but CDN-cached for ~5 minutes after each
  push.

Replace `SUFeedURL` in `Mullion/Resources/Info.plist` with your choice.

## Per-release flow

Once setup is done:

```sh
VERSION=0.2.0 \
DEVELOPER_ID_APP="Developer ID Application: Your Name (TEAMID)" \
NOTARY_KEYCHAIN_PROFILE=mullion-notary \
make release
```

This runs `scripts/release.sh`, which:

1. Refuses to proceed if `Info.plist` still contains `CHANGE_ME`
   placeholders
2. Generates the Xcode project from `project.yml`
3. Archives with manual signing (`Developer ID Application`)
4. Exports to `release-build/export/Mullion.app`
5. Verifies codesign
6. Builds a DMG with the app + an `/Applications` symlink
7. Submits to Apple's notary service (`notarytool submit --wait`)
8. Staples the notarization ticket
9. Sparkle-signs the DMG with `sign_update`
10. Prints an `<item>` snippet for `docs/appcast.xml`

Output: `release-build/Mullion-<VERSION>.dmg`.

### Posting the release

1. Create a git tag: `git tag v<VERSION> && git push --tags`
2. Create a GitHub Release for that tag and upload the DMG as a release
   asset.
3. Paste the `<item>` snippet into `docs/appcast.xml` (replace the
   placeholder `OWNER/REPO` URL with the real one).
4. Commit the appcast update and push (or wait for the Pages deploy if
   you configured Pages).

Installed Mullions will detect the new version on their next update
check (default cadence is daily; manual via menu bar → Check for
Updates…).

## Troubleshooting

- **"sign_update not found"**: build the project at least once
  (`xcodebuild -project Mullion.xcodeproj -scheme Mullion build`) so
  Sparkle's tooling lands in DerivedData. Alternative:
  `brew install sparkle`.
- **Notarization fails**: `xcrun notarytool log <submission-id>
  --keychain-profile mullion-notary` shows the per-issue log.
- **Sparkle won't update**: check `Console.app` filtered to the
  `com.mullion.Mullion` subsystem and category `updater`. The most
  common cause is a public key in Info.plist that doesn't match the
  private key used to `sign_update` the DMG.
- **DMG won't open on Gatekeeper**: `spctl --assess --verbose=4
  release-build/Mullion-<VERSION>.dmg` reproduces what Gatekeeper sees
  on a clean machine.

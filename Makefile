APP = Mullion

.PHONY: update
update:
	git pull
	xcodegen generate
	xcodebuild -project $(APP).xcodeproj -scheme $(APP) -configuration Release -derivedDataPath build -destination 'platform=macOS' build
	-pkill -x $(APP)
	rm -rf /Applications/$(APP).app
	cp -R build/Build/Products/Release/$(APP).app /Applications/
	open /Applications/$(APP).app

# Build, sign, notarize, staple, package into a DMG, and Sparkle-sign it.
# See docs/release.md for the one-time Apple Developer + Sparkle setup.
#
# Required env vars (fail-fast in scripts/release.sh):
#   VERSION                  semver string, e.g. 0.2.0 (default: from git tag)
#   DEVELOPER_ID_APP         "Developer ID Application: Name (TEAMID)"
#   NOTARY_KEYCHAIN_PROFILE  name stored via `xcrun notarytool store-credentials`
# Optional:
#   SPARKLE_PRIVATE_KEY_PATH path to the EdDSA private key; defaults to
#                            the Keychain item Sparkle generates by default.
.PHONY: release
release:
	./scripts/release.sh

# Clean every artifact directory the build pipeline writes to. Does NOT
# touch DerivedData (Xcode owns that) or .git.
.PHONY: clean
clean:
	rm -rf build release-build $(APP).xcarchive

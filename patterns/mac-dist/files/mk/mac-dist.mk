# mac-dist.mk — a release of the Mac app outside the App Store: signed with
# a Developer ID, notarized, stapled, zipped, checked as Gatekeeper will
# check it, and published as a GitHub release.
#
# Imported by peru from the app-tooling pattern `mac-dist`
# (https://github.com/tikitu/app-tooling). Never edit it here: `peru sync`
# refuses to overwrite a changed copy, and the change belongs in app-tooling.
# docs/app-tooling/mac-dist/ says how to use it.
#
# The project's Makefile sets these, then `include mk/mac-dist.mk`:
#
#   MAC_DIST_APP           the built .app to release                 (required)
#   MAC_DIST_NAME          the name in the zip's and release's name  (required)
#   MAC_DIST_ENTITLEMENTS  the app's entitlements file               (required)
#   MAC_DIST_BUILD         the target that builds $(MAC_DIST_APP) in its
#                          release configuration                     (required)
#   MAC_DIST_CLEAN         the target that removes earlier builds and
#                          $(DIST_DIR)                       (default: clean)
#   MAC_DIST_SIGN_NESTED   a target of the project's that signs code nested
#                          in the app (a helper tool, a helper app), with
#                          $(mac_dist_codesign); it must depend on
#                          $(MAC_DIST_BUILD), and its rule must come after
#                          the Makefile's default target    (optional)
#   TEAM_ID, DEVELOPER_NAME  as on the Developer ID Application certificate
#   NOTARY_PROFILE         the notarytool keychain profile
#
# The targets read MAC_DIST_BUILD, MAC_DIST_CLEAN and MAC_DIST_SIGN_NESTED as
# prerequisites, so set them before the include: make reads prerequisites as
# it reads the rule.
#
# From the command line: VERSION=… (a trial without a tag), CERT_NAME=… (the
# identity in full), NOTES_FILE=… (github-release), and notary-setup's own.

# Leave the including Makefile's default goal alone, wherever the include is.
_mac_dist_default_goal := $(.DEFAULT_GOAL)

# The version, in this order:
#   1. VERSION=… on the command line (a trial, no tag needed).
#   2. An exact `vX.Y.Z` git tag at HEAD (the canonical `make dist` path,
#      which also requires a clean checkout).
#   3. The VERSION file at the repo root (preview the pipeline before tagging).
GIT_TAG_VERSION := $(shell git describe --tags --exact-match --match 'v[0-9]*' 2>/dev/null | sed 's/^v//')
FILE_VERSION    := $(shell test -f VERSION && sed -n '1p' VERSION | tr -d '[:space:]')
VERSION         ?= $(or $(GIT_TAG_VERSION),$(FILE_VERSION))

MAC_DIST_CLEAN ?= clean

DIST_DIR    ?= dist
NOTARY_ZIP  := $(DIST_DIR)/$(MAC_DIST_NAME)-$(VERSION)-notary.zip
RELEASE_ZIP := $(DIST_DIR)/$(MAC_DIST_NAME)-$(VERSION)-macos.zip

# The identity names the Developer ID in full: a Mac that also holds an
# "Apple Distribution" or "Apple Development" identity of the same team
# could otherwise be asked for the wrong one.
CERT_NAME ?= $(if $(TEAM_ID),Developer ID Application: $(DEVELOPER_NAME) ($(TEAM_ID)),)

# Hand-written notes for `make github-release` (generated ones otherwise).
# Keep the file outside the worktree, not in dist/: `make dist` starts with
# the clean target, which deletes dist/. The GitHub release is where the
# notes live.
NOTES_FILE ?=

# Signs one piece of code for distribution: the Developer ID, the hardened
# runtime and a secure timestamp, all three of which notarization requires
# of every executable in the app. For MAC_DIST_SIGN_NESTED's recipe, with
# the path (and usually --identifier) after it.
mac_dist_codesign = codesign --force --options runtime --timestamp --sign "$(CERT_NAME)"

.PHONY: dist check-version print-version notary-setup sign zip-notary notarize staple \
        zip-release checksum verify-release github-release

# sign → zip-notary → notarize → staple → zip-release → checksum →
# verify-release. Two zips on purpose: the notary service takes a zip;
# stapling writes the ticket into the .app; the zip that is distributed is a
# fresh one taken after stapling.
#
#   git tag v0.1.0 && make dist
dist: check-version $(MAC_DIST_CLEAN) $(MAC_DIST_BUILD) sign zip-notary notarize staple zip-release checksum verify-release
	@echo "✓ release artifact ready: $(RELEASE_ZIP)"
	@echo "  next: make github-release   (or upload $(RELEASE_ZIP) manually)"

check-version:
	@[ -n "$(MAC_DIST_APP)" ] && [ -n "$(MAC_DIST_NAME)" ] && [ -n "$(MAC_DIST_ENTITLEMENTS)" ] && [ -n "$(MAC_DIST_BUILD)" ] || \
	  { echo "✗ set MAC_DIST_APP, MAC_DIST_NAME, MAC_DIST_ENTITLEMENTS and MAC_DIST_BUILD before including mk/mac-dist.mk"; exit 1; }
	@if [ -z "$(VERSION)" ]; then \
	  echo "✗ VERSION is empty — no exact vX.Y.Z git tag at HEAD and no VERSION file."; \
	  echo "  Tag the release first:   git tag v0.1.0 && make dist"; \
	  echo "  Or override:             make dist VERSION=0.1.0"; \
	  exit 1; \
	fi
	@if [ -z "$(GIT_TAG_VERSION)" ]; then \
	  echo "✗ make dist requires an exact 'vX.Y.Z' git tag at HEAD."; \
	  echo "  HEAD currently has no matching tag; VERSION=$(VERSION) came from a fallback."; \
	  echo "  Tag the release first:   git tag v$(VERSION) && make dist"; \
	  exit 1; \
	fi
	@# The release carries the tag's name, so it must be exactly the tagged
	@# commit: no changed files and no untracked ones (git-ignored build
	@# output does not count). This runs before the clean and the build, so
	@# only what was there beforehand is checked.
	@if [ -n "$$(git status --porcelain)" ]; then \
	  echo "✗ make dist requires a clean checkout. These would go into a release"; \
	  echo "  labelled v$(VERSION) that does not contain them:"; \
	  git status --short | sed 's/^/    /'; \
	  echo "  Commit or remove them; build output belongs in .gitignore."; \
	  exit 1; \
	fi
	@echo "→ release version $(VERSION)"

print-version:
	@echo "VERSION=$(VERSION)"
	@echo "  git tag at HEAD: $(if $(GIT_TAG_VERSION),$(GIT_TAG_VERSION),(none))"
	@echo "  VERSION file:    $(if $(FILE_VERSION),$(FILE_VERSION),(missing))"

# Stores the notary credentials in the keychain, once per Mac. Preferably an
# App Store Connect team API key: it belongs to the team rather than a
# person, needs no password or phone, and can be revoked at any time.
# Without one, an Apple Account and an app-specific password, typed at the
# prompt, never on the command line.
notary-setup:
	@command -v xcrun >/dev/null 2>&1 || { echo "✗ xcrun not found — install Xcode or the Command Line Tools"; exit 1; }
	@[ -n "$(NOTARY_PROFILE)" ] || { echo "✗ NOTARY_PROFILE is empty: set it in the Makefile"; exit 1; }
ifdef API_KEY
	@[ -f "$(API_KEY)" ] || { echo "✗ API_KEY=$(API_KEY): no such file (the AuthKey_<KeyID>.p8 you downloaded)"; exit 1; }
	@if [ -z "$(API_KEY_ID)" ] || [ -z "$(API_ISSUER)" ]; then \
	  echo "✗ make notary-setup API_KEY=AuthKey_XXXX.p8 API_KEY_ID=XXXX API_ISSUER=<issuer id>"; exit 1; \
	fi
	@echo "→ storing the API key in keychain profile '$(NOTARY_PROFILE)'"
	xcrun notarytool store-credentials "$(NOTARY_PROFILE)" \
	  --key "$(API_KEY)" --key-id "$(API_KEY_ID)" --issuer "$(API_ISSUER)"
	@echo "✓ stored. Keep $(API_KEY) wherever the team keeps secrets, and delete it from disk."
else
	@if [ ! -t 0 ]; then \
	  echo "✗ make notary-setup without an API key is interactive — run it in a real terminal,"; \
	  echo "  not from an editor or agent shell (it prompts for a password). Either:"; \
	  echo "    make notary-setup API_KEY=AuthKey_XXXX.p8 API_KEY_ID=XXXX API_ISSUER=<issuer id>"; \
	  echo "  or, with an app-specific password from https://appleid.apple.com:"; \
	  echo "    make notary-setup APPLE_ID=you@example.com TEAM_ID=XXXXXXXXXX"; \
	  exit 1; \
	fi
	@if [ -z "$(TEAM_ID)" ]; then echo "✗ TEAM_ID required: make notary-setup TEAM_ID=XXXXXXXXXX APPLE_ID=you@example.com"; exit 1; fi
	@echo "→ storing notary credentials in keychain profile '$(NOTARY_PROFILE)' (team $(TEAM_ID))"
	xcrun notarytool store-credentials "$(NOTARY_PROFILE)" \
	  --team-id "$(TEAM_ID)" \
	  $(if $(APPLE_ID),--apple-id "$(APPLE_ID)",)
	@echo "✓ stored. 'make dist' / 'make notarize' will use profile '$(NOTARY_PROFILE)'."
endif

# Inside out: MAC_DIST_SIGN_NESTED signs the nested code first, then the app,
# whose signature seals it.
sign: $(MAC_DIST_BUILD) $(MAC_DIST_SIGN_NESTED)
	@if [ -z "$(CERT_NAME)" ]; then echo "✗ CERT_NAME required (set TEAM_ID, or pass CERT_NAME=...)"; exit 1; fi
	@echo "→ signing $(MAC_DIST_APP) as $(CERT_NAME)"
	$(mac_dist_codesign) --entitlements "$(MAC_DIST_ENTITLEMENTS)" "$(MAC_DIST_APP)"
	codesign --verify --strict --verbose=2 "$(MAC_DIST_APP)"

zip-notary: sign
	@mkdir -p "$(DIST_DIR)"
	rm -f "$(NOTARY_ZIP)"
	ditto -c -k --keepParent "$(MAC_DIST_APP)" "$(NOTARY_ZIP)"
	@echo "✓ wrote $(NOTARY_ZIP)"

notarize: zip-notary
	@if [ -z "$(NOTARY_PROFILE)" ]; then \
	  echo "✗ NOTARY_PROFILE is empty. Run 'make notary-setup' once first."; \
	  exit 1; \
	fi
	@echo "→ submitting $(NOTARY_ZIP) via profile '$(NOTARY_PROFILE)' (a few minutes)"
	xcrun notarytool submit "$(NOTARY_ZIP)" \
	  --keychain-profile "$(NOTARY_PROFILE)" \
	  --wait

staple: notarize
	xcrun stapler staple "$(MAC_DIST_APP)"
	xcrun stapler validate "$(MAC_DIST_APP)"

zip-release: staple
	rm -f "$(RELEASE_ZIP)"
	ditto -c -k --keepParent "$(MAC_DIST_APP)" "$(RELEASE_ZIP)"
	@echo "✓ wrote $(RELEASE_ZIP)"

checksum: zip-release
	cd "$(DIST_DIR)" && shasum -a 256 "$$(basename $(RELEASE_ZIP))" > "$$(basename $(RELEASE_ZIP)).sha256"
	@echo "✓ wrote $(RELEASE_ZIP).sha256"

# What Gatekeeper will say on another Mac: "accepted",
# "source=Notarized Developer ID".
verify-release: zip-release
	spctl --assess --type execute --verbose "$(MAC_DIST_APP)"
	codesign --verify --deep --strict --verbose=2 "$(MAC_DIST_APP)"

github-release:
	@if ! command -v gh >/dev/null 2>&1; then echo "✗ gh CLI not installed (brew install gh)"; exit 1; fi
	@if [ -z "$(VERSION)" ]; then echo "✗ VERSION required (tag or override)"; exit 1; fi
	@if [ ! -f "$(RELEASE_ZIP)" ]; then echo "✗ $(RELEASE_ZIP) not found — run make dist first"; exit 1; fi
	@if [ ! -f "$(RELEASE_ZIP).sha256" ]; then echo "✗ $(RELEASE_ZIP).sha256 not found — run make dist first"; exit 1; fi
	gh release create "v$(VERSION)" \
	  "$(RELEASE_ZIP)" \
	  "$(RELEASE_ZIP).sha256" \
	  --title "$(MAC_DIST_NAME) $(VERSION)" \
	  $(if $(NOTES_FILE),--notes-file "$(NOTES_FILE)",--generate-notes)
	@echo "✓ published v$(VERSION)"

.DEFAULT_GOAL := $(_mac_dist_default_goal)

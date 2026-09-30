# Starter — build front door.
#
# The Mac app is pure SwiftPM (swift build + ./build.sh), no Xcode project.
#
# Quick start:
#   make           # debug-builds via SwiftPM into ./build/Starter.app
#   make run       # build + launch, in front
#   make check     # compile only, no bundling/signing (agent / CI gate)
#   make test      # run the SwiftPM test suite
#   make help      # full target list

CONFIG       := debug
# Two packages, split by platform rather than by `#if`: SHARED declares macOS
# and iOS and holds everything that is not Mac-specific; PACKAGE is macOS only
# and holds the Mac app. `check` compiles SHARED for iOS too, so it stays
# platform-neutral even while there is no iOS app.
SHARED       := Packages/StarterKit
PACKAGE      := Packages/StarterMacKit
APP          := build/Starter.app
BUNDLE_ID    := org.example.starter
LSREGISTER   := /System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister
MIN_MACOS    := 26

APP_NAME      := Starter
DISPLAY_NAME  := Starter App
ENTITLEMENTS  := StarterMac/StarterMac.entitlements

# ---------------------------------------------------------------------------
# Release variables
# ---------------------------------------------------------------------------
# Version is resolved in this order:
#   1. VERSION=... on the command line (one-off testing, no tag needed).
#   2. An exact `vX.Y.Z` git tag at HEAD (the canonical `make dist` path).
#   3. The VERSION file at the repo root (preview the pipeline pre-tag).
GIT_TAG_VERSION := $(shell git describe --tags --exact-match --match 'v[0-9]*' 2>/dev/null | sed 's/^v//')
FILE_VERSION    := $(shell test -f VERSION && sed -n '1p' VERSION | tr -d '[:space:]')
VERSION         ?= $(or $(GIT_TAG_VERSION),$(FILE_VERSION))

DIST_DIR      := dist
NOTARY_ZIP    := $(DIST_DIR)/$(APP_NAME)-$(VERSION)-notary.zip
RELEASE_ZIP   := $(DIST_DIR)/$(APP_NAME)-$(VERSION)-macos.zip

# Dev signing identity. Ad-hoc is enough until the app needs an entitlement
# that a provisioning profile has to grant, such as iCloud.
DEV_IDENTITY  ?= -

# Distribution signing. Developer ID + hardened runtime + notarization.
# Fill in TEAM_ID and DEVELOPER_NAME (as on the certificate) before the first
# `make dist`, or pass CERT_NAME=... in full.
TEAM_ID        ?=
DEVELOPER_NAME ?=
CERT_NAME      ?= $(if $(TEAM_ID),Developer ID Application: $(DEVELOPER_NAME) ($(TEAM_ID)),)

# Notarization credentials profile name. Populate once with
# `make notary-setup` (interactive; never puts the password on the cmdline).
NOTARY_PROFILE ?= starter-notary

NOTES_FILE       ?=

# app-tooling-update and app-tooling-check, for the conventions imported from
# app-tooling (peru.yaml; docs/app-tooling/pattern-imports/README.md).
include mk/app-tooling.mk

.PHONY: all deps outdated update-pins check-pins check-shared-ios build check test release run run-background run-scratch scratch-reset \
        screenshot clean install uninstall register help \
        icon check-version notary-setup sign zip-notary notarize staple zip-release \
        checksum verify-release dist github-release print-version \
        fmt fmt-check lint rules

all: build

help:
	@echo "Build:"
	@echo "  make / build      Build $(CONFIG) into ./$(APP)  (default)"
	@echo "  check             Compile only — the Mac app, and the shared package for iOS; CI/agent gate"
	@echo "  test              Run the SwiftPM test suite"
	@echo "  release           Build release into ./$(APP)"
	@echo "  run               Build and launch $(APP_NAME), in front, as if opened from Finder"
	@echo "  run-background    The same, but launched behind whatever has focus (for agents)"
	@echo "  run-scratch       Build and launch in the background, on scratch data, accepting commands"
	@echo "  scratch-reset     Delete the scratch database and settings"
	@echo "  screenshot        Capture the running app's window to build/window.png, without focus"
	@echo "  icon              Regenerate build/AppIcon.icns from scripts/make-icon.swift"
	@echo "  clean             Remove ./build/ ./.build/ ./dist/"
	@echo "  deps              Verify build prerequisites (auto-run before build)"
	@echo "  outdated          List dependencies with newer versions allowed (changes nothing)"
	@echo "  update-pins       Re-resolve both packages to the newest allowed versions; review the diff"
	@echo "  check-pins        Check the two packages pin the same versions (run by every build)"
	@echo "  app-tooling-update  Move to the newest app-tooling commit peru.yaml follows; prints the steps"
	@echo "  app-tooling-check   Check files imported from app-tooling match peru.yaml's pin"
	@echo ""
	@echo "Lint / format:"
	@echo "  fmt               Reformat every Swift file in place (swift format)"
	@echo "  fmt-check         Fail if any Swift file is not formatted"
	@echo "  rules             Test the ast-grep rules, then scan (see rules/README.md)"
	@echo "  lint              fmt-check + rules — the whole non-compiling gate"
	@echo ""
	@echo "Local install:"
	@echo "  install           Copy $(APP_NAME).app to /Applications/ and register it"
	@echo "  uninstall         Remove /Applications/$(APP_NAME).app"
	@echo "  register          Refresh LaunchServices for ./$(APP)"
	@echo ""
	@echo "Release pipeline (require an exact 'vX.Y.Z' git tag + signing identity):"
	@echo "  notary-setup      One-time: store notary creds in keychain ($(NOTARY_PROFILE))"
	@echo "  dist              Build → sign → notarize → staple → zip → checksum"
	@echo "  github-release    Upload \$$(RELEASE_ZIP) + .sha256 to a GitHub release"
	@echo "  print-version     Print resolved release VERSION"
	@echo ""
	@echo "  help              Show this message"

# ---------------------------------------------------------------------------
# Prerequisite checks
# ---------------------------------------------------------------------------

deps:
	@echo "→ Checking build prerequisites..."
	@OS_VERSION=$$(sw_vers -productVersion 2>/dev/null); \
	if [ -z "$$OS_VERSION" ]; then \
	  echo "  ✗ Could not detect macOS version. $(APP_NAME) only builds on macOS."; exit 1; \
	fi; \
	OS_MAJOR=$$(echo $$OS_VERSION | cut -d. -f1); \
	if [ $$OS_MAJOR -lt $(MIN_MACOS) ]; then \
	  echo "  ✗ macOS $$OS_VERSION — $(APP_NAME) requires macOS $(MIN_MACOS).0 or newer."; exit 1; \
	fi; \
	echo "  ✓ macOS $$OS_VERSION"
	@command -v swift >/dev/null 2>&1 || { \
	  echo "  ✗ swift not on PATH. Install Xcode (App Store) or the Swift toolchain"; \
	  echo "    from https://swift.org/install/macos/, then re-run."; exit 1; }
	@SW_LINE=$$(swift --version 2>&1 | head -1); \
	echo "  ✓ $$SW_LINE"
	@for pkg in $(SHARED) $(PACKAGE); do \
	  [ -f $$pkg/Package.swift ] || { echo "  ✗ $$pkg/Package.swift not found. Run make from the repo root."; exit 1; }; \
	  [ -f $$pkg/Package.resolved ] || { \
	    echo "  ✗ $$pkg/Package.resolved is missing: dependencies are pinned, and a build"; \
	    echo "    without the lockfile would resolve afresh. Restore it from git."; exit 1; }; \
	done
	@echo "  ✓ Package.resolved present in both packages"
	@$(MAKE) -s check-pins
	@[ -x ./build.sh ] || { echo "  ✗ ./build.sh missing or not executable."; exit 1; }
	@echo "→ Prerequisites OK."

# ---------------------------------------------------------------------------
# Pinned dependencies
#
# Every build uses exactly the versions in the committed Package.resolved, and
# fails rather than re-resolving (--force-resolved-versions). Moving a pin is a
# deliberate, reviewable change: `make outdated` says what could move,
# `make update-pins` moves it, and the diff of Package.resolved is the review.
#
# The two packages resolve separately, so each has its own Package.resolved,
# and nothing in SwiftPM stops them drifting apart: the Mac app would then be
# built against one version of a library and tested against another.
# `check-pins` fails the build when they disagree; `update-pins` moves both
# together.
# ---------------------------------------------------------------------------

SWIFT_PINNED := --force-resolved-versions

outdated:
	@swift package --package-path $(SHARED) update --dry-run
	@swift package --package-path $(PACKAGE) update --dry-run

update-pins:
	swift package --package-path $(SHARED) update
	swift package --package-path $(PACKAGE) update
	@$(MAKE) -s check-pins
	@git --no-pager diff --stat -- $(SHARED)/Package.resolved $(PACKAGE)/Package.resolved

check-pins:
	@python3 scripts/check-pins.py $(SHARED)/Package.resolved $(PACKAGE)/Package.resolved \
	  || { echo "  ✗ the two Package.resolved files disagree — run 'make update-pins'"; exit 1; }
	@echo "  ✓ dependency pins agree"

# ---------------------------------------------------------------------------
# Build (delegates to ./build.sh: swift build + bundle + codesign)
# ---------------------------------------------------------------------------

ICON_SCRIPT := scripts/make-icon.swift
APP_ICON    := build/AppIcon.icns

# App icon: regenerated when the script changes. The script renders the icon
# at every macOS size and iconutil packages them.
$(APP_ICON): $(ICON_SCRIPT)
	@mkdir -p build
	@swift $(ICON_SCRIPT)
	@iconutil -c icns build/AppIcon.iconset -o $(APP_ICON)
	@echo "✓ $(APP_ICON)"

icon: $(APP_ICON)

build: deps $(APP_ICON)
	SIGN_IDENTITY="$(DEV_IDENTITY)" VERSION="$(VERSION)" ./build.sh $(CONFIG)

release: deps $(APP_ICON)
	SIGN_IDENTITY="$(DEV_IDENTITY)" VERSION="$(VERSION)" ./build.sh release

# Compile-only gate — no .app, no signing. CI / agent verification. Building
# the Mac package compiles the shared one for the Mac along the way.
check: deps check-shared-ios
	swift build --package-path $(PACKAGE) -c $(CONFIG) $(SWIFT_PINNED)
	@echo "✓ compiles ($(CONFIG))"

# The shared package, compiled for iOS. This is what keeps it free of Mac-only
# API without an iOS app to find out: `import AppKit` there, or any
# macOS-only modifier, fails here. Needs Xcode's iOS platform
# (`xcodebuild -downloadPlatform iOS`).
IOS_CHECK_DIR := build/ios-check

# Every xcodebuild of the packages passes these. Pinned, as with swift build.
# And macros enabled: the Point-Free libraries are built on Swift macros, and
# xcodebuild refuses a package's macros until they are trusted — in Xcode by
# clicking "Trust & Enable", which a script or a fresh machine cannot do.
# `swift build` does not ask. Trusting them wholesale is reasonable here
# because every dependency is pinned, so new macro code only arrives through
# a reviewed `make update-pins`.
XCODE_FLAGS := -onlyUsePackageVersionsFromResolvedFile -skipMacroValidation

check-shared-ios:
	@cd $(SHARED) && xcodebuild -scheme StarterKit-Package -destination 'generic/platform=iOS' \
	  -derivedDataPath $(CURDIR)/$(IOS_CHECK_DIR) $(XCODE_FLAGS) -quiet build
	@echo "✓ shared package compiles for iOS"

# The tests live with the shared code; the Mac package is views and the
# entry point.
test: deps
	swift test --package-path $(SHARED) $(SWIFT_PINNED)
	@echo "✓ tests pass"

print-version:
	@echo "VERSION=$(VERSION)"
	@echo "  git tag at HEAD: $(if $(GIT_TAG_VERSION),$(GIT_TAG_VERSION),(none))"
	@echo "  VERSION file:    $(if $(FILE_VERSION),$(FILE_VERSION),(missing))"

# ---------------------------------------------------------------------------
# Run / install / register
# ---------------------------------------------------------------------------

# Every launch quits any running copy first — `open` would otherwise just
# bring the old one forward, and `open -n` leaves old copies whose windows
# screenshots then come from (docs/gotchas.md).
define quit-running
	@if pgrep -f "$(APP)/Contents/MacOS/" >/dev/null; then \
	  osascript -e 'tell application id "$(BUNDLE_ID)" to quit' >/dev/null 2>&1 || true; \
	  for i in $$(seq 50); do pgrep -f "$(APP)/Contents/MacOS/" >/dev/null || break; sleep 0.2; done; \
	  pkill -f "$(APP)/Contents/MacOS/" 2>/dev/null || true; \
	fi
endef

# `make run` is what a person expects: the app opens in front. An agent
# working while someone else uses the machine wants `run-background`, whose
# `open -g` launches behind whatever has focus. They are separate targets
# because a plain `make run` that appears to do nothing is baffling.
run: build
	$(quit-running)
	open -n "$(APP)"
	@echo "✓ launched"

run-background: build
	$(quit-running)
	open -g -n "$(APP)"
	@echo "✓ launched in the background"

# The app on a disposable database and its own user defaults, accepting
# commands from scripts/send-commands.sh. See docs/commands.md. Always in the
# background: this is the target for scripted checks.
CONTAINER   := $(HOME)/Library/Containers/$(BUNDLE_ID)/Data
SCRATCH_DIR := $(CONTAINER)/tmp/Starter-scratch

run-scratch: build
	$(quit-running)
	open -g -n "$(APP)" --args --scratch-database
	@echo "✓ launched on scratch data, in the background"

scratch-reset:
	$(quit-running)
	rm -rf "$(SCRATCH_DIR)"
	@# `defaults delete`, not `rm`: cfprefsd caches the file, and a plist
	@# removed underneath it comes back with the old values (docs/gotchas.md).
	-defaults delete "$(CONTAINER)/Library/Preferences/$(BUNDLE_ID).scratch" 2>/dev/null
	@echo "✓ removed the scratch database and settings (takes effect at the next run-scratch)"

screenshot:
	@mkdir -p build
	@ID=$$(swift scripts/window-id.swift "$(DISPLAY_NAME)") && \
	  screencapture -o -x -l $$ID build/window.png && echo "✓ build/window.png (window $$ID)"

install: build
	@if [ ! -d "$(APP)" ]; then echo "✗ $(APP) missing — build failed?"; exit 1; fi
	rm -rf /Applications/$(APP_NAME).app
	cp -R "$(APP)" /Applications/
	@echo "✓ copied to /Applications/$(APP_NAME).app"
	$(LSREGISTER) -f /Applications/$(APP_NAME).app
	@echo "✓ registered /Applications/$(APP_NAME).app with LaunchServices"

uninstall:
	@if [ -d /Applications/$(APP_NAME).app ]; then \
	  rm -rf /Applications/$(APP_NAME).app 2>/dev/null || sudo rm -rf /Applications/$(APP_NAME).app; \
	  echo "✓ removed /Applications/$(APP_NAME).app"; \
	else \
	  echo "  (no /Applications/$(APP_NAME).app to remove)"; \
	fi

register: build
	$(LSREGISTER) -f "$(APP)"
	@echo "✓ registered $(APP) with LaunchServices"

# ---------------------------------------------------------------------------
# Lint and format
#
# `swift format` comes from the Xcode toolchain, so its version moves with the
# toolchain rather than with a pin of its own. Configuration is .swift-format
# at the repo root.
#
# The ast-grep rules are the other half and catch something different:
# mistakes that fail *silently*, or keep coming back. Each rule sits beside a
# document saying why it exists, and has a test. See rules/README.md.
# ---------------------------------------------------------------------------

# NOT scripts/: swift-format mangles a `#!/usr/bin/env swift` script, folding
# the shebang and the comment block beneath it into one ever-growing line.
# See docs/gotchas.md.
SWIFT_FORMAT_PATHS := Packages

fmt:
	@swift format --configuration .swift-format --recursive --in-place $(SWIFT_FORMAT_PATHS)
	@echo "✓ formatted"

fmt-check:
	@swift format lint --configuration .swift-format --recursive --strict $(SWIFT_FORMAT_PATHS) \
	  && echo "✓ formatting clean"

# The tests first: a rule whose pattern has quietly stopped matching would
# otherwise pass every scan.
rules:
	@command -v ast-grep >/dev/null 2>&1 || { \
	  echo "  ✗ ast-grep not installed (brew install ast-grep)"; exit 1; }
	@ast-grep test --skip-snapshot-tests
	ast-grep scan Packages
	@echo "✓ rules clean"

lint: fmt-check rules
	@echo "✓ lint clean"

# ---------------------------------------------------------------------------
# Clean
# ---------------------------------------------------------------------------

clean:
	rm -rf build .build $(SHARED)/.build $(PACKAGE)/.build $(DIST_DIR)
	@echo "✓ removed build/, .build/, and $(DIST_DIR)/"

# ---------------------------------------------------------------------------
# Release pipeline: sign → zip-notary → notarize → staple → zip-release →
# checksum → verify-release. The two-zip dance is on purpose: Apple's notary
# service operates on a zip; stapling writes the ticket back into the .app;
# the zip we distribute must be a fresh one taken AFTER stapling.
#
#   git tag v0.1.0 && make dist
# ---------------------------------------------------------------------------

dist: check-version clean release sign zip-notary notarize staple zip-release checksum verify-release
	@echo "✓ release artifact ready: $(RELEASE_ZIP)"
	@echo "  next: make github-release   (or upload $(RELEASE_ZIP) manually)"

check-version:
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
	@echo "→ release version $(VERSION)"

notary-setup:
	@command -v xcrun >/dev/null 2>&1 || { echo "✗ xcrun not found — install Xcode or the Command Line Tools"; exit 1; }
	@if [ ! -t 0 ]; then \
	  echo "✗ make notary-setup is interactive — run it in a real terminal,"; \
	  echo "  not from an editor / agent shell (it prompts for your password)."; \
	  echo "    1. Create an App-Specific Password at https://appleid.apple.com → Sign-In and Security."; \
	  echo "    2. Run: make notary-setup APPLE_ID=you@example.com TEAM_ID=XXXXXXXXXX"; \
	  echo "    3. Paste the App-Specific Password when prompted."; \
	  exit 1; \
	fi
	@if [ -z "$(TEAM_ID)" ]; then echo "✗ TEAM_ID required: make notary-setup TEAM_ID=XXXXXXXXXX APPLE_ID=you@example.com"; exit 1; fi
	@echo "→ storing notary credentials in keychain profile '$(NOTARY_PROFILE)' (team $(TEAM_ID))"
	xcrun notarytool store-credentials "$(NOTARY_PROFILE)" \
	  --team-id "$(TEAM_ID)" \
	  $(if $(APPLE_ID),--apple-id "$(APPLE_ID)",)
	@echo "✓ stored. 'make dist' / 'make notarize' will use profile '$(NOTARY_PROFILE)'."

sign: release
	@if [ -z "$(CERT_NAME)" ]; then echo "✗ CERT_NAME required (set TEAM_ID, or pass CERT_NAME=...)"; exit 1; fi
	@echo "→ signing $(APP) as $(CERT_NAME)"
	codesign --force --options runtime --timestamp \
	  --entitlements "$(ENTITLEMENTS)" \
	  --sign "$(CERT_NAME)" "$(APP)"
	codesign --verify --strict --verbose=2 "$(APP)"

zip-notary: sign
	@mkdir -p "$(DIST_DIR)"
	rm -f "$(NOTARY_ZIP)"
	ditto -c -k --keepParent "$(APP)" "$(NOTARY_ZIP)"
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
	xcrun stapler staple "$(APP)"
	xcrun stapler validate "$(APP)"

zip-release: staple
	rm -f "$(RELEASE_ZIP)"
	ditto -c -k --keepParent "$(APP)" "$(RELEASE_ZIP)"
	@echo "✓ wrote $(RELEASE_ZIP)"

checksum: zip-release
	cd "$(DIST_DIR)" && shasum -a 256 "$$(basename $(RELEASE_ZIP))" > "$$(basename $(RELEASE_ZIP)).sha256"
	@echo "✓ wrote $(RELEASE_ZIP).sha256"

verify-release: zip-release
	spctl --assess --type execute --verbose "$(APP)"
	codesign --verify --deep --strict --verbose=2 "$(APP)"

github-release:
	@if ! command -v gh >/dev/null 2>&1; then echo "✗ gh CLI not installed (brew install gh)"; exit 1; fi
	@if [ -z "$(VERSION)" ]; then echo "✗ VERSION required (tag or override)"; exit 1; fi
	@if [ ! -f "$(RELEASE_ZIP)" ]; then echo "✗ $(RELEASE_ZIP) not found — run make dist first"; exit 1; fi
	@if [ ! -f "$(RELEASE_ZIP).sha256" ]; then echo "✗ $(RELEASE_ZIP).sha256 not found — run make dist first"; exit 1; fi
	gh release create "v$(VERSION)" \
	  "$(RELEASE_ZIP)" \
	  "$(RELEASE_ZIP).sha256" \
	  --title "$(APP_NAME) $(VERSION)" \
	  $(if $(NOTES_FILE),--notes-file "$(NOTES_FILE)",--generate-notes)
	@echo "✓ published v$(VERSION)"

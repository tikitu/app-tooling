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
# The toolchain the pinned packages need (Xcode 27); `make deps` checks it.
MIN_SWIFT    := 6.4

APP_NAME      := Starter
DISPLAY_NAME  := Starter App
ENTITLEMENTS  := StarterMac/StarterMac.entitlements

# Dev signing identity. Ad-hoc is enough until the app needs an entitlement
# that a provisioning profile has to grant, such as iCloud.
DEV_IDENTITY  ?= -

# `make dist`: signed with the Developer ID, notarized, stapled, zipped and
# checked; `make github-release` publishes it (app-tooling: mac-dist).
# docs/app-tooling/mac-dist/. Fill in TEAM_ID and DEVELOPER_NAME (as on the
# certificate) before the first `make dist`, or pass CERT_NAME=... in full.
# The notary profile is stored once per Mac with `make notary-setup`.
TEAM_ID               ?=
DEVELOPER_NAME        ?=
NOTARY_PROFILE        ?= starter-notary
MAC_DIST_APP          := $(APP)
MAC_DIST_NAME         := $(APP_NAME)
MAC_DIST_ENTITLEMENTS := $(ENTITLEMENTS)
MAC_DIST_BUILD        := release
include mk/mac-dist.mk

# app-tooling-update and app-tooling-check, for the conventions imported from
# app-tooling (peru.yaml; docs/app-tooling/pattern-imports/README.md).
include mk/app-tooling.mk

# Two dependency and Xcode warnings removed at their cause; refuses to run
# while the App Intents skip and App Intents code are both in the project
# (app-tooling: build-warnings). docs/app-tooling/build-warnings/.
include mk/build-warnings.mk

# `make install`: the app into /Applications with a rising build number,
# quitting and restarting a running copy; `make mac-stale-registrations`
# (app-tooling: mac-install). docs/app-tooling/mac-install/.
MAC_INSTALL_APP       := $(APP)
MAC_INSTALL_BUNDLE_ID := $(BUNDLE_ID)
MAC_INSTALL_BUILD     := build
include mk/mac-install.mk

.PHONY: all deps outdated update-pins check-pins check-shared-ios build build-scratch check test release run run-background run-scratch scratch-reset \
        screenshot clean uninstall register help \
        icon \
        fmt fmt-check lint rules

all: build

help:
	@echo "Build:"
	@echo "  make / build      Build $(CONFIG) into ./$(APP)  (default)"
	@echo "  check             Compile only — the Mac app, and the shared package for iOS; CI/agent gate"
	@echo "  test              Run the SwiftPM test suite"
	@echo "  release           Build release into ./$(APP)"
	@echo "  run               Build and launch $(APP_NAME), in front, as if opened from Finder"
	@echo "  run-background    The same, but launched behind whatever has focus"
	@echo "  build-scratch     Build $(APP_NAME) Scratch, the scratch build, into ./$(SCRATCH_APP)"
	@echo "  run-scratch       Build and launch $(APP_NAME) Scratch in the background, accepting commands (agents)"
	@echo "  scratch-reset     Delete the scratch build's database and settings"
	@echo "  screenshot        Capture $(APP_NAME) Scratch's window to build/window.png, without focus"
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
	@echo "  install           Build, copy $(APP_NAME).app to /Applications/ and register it,"
	@echo "                    restarting a running copy (docs/app-tooling/mac-install/)"
	@echo "  mac-stale-registrations  List other registrations of the bundle id (UNREGISTER=1 removes them)"
	@echo "  uninstall         Remove /Applications/$(APP_NAME).app"
	@echo "  register          Refresh LaunchServices for ./$(APP)"
	@echo ""
	@echo "Release pipeline (require an exact 'vX.Y.Z' git tag + signing identity):"
	@echo "  notary-setup      One-time: store notary creds in keychain ($(NOTARY_PROFILE))"
	@echo "  dist              Build → sign → notarize → staple → zip → checksum"
	@echo "  github-release    Upload \$$(RELEASE_ZIP) + .sha256 to a GitHub release"
	@echo "                    NOTES_FILE=<path> for hand-written notes; not in dist/, which dist cleans"
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
	SW_VERSION=$$(echo "$$SW_LINE" | sed -nE 's/.*Swift version ([0-9]+\.[0-9]+).*/\1/p'); \
	if [ -z "$$SW_VERSION" ]; then \
	  echo "  ✗ could not read the Swift version from: $$SW_LINE"; exit 1; \
	fi; \
	if [ "$$(printf '%s\n%s\n' "$(MIN_SWIFT)" "$$SW_VERSION" | sort -t. -k1,1n -k2,2n | head -1)" != "$(MIN_SWIFT)" ]; then \
	  echo "  ✗ Swift $$SW_VERSION — $(APP_NAME) requires Swift $(MIN_SWIFT) or newer (Xcode 27)."; \
	  echo "    The pinned Point-Free packages name swift-issue-reporting only from Swift $(MIN_SWIFT)"; \
	  echo "    on; an older toolchain reads their older manifests, which name xctest-dynamic-overlay."; \
	  exit 1; \
	fi; \
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

# Every build gets the time it was made as its build number, so each
# `make install` rises above the last (mac-install).
build: deps $(APP_ICON)
	SIGN_IDENTITY="$(DEV_IDENTITY)" VERSION="$(VERSION)" BUILD_NUMBER="$(MAC_INSTALL_BUILD_NUMBER)" ./build.sh $(CONFIG)

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

# ---------------------------------------------------------------------------
# Run / install / register
# ---------------------------------------------------------------------------

# Every launch quits any running copy first — `open` would otherwise just
# bring the old one forward, and `open -n` leaves old copies whose windows
# screenshots then come from (docs/gotchas.md). `$(quit-running)` and
# `$(scratch-pids)` come from mk/scratch-data.mk (below): only this
# checkout's build is touched, by absolute path and pid, since the bundle id,
# or a relative path, would also reach the app built from another checkout.

# `make run` is what a person expects: the real app opens in front, on the
# real data. `run-background` launches it behind whatever has focus. Agents
# use neither: they run the scratch build (`run-scratch`, below).
run: build
	$(quit-running)
	open -n "$(APP)"
	@echo "✓ launched"

run-background: build
	$(quit-running)
	open -g -n "$(APP)"
	@echo "✓ launched in the background"

# The scratch build (app-tooling: scratch-data, scratch-look): "Starter
# Scratch", bundle id org.example.starter.scratch, an icon with the caution
# band, ScratchBuild = YES. It is another app, so its database and settings
# are in a container of its own, and it is the only build that accepts
# commands from scripts/send-commands.sh (docs/commands.md). `run-scratch`
# launches it in the background: the target for agents and scripted checks.
# `scratch-reset` throws its data away. docs/app-tooling/scratch-data/.
SCRATCH_APP       := build/$(APP_NAME) Scratch.app
SCRATCH_BUILD     := build-scratch
SCRATCH_CONTAINER := $(HOME)/Library/Containers/$(BUNDLE_ID).scratch/Data
SCRATCH_DIR       := $(SCRATCH_CONTAINER)/Library/Application Support/Starter
SCRATCH_DEFAULTS  := $(SCRATCH_CONTAINER)/Library/Preferences/$(BUNDLE_ID).scratch
# The command inbox (app-tooling: command-inbox), outside the container: a
# terminal that touches the container raises a privacy prompt on screen. The
# entitlements open it to the app, which cannot create it, so it is made here.
COMMANDS_DIR      := $(HOME)/Library/Caches/Starter-scratch/Commands
SCRATCH_ARGS      := --commands "$(COMMANDS_DIR)"

build-scratch: build
	scripts/make-scratch-app.sh "$(APP)" "$(SCRATCH_APP)"
	mkdir -p "$(COMMANDS_DIR)"

include mk/scratch-data.mk

# The scratch build from this checkout only, by absolute path and then pid:
# by name, the window of a copy built in another checkout, or of the real
# app, could be photographed instead.
screenshot:
	@mkdir -p build
	@pids=$$($(scratch-pids)); set -- $$pids; \
	  [ $$# -eq 1 ] || { echo "✗ $$# copies of $(SCRATCH_APP) running; want exactly 1 (make run-scratch)"; exit 1; }; \
	  ID=$$(swift scripts/window-id.swift --pid $$1) && \
	  screencapture -o -x -l $$ID build/window.png && echo "✓ build/window.png (window $$ID, pid $$1)"

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
# See docs/gotchas.md. Nor the Swift files imported from app-tooling
# (peru.yaml), which are never reformatted here: `make app-tooling-check`
# would fail, and they cannot carry an ignore comment of this project's.
SWIFT_FORMAT_IMPORTED := ScratchBuild.swift ScratchDataBanner.swift ScratchMenuBarBadge.swift
_swift_format_files = find Packages -name .build -prune -o -name '*.swift' \
  $(foreach f,$(SWIFT_FORMAT_IMPORTED),-not -name '$(f)') -print0

fmt:
	@$(_swift_format_files) | xargs -0 swift format --configuration .swift-format --in-place
	@echo "✓ formatted"

fmt-check:
	@$(_swift_format_files) | xargs -0 swift format lint --configuration .swift-format --strict \
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

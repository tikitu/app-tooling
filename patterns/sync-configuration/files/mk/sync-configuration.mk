# sync-configuration.mk — refuse a TestFlight upload that is not Production.
#
# Imported by peru from the app-tooling pattern `sync-configuration`
# (https://github.com/tikitu/app-tooling). Never edit it here: `peru sync`
# refuses to overwrite a changed copy, and the change belongs in app-tooling.
# docs/app-tooling/sync-configuration/ says how to use it.
#
# The project's Makefile sets these, then `include mk/sync-configuration.mk`:
#
#   SYNC_PREFIX     the Info.plist keys' prefix, as in <prefix>SyncEnabled (required)
#   SYNC_IOS_SPEC   the XcodeGen spec of the iOS app  (default: apps/ios/project.yml)
#
# and makes the upload depend on the check:
#
#   testflight-upload: testflight-check-environment

# Leave the including Makefile's default goal alone, wherever the include is.
_sync_configuration_default_goal := $(.DEFAULT_GOAL)

SYNC_IOS_SPEC ?= apps/ios/project.yml

.PHONY: testflight-check-environment

# A TestFlight build is signed for distribution, which always means CloudKit
# Production. An app that declares Development in its Info.plist would then
# check its sync state against the wrong environment. So both the
# entitlement and the declaration must say Production before an upload.
testflight-check-environment:
	@[ -n "$(SYNC_PREFIX)" ] || { echo "✗ SYNC_PREFIX is not set"; exit 1; }
	@grep -q '^ *com\.apple\.developer\.icloud-container-environment: Production$$' "$(SYNC_IOS_SPEC)" || { \
	  echo "✗ $(SYNC_IOS_SPEC) does not set icloud-container-environment to Production."; \
	  echo "  A TestFlight build is always Production: docs/app-tooling/sync-configuration/README.md."; \
	  exit 1; }
	@grep -q '^ *$(SYNC_PREFIX)CloudKitEnvironment: Production$$' "$(SYNC_IOS_SPEC)" || { \
	  echo "✗ $(SYNC_IOS_SPEC) declares $(SYNC_PREFIX)CloudKitEnvironment other than Production."; \
	  echo "  A TestFlight build is always Production: docs/app-tooling/sync-configuration/README.md."; \
	  exit 1; }
	@echo "✓ $(SYNC_IOS_SPEC) is Production"

.DEFAULT_GOAL := $(_sync_configuration_default_goal)

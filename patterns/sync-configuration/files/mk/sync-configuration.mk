# sync-configuration.mk — check that a built app's signature and Info.plist
# agree on sync, and refuse a TestFlight upload that is not Production.
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
# and, for a scratch build that is a separate app (each optional; see
# scripts/check-sync-configuration.sh):
#
#   SYNC_BUNDLE_ID, SYNC_APP_GROUPS                  the sync build's
#   SYNC_SCRATCH_BUNDLE_ID, SYNC_SCRATCH_APP_GROUPS  the scratch build's
#   SYNC_APP_GROUP_KEY                               the Info.plist key naming the group
#
# It provides SYNC_CHECK, the check with those parameters, to run on a
# built app (`$(SYNC_CHECK) --expect scratch build/MyApp.app`), and
#
#   make sync-check SYNC_CHECK_APPS='<App.app>...' [SYNC_EXPECT=scratch|sync|production]
#                            SYNC_CHECK_APPS is shell words: from a script,
#                            SYNC_CHECK_APPS="$(printf '%q ' "$app"...)"
#   make sync-check-test     the check's own tests, on fake bundles
#
# With the testflight pattern, the upload depends on the spec's check, and
# the archive is checked as well:
#
#   testflight-upload: testflight-check-environment
#   TESTFLIGHT_ARCHIVE_CHECK = $(SYNC_CHECK) --expect production

# Leave the including Makefile's default goal alone, wherever the include is.
_sync_configuration_default_goal := $(.DEFAULT_GOAL)

SYNC_IOS_SPEC ?= apps/ios/project.yml

.PHONY: testflight-check-environment sync-check sync-check-test

# The parameters go as options, and only those that are set: an empty one
# means "not checked", never "must be empty".
SYNC_CHECK = scripts/check-sync-configuration.sh --prefix '$(SYNC_PREFIX)' \
	$(if $(SYNC_BUNDLE_ID),--bundle-id '$(SYNC_BUNDLE_ID)') \
	$(if $(SYNC_APP_GROUPS),--app-groups '$(SYNC_APP_GROUPS)') \
	$(if $(SYNC_SCRATCH_BUNDLE_ID),--scratch-bundle-id '$(SYNC_SCRATCH_BUNDLE_ID)') \
	$(if $(SYNC_SCRATCH_APP_GROUPS),--scratch-app-groups '$(SYNC_SCRATCH_APP_GROUPS)') \
	$(if $(SYNC_APP_GROUP_KEY),--app-group-key '$(SYNC_APP_GROUP_KEY)')

# What each built app is actually signed with, against its Info.plist.
sync-check:
	@[ -n "$(SYNC_PREFIX)" ] || { echo "✗ SYNC_PREFIX is not set"; exit 1; }
	@[ -n "$(SYNC_CHECK_APPS)" ] || { echo "✗ name the built apps: make sync-check SYNC_CHECK_APPS='build/MyApp.app'"; exit 1; }
	@$(SYNC_CHECK) $(if $(SYNC_EXPECT),--expect '$(SYNC_EXPECT)') $(SYNC_CHECK_APPS)

sync-check-test:
	@scripts/tests/check-sync-configuration-test.sh

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

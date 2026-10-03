# testflight.mk — make targets that send the iOS app to App Store Connect.
#
# Imported by peru from the app-tooling pattern `testflight`
# (https://github.com/tikitu/app-tooling). Never edit it here: `peru sync`
# refuses to overwrite a changed copy, and the change belongs in app-tooling.
# docs/app-tooling/testflight/ says how to use it.
#
# The project's Makefile sets these, then `include mk/testflight.mk`:
#
#   TESTFLIGHT_PROJECT        the .xcodeproj                      (required)
#   TESTFLIGHT_SCHEME         its app scheme                      (required)
#   TESTFLIGHT_TEAM           the team id                         (required)
#   TESTFLIGHT_PREPARE        make targets to run first, such as the one
#                             that generates the Xcode project
#   TESTFLIGHT_XCODE_FLAGS    extra xcodebuild flags, such as the
#                             project's pinned-package flags
#   TESTFLIGHT_BRANCH         the branch builds go up from (default: main)
#   TESTFLIGHT_INTERNAL_ONLY  YES for internal testers only (default: NO)
#
# TESTFLIGHT_PREPARE must be set before the include: make reads
# prerequisites as it reads the rule.

# Leave the including Makefile's default goal alone, wherever the include is.
_testflight_default_goal := $(.DEFAULT_GOAL)

TESTFLIGHT_BRANCH ?= main
TESTFLIGHT_INTERNAL_ONLY ?= NO
export TESTFLIGHT_PROJECT TESTFLIGHT_SCHEME TESTFLIGHT_TEAM TESTFLIGHT_XCODE_FLAGS \
	TESTFLIGHT_BRANCH TESTFLIGHT_INTERNAL_ONLY

.PHONY: testflight-validate testflight-upload

# Archive a clean commit and have App Store Connect check it. Uploads
# nothing: run it before the first upload, and whenever signing or the
# project's settings change.
testflight-validate: $(TESTFLIGHT_PREPARE)
	@scripts/testflight.sh validate

# Archive a clean commit and upload it to TestFlight.
testflight-upload: $(TESTFLIGHT_PREPARE)
	@scripts/testflight.sh upload

.DEFAULT_GOAL := $(_testflight_default_goal)

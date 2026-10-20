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
#   TESTFLIGHT_ONLY_DEVICES   devices that hold real data and get builds only
#                             through TestFlight, comma-separated (default:
#                             none)
#   TESTFLIGHT_INSTALL_DEVICE the device a development install goes to
#                             (default: $(IOS_DEVICE))
#
# TESTFLIGHT_PREPARE must be set before the include: make reads
# prerequisites as it reads the rule. For the same reason, the include comes
# before the project's install target, which lists $(TESTFLIGHT_DEVICE_GUARD)
# first among its prerequisites.

# Leave the including Makefile's default goal alone, wherever the include is.
_testflight_default_goal := $(.DEFAULT_GOAL)

TESTFLIGHT_BRANCH ?= main
TESTFLIGHT_INTERNAL_ONLY ?= NO
TESTFLIGHT_ONLY_DEVICES ?=
TESTFLIGHT_INSTALL_DEVICE ?= $(IOS_DEVICE)
export TESTFLIGHT_PROJECT TESTFLIGHT_SCHEME TESTFLIGHT_TEAM TESTFLIGHT_XCODE_FLAGS \
	TESTFLIGHT_BRANCH TESTFLIGHT_INTERNAL_ONLY

.PHONY: testflight-validate testflight-upload testflight-device-guard

# Archive a clean commit and have App Store Connect check it. Uploads
# nothing: run it before the first upload, and whenever signing or the
# project's settings change.
testflight-validate: $(TESTFLIGHT_PREPARE)
	@scripts/testflight.sh validate

# Archive a clean commit and upload it to TestFlight.
testflight-upload: $(TESTFLIGHT_PREPARE)
	@scripts/testflight.sh upload

# Refuse a development install on a device in TESTFLIGHT_ONLY_DEVICES. A
# development build is whatever the tree holds; on a device with real data a
# new migration or enum case runs forward on it, syncs, and can leave the
# TestFlight build and other devices unable to read it, which reinstalling
# TestFlight does not undo. The project's install target lists
# $(TESTFLIGHT_DEVICE_GUARD) first, so a refusal comes before the build.
TESTFLIGHT_DEVICE_GUARD := testflight-device-guard
testflight-device-guard:
	@# The list goes through a variable: a literal `for` list is split on
	@# spaces whatever IFS says, and device names have spaces in them.
	@list='$(TESTFLIGHT_ONLY_DEVICES)'; IFS=','; for d in $$list; do \
	  d="$${d# }"; d="$${d% }"; \
	  if [ "$$d" = '$(TESTFLIGHT_INSTALL_DEVICE)' ] && [ "$(INSTALL_ON_TESTFLIGHT_DEVICE)" != yes ]; then \
	    echo "✗ '$(TESTFLIGHT_INSTALL_DEVICE)' holds real data and gets builds only through TestFlight"; \
	    echo "  (TESTFLIGHT_ONLY_DEVICES). Use the simulator, another device, or"; \
	    echo "  make testflight-upload. Only if the owner asks: INSTALL_ON_TESTFLIGHT_DEVICE=yes."; \
	    exit 1; \
	  fi; \
	done

.DEFAULT_GOAL := $(_testflight_default_goal)

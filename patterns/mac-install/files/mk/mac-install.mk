# mac-install.mk — install the Mac app into /Applications with a rising
# build number, and find the stale registrations that share its bundle id.
#
# Imported by peru from the app-tooling pattern `mac-install`
# (https://github.com/tikitu/app-tooling). Never edit it here: `peru sync`
# refuses to overwrite a changed copy, and the change belongs in app-tooling.
# docs/app-tooling/mac-install/ says how to use it.
#
# The project's Makefile sets these, then `include mk/mac-install.mk`:
#
#   MAC_INSTALL_APP        the built .app to install                 (required)
#   MAC_INSTALL_BUNDLE_ID  its bundle id                             (required)
#   MAC_INSTALL_BUILD      the target that builds $(MAC_INSTALL_APP),
#                          with $(MAC_INSTALL_BUILD_NUMBER) as its
#                          CFBundleVersion                           (required)
#   MAC_INSTALL_DIR        where to install it   (default: /Applications)
#
# MAC_INSTALL_BUILD must be set before the include: make reads prerequisites
# as it reads the rule.
#
# MAC_INSTALL_BUILD_NUMBER is defined here, for the build to use: the date
# and time to the second, read once per `make`, so it rises with every
# install. An Xcode build passes CURRENT_PROJECT_VERSION=$(MAC_INSTALL_BUILD_NUMBER);
# a build.sh that writes the Info.plist itself takes it from the environment.

# Leave the including Makefile's default goal alone, wherever the include is.
_mac_install_default_goal := $(.DEFAULT_GOAL)

MAC_INSTALL_DIR          ?= /Applications
MAC_INSTALL_BUILD_NUMBER := $(shell date +%Y%m%d%H%M%S)

.PHONY: install mac-stale-registrations

# Builds, quits the installed copy if it is running, replaces it, registers
# it, and starts it again if it was running. Warns when the build number
# has not risen. For a person: this replaces the real app.
install: $(MAC_INSTALL_BUILD)
	@[ -n "$(MAC_INSTALL_APP)" ] || { echo "✗ set MAC_INSTALL_APP before including mk/mac-install.mk"; exit 1; }
	@scripts/mac-install.sh --dir "$(MAC_INSTALL_DIR)" "$(MAC_INSTALL_APP)"

# Lists LaunchServices registrations of the bundle id other than the
# installed copy: builds in DerivedData, build/, worktrees and /tmp, which
# can lend the Dock an old icon. UNREGISTER=1 unregisters them (nothing on
# disk is deleted).
mac-stale-registrations:
	@[ -n "$(MAC_INSTALL_BUNDLE_ID)" ] || { echo "✗ set MAC_INSTALL_BUNDLE_ID before including mk/mac-install.mk"; exit 1; }
	@scripts/mac-stale-registrations.sh "$(MAC_INSTALL_BUNDLE_ID)" \
	  "$(MAC_INSTALL_DIR)/$(notdir $(MAC_INSTALL_APP))" $(if $(filter 1,$(UNREGISTER)),--unregister)

.DEFAULT_GOAL := $(_mac_install_default_goal)

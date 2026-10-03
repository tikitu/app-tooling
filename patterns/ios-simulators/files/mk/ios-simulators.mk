# ios-simulators.mk — simulators the project owns, by names no Xcode release
# changes, and the pieces its own simulator targets build on.
#
# Imported by peru from the app-tooling pattern `ios-simulators`
# (https://github.com/tikitu/app-tooling). Never edit it here: `peru sync`
# refuses to overwrite a changed copy, and the change belongs in app-tooling.
# docs/app-tooling/ios-simulators/ says how to use it.
#
# The project's Makefile sets these, then `include mk/ios-simulators.mk`:
#
#   IOS_SIM_NAME       the project's simulator on the newest iOS     (required)
#                      e.g. MyApp
#   IOS_SIM_TYPE       device type, from `xcrun simctl list devicetypes`
#                      (default: an iPhone the current runtimes all run)
#   IOS_PHONE_RUNTIME  runtime closest to the iOS on the phone; empty for none
#                      e.g. com.apple.CoreSimulator.SimRuntime.iOS-26-5
#   IOS_SIM            which simulator a target runs on (default IOS_SIM_NAME)
#
# It gives:
#
#   make ios-sims        (re)create $(IOS_SIM_NAME) on the newest iOS and
#                        "$(IOS_SIM_NAME) Phone OS" on IOS_PHONE_RUNTIME
#   IOS_SIM_BUILD_FLAGS  for `xcodebuild build`: any simulator, signed to run
#   IOS_SIM_UDID         a shell snippet setting $$UDID to IOS_SIM's, or
#                        failing with "run make ios-sims"
#   IOS_SIMS             both names, for a target that runs on each

# Leave the including Makefile's default goal alone, wherever the include is.
_ios_simulators_default_goal := $(.DEFAULT_GOAL)

IOS_SIM_TYPE      ?= com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro
IOS_PHONE_RUNTIME ?=
IOS_SIM           ?= $(IOS_SIM_NAME)
IOS_SIM_PHONE     := $(IOS_SIM_NAME) Phone OS
IOS_SIMS          := $(IOS_SIM_NAME)$(if $(IOS_PHONE_RUNTIME),;$(IOS_SIM_PHONE))

# A build for any simulator needs none to exist. Signed to run locally (ad
# hoc): an unsigned app installs, then the simulator refuses to open it
# ("Application failed preflight checks").
IOS_SIM_BUILD_FLAGS := -destination 'generic/platform=iOS Simulator' CODE_SIGN_IDENTITY=-

# By UDID, looked up by name: a destination by name alone means "on the
# newest iOS", which never finds the Phone OS simulator.
IOS_SIM_UDID = UDID=$$(xcrun simctl list devices available \
	| sed -nE 's/^    $(IOS_SIM) \(([0-9A-F-]+)\).*/\1/p' | head -1); \
	[ -n "$$UDID" ] || { echo "✗ no simulator named $(IOS_SIM): run make ios-sims" >&2; exit 1; }

.PHONY: ios-sims

# Deletes and recreates, so it is safe to rerun, and is the answer after an
# Xcode update: the newest runtime is whatever is installed now.
ios-sims:
	@[ -n "$(IOS_SIM_NAME)" ] || { echo "✗ set IOS_SIM_NAME before including ios-simulators.mk" >&2; exit 1; }
	@while xcrun simctl delete "$(IOS_SIM_NAME)" 2>/dev/null; do :; done
	@while xcrun simctl delete "$(IOS_SIM_PHONE)" 2>/dev/null; do :; done
	xcrun simctl create "$(IOS_SIM_NAME)" $(IOS_SIM_TYPE)
	$(if $(IOS_PHONE_RUNTIME),xcrun simctl create "$(IOS_SIM_PHONE)" $(IOS_SIM_TYPE) $(IOS_PHONE_RUNTIME))
	@xcrun simctl list devices available | grep -F "$(IOS_SIM_NAME)"

.DEFAULT_GOAL := $(_ios_simulators_default_goal)

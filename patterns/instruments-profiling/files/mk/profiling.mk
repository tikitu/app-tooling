# profiling.mk — make targets for headless Instruments profiling.
#
# Imported by peru from the app-tooling pattern `instruments-profiling`
# (https://github.com/tikitu/app-tooling). Never edit it here: `peru sync`
# refuses to overwrite a changed copy, and the change belongs in app-tooling.
# docs/app-tooling/instruments-profiling/ says how to use it.
#
# From the project's Makefile, after the target that builds the app:
#
#   PROFILE_BUILD := build      # a target that builds a build which cannot sync
#   include mk/profiling.mk
#
# The app, its data and its scenarios are in the project's profiling.conf.zsh.

PROFILE_BUILD ?=
TEMPLATE ?= Animation Hitches
SCENARIO ?= idle

.PHONY: profile profile-tools

profile-tools:
	@command -v xcrun >/dev/null 2>&1 || { echo "✗ Xcode command line tools missing"; exit 1; }
	@xcrun --find xctrace >/dev/null 2>&1 || { echo "✗ xctrace missing: install Xcode"; exit 1; }
	@command -v sqlite3 >/dev/null 2>&1 || { echo "✗ sqlite3 missing"; exit 1; }
	@[ -f profiling.conf.zsh ] || { echo "✗ no profiling.conf.zsh: docs/app-tooling/instruments-profiling/apply.md"; exit 1; }

# Record TEMPLATE while the app runs SCENARIO, on a copy of the app and of its
# data; read the result with scripts/trace-query.py.
profile: profile-tools $(PROFILE_BUILD)
	scripts/profile-mac.sh "$(TEMPLATE)" $(SCENARIO)

# scratch-data.mk — run the Mac app's scratch build, and throw its data away.
#
# Imported by peru from the app-tooling pattern `scratch-data`
# (https://github.com/tikitu/app-tooling). Never edit it here: `peru sync`
# refuses to overwrite a changed copy, and the change belongs in app-tooling.
# docs/app-tooling/scratch-data/ says how to use it.
#
# The project's Makefile sets these, then `include mk/scratch-data.mk`:
#
#   SCRATCH_APP       the built scratch app, "<App> Scratch.app"  (required)
#   SCRATCH_BUILD     the target that builds $(SCRATCH_APP)       (required)
#   SCRATCH_DIR       the scratch build's data directory; its
#                     path must name the scratch bundle id
#                     (a component ending ".scratch")             (required)
#   SCRATCH_DEFAULTS  the scratch build's user defaults, as
#                     `defaults delete` takes them                (optional)
#   SCRATCH_ARGS      launch arguments for the scratch build
#                     (`--commands <dir>`, say)                   (optional)
#   APP               the real app, for `quit-running`            (optional)
#
# SCRATCH_BUILD must be set before the include: make reads prerequisites as
# it reads the rule. `quit-running` (the real app at $(APP)) and
# `scratch-pids` are defined here for the project's own targets too.

# Leave the including Makefile's default goal alone, wherever the include is.
_scratch_data_default_goal := $(.DEFAULT_GOAL)

$(if $(SCRATCH_BUILD),,$(error scratch-data: set SCRATCH_BUILD, the target that builds the scratch app, before the include))

.PHONY: run-scratch scratch-reset

# A shell command printing the pids of processes started from the bundle at
# $(1), a path relative to here or absolute, which may contain spaces, its
# embedded helpers included. Only processes whose command line starts with
# that absolute (physical) path are found: a relative path or the bundle id
# would also reach a build from another checkout of the same project.
app-pids = app='$(1)'; [ "$${app\#/}" != "$$app" ] || app='$(CURDIR)'/"$$app"; \
  d=$$(cd "$$(dirname "$$app")" 2>/dev/null && pwd -P) && app="$$d/$$(basename "$$app")"; \
  ps -axo pid=,args= | awk -v p="$$app/Contents/" \
  '{ pid = $$1; sub(/^ *[0-9]+ /, ""); if (index($$0, p) == 1) print pid }'

# The scratch build's processes, for a project's screenshot target.
scratch-pids = $(call app-pids,$(SCRATCH_APP))

# Quit the app built at $(1), if it is running, and wait for it to go: `open`
# would otherwise just bring the running copy forward. Each process is quit by
# its pid, never by bundle id.
define _quit_app
	@pids=$$($(call app-pids,$(1))); \
	if [ -n "$$pids" ]; then \
	  for pid in $$pids; do \
	    osascript -l JavaScript -e "ObjC.import('AppKit'); \$$.NSRunningApplication.runningApplicationWithProcessIdentifier($$pid).terminate" >/dev/null 2>&1 || true; \
	  done; \
	  for i in $$(seq 50); do [ -n "$$($(call app-pids,$(1)))" ] || break; sleep 0.2; done; \
	  pids=$$($(call app-pids,$(1))); [ -z "$$pids" ] || kill $$pids 2>/dev/null || true; \
	fi
endef
quit-running = $(call _quit_app,$(APP))
quit-scratch = $(call _quit_app,$(SCRATCH_APP))

# The scratch build, in the background (`open -g`), so that an agent can run
# it while someone else uses the machine. It refuses a bundle without
# `ScratchBuild = YES`: launching the real build here would put an agent on
# real data while it believes it is on scratch.
run-scratch: $(SCRATCH_BUILD)
	@v=$$(plutil -extract ScratchBuild raw -o - "$(SCRATCH_APP)/Contents/Info.plist" 2>/dev/null); \
	case "$$v" in true|YES|yes|1) ;; \
	  *) echo "✗ $(SCRATCH_APP) is not a scratch build (no ScratchBuild = YES in its Info.plist); not launching it"; exit 1;; esac
	$(quit-scratch)
	open -g -n "$(SCRATCH_APP)" $(if $(strip $(SCRATCH_ARGS)),--args $(SCRATCH_ARGS))
	@echo "✓ launched the scratch build, in the background"

# Refuses a SCRATCH_DIR or SCRATCH_DEFAULTS that does not name the scratch
# bundle id: an empty or mistyped variable must not become `rm -rf` of the
# real data, or `defaults delete` of the real settings.
scratch-reset:
	@case "$(SCRATCH_DIR)" in *.scratch|*.scratch/*) ;; \
	  *) echo "✗ SCRATCH_DIR ('$(SCRATCH_DIR)') must be under the scratch bundle id (a path component ending \".scratch\")"; exit 1;; esac
	@case "$(SCRATCH_DEFAULTS)" in ""|*.scratch|*.scratch/*) ;; \
	  *) echo "✗ SCRATCH_DEFAULTS ('$(SCRATCH_DEFAULTS)') must be the scratch bundle id's (ending \".scratch\")"; exit 1;; esac
	$(quit-scratch)
	rm -rf "$(SCRATCH_DIR)"
	@# `defaults delete`, not `rm`: cfprefsd caches the file, and a plist
	@# removed underneath it comes back with the old values.
	$(if $(SCRATCH_DEFAULTS),-defaults delete "$(SCRATCH_DEFAULTS)" 2>/dev/null)
	@echo "✓ removed the scratch data (takes effect at the next run-scratch)"

.DEFAULT_GOAL := $(_scratch_data_default_goal)

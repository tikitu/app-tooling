# scratch-data.mk — run the Mac app on scratch data, and throw that away.
#
# Imported by peru from the app-tooling pattern `scratch-data`
# (https://github.com/tikitu/app-tooling). Never edit it here: `peru sync`
# refuses to overwrite a changed copy, and the change belongs in app-tooling.
# docs/app-tooling/scratch-data/ says how to use it.
#
# The project's Makefile sets these, then `include mk/scratch-data.mk`:
#
#   APP               the built .app                              (required)
#   SCRATCH_DIR       the directory --scratch-database keeps its
#                     data in; its name must contain "scratch"    (required)
#   SCRATCH_DEFAULTS  the scratch user defaults, as
#                     `defaults delete` takes them                (optional)
#   SCRATCH_BUILD     the target that builds $(APP)  (default: build)
#
# SCRATCH_BUILD must be set before the include: make reads prerequisites as
# it reads the rule. `quit-running` is defined here for the project's own run
# targets too.

# Leave the including Makefile's default goal alone, wherever the include is.
_scratch_data_default_goal := $(.DEFAULT_GOAL)

SCRATCH_BUILD ?= build

.PHONY: run-scratch scratch-reset

# Quit the app built at $(APP), if it is running, and wait for it to go:
# `open` would otherwise just bring the running copy forward, on whatever
# data it already has. Only processes whose command line starts with this
# checkout's absolute $(APP) are touched, each quit by its pid: a relative
# path or the bundle id would also reach the real app, built from another
# checkout of the same project.
_quit_running_pids = ps -axo pid=,args= | awk -v p='$(abspath $(APP))/Contents/MacOS/' \
  '{ pid = $$1; sub(/^ *[0-9]+ /, ""); if (index($$0, p) == 1) print pid }'
define quit-running
	@pids=$$($(_quit_running_pids)); \
	if [ -n "$$pids" ]; then \
	  for pid in $$pids; do \
	    osascript -l JavaScript -e "ObjC.import('AppKit'); \$$.NSRunningApplication.runningApplicationWithProcessIdentifier($$pid).terminate" >/dev/null 2>&1 || true; \
	  done; \
	  for i in $$(seq 50); do [ -n "$$($(_quit_running_pids))" ] || break; sleep 0.2; done; \
	  pids=$$($(_quit_running_pids)); [ -z "$$pids" ] || kill $$pids 2>/dev/null || true; \
	fi
endef

# The app on scratch data, in the background (`open -g`), so that an agent
# can run it while someone else uses the machine. This is the target for
# agents and scripted checks; `make run` is for a person, on real data.
run-scratch: $(SCRATCH_BUILD)
	$(quit-running)
	open -g -n "$(APP)" --args --scratch-database
	@echo "✓ launched on scratch data, in the background"

# Refuses a SCRATCH_DIR that does not say "scratch": an empty or mistyped
# variable must not become `rm -rf` of the real data.
scratch-reset:
	@case "$$(basename "$(SCRATCH_DIR)")" in *scratch*) ;; \
	  *) echo "✗ SCRATCH_DIR ('$(SCRATCH_DIR)') must name a directory containing \"scratch\""; exit 1;; esac
	$(quit-running)
	rm -rf "$(SCRATCH_DIR)"
	@# `defaults delete`, not `rm`: cfprefsd caches the file, and a plist
	@# removed underneath it comes back with the old values.
	$(if $(SCRATCH_DEFAULTS),-defaults delete "$(SCRATCH_DEFAULTS)" 2>/dev/null)
	@echo "✓ removed the scratch data (takes effect at the next run-scratch)"

.DEFAULT_GOAL := $(_scratch_data_default_goal)

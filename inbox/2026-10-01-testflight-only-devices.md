# Once TestFlight is how the phone gets builds, refuse development installs on it

**Problem.** ReadingRecord, 2026-10-01, right after its first TestFlight
build reached the owner's phone. The phone holds the real data, and the
project's `make ios-device-run` still installed onto it by default
(`IOS_DEVICE ?= <the phone>`), from any tree: dirty, a branch, half done.
Until TestFlight, that *was* how the phone got builds, so an agent told to
"verify by running" reaches for it naturally. The cost is not the install
itself but what a development build does to real data: a new migration or
enum case runs forward on it, syncs (here to CloudKit Production), and can
leave the TestFlight build and other devices unable to read it.
Reinstalling TestFlight does not undo that.

It happened while the guard was being written: the first version passed
everything, the agent tested it by running the real target, and a
development build went onto the phone over TestFlight. Harmless that time
(no app code differed), but it is the exact failure.

**What worked** (ReadingRecord `075f97b`): a project-level guard.

```make
TESTFLIGHT_ONLY_DEVICES ?= My iPhone          # comma-separated
ios-device-guard:
	@list='$(TESTFLIGHT_ONLY_DEVICES)'; IFS=','; for d in $$list; do \
	  d="$${d# }"; d="$${d% }"; \
	  if [ "$$d" = '$(IOS_DEVICE)' ] && [ "$(INSTALL_ON_TESTFLIGHT_DEVICE)" != yes ]; then \
	    echo "✗ '$(IOS_DEVICE)' gets builds only through TestFlight"; exit 1; \
	  fi; \
	done
ios-device-run: ios-device-guard ios-device-build
```

Two traps found on the way:

- **`for d in $(LIST)` in a recipe splits on spaces whatever `IFS` says**
  (`IFS` applies to expansion results, not to words the parser sees), so a
  device name with spaces never matches and the guard silently passes.
  The list has to go through a shell variable.
- **Test a guard against a case it must refuse, with nothing real behind
  it**: the full target with `IOS_DEVICE` and the list both set to a device
  name that does not exist. Running the real target is how the phone got
  the build.

**Idea, for the `testflight` pattern.** The guard belongs to the pattern,
because it only makes sense once TestFlight is how a device gets builds;
an app without the pattern must not get it. A seam that does that:

- `mk/testflight.mk` defines `TESTFLIGHT_ONLY_DEVICES ?=` (empty), the
  `testflight-device-guard` target, and
  `TESTFLIGHT_DEVICE_GUARD := testflight-device-guard`.
- A project's own install target lists `$(TESTFLIGHT_DEVICE_GUARD)` first
  among its prerequisites. Without the pattern the variable is empty and the
  prerequisite disappears; with it, the guard runs. (As with
  `TESTFLIGHT_PREPARE`, the include must come before the rule, because make
  expands prerequisites as it reads.)
- `apply.md` gains a step: name the real-data devices, and add the
  prerequisite to the install target. Open question: whether an empty list
  should be a warning from `make testflight-upload`, since the pattern cannot
  know which devices hold real data and the safe default is not obvious.

Related: ReadingRecord's next step goes further, a separate development app
(own bundle id and database, on CloudKit Development) so that development
builds cannot touch real data at all. If that works it may be the better
thing to promote, with this guard as the cheap first step.

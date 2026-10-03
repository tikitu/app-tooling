# Applying ios-simulators

Read [`README.md`](README.md) first for what this does and why.

> **Draft.** Enough to apply it; not yet tried on a second project.

## Detect

- **Already adopted:** `peru.yaml` imports `app-tooling|ios-simulators`.
- **Something else choosing simulators.** Look in the Makefile and scripts
  for `-destination` with `iOS Simulator`, `IOS_SIM`, `IOS_DEST`,
  `simctl boot|create|install`, and for scripts that pick a device. Note
  `CODE_SIGNING_ALLOWED=NO` on a simulator build: that is the "preflight
  checks" trap, and this pattern replaces it.

## Parameters

| Parameter | Where to find it |
|---|---|
| `IOS_SIM_NAME` | the app's name, as used elsewhere in the Makefile |
| `IOS_PHONE_RUNTIME` | the phone's iOS: `xcrun devicectl device info details --device '<phone>' --json-output f.json`, `result.deviceProperties.osVersionNumber`; then the newest installed runtime not newer than it, from `xcrun simctl list runtimes` (its identifier, `com.apple.CoreSimulator.SimRuntime.iOS-26-5`). If none is installed for that major version, ask the user before downloading one |
| `IOS_SIM_TYPE` | only if the default device type is not supported by both runtimes (`xcrun simctl list runtimes -j`, `supportedDeviceTypes`) |

## Steps

**1. Import the pattern.** In `peru.yaml`, under `imports:`:

```yaml
    app-tooling|ios-simulators: ./
    app-tooling|ios-simulators-docs: docs/app-tooling/ios-simulators/
```

and beside the other rules:

```yaml
rule ios-simulators:
    export: patterns/ios-simulators/files
rule ios-simulators-docs:
    export: patterns/ios-simulators
    pick: [patterns/ios-simulators/README.md, patterns/ios-simulators/apply.md, patterns/ios-simulators/CHANGELOG.md]
```

**2. Include it** from the Makefile, after setting its parameters:

```make
IOS_SIM_NAME      := MyApp
IOS_PHONE_RUNTIME ?= com.apple.CoreSimulator.SimRuntime.iOS-26-5
include mk/ios-simulators.mk
```

**3. Use it in the project's simulator targets.** Replace any fixed
`-destination` and `CODE_SIGNING_ALLOWED=NO`. For example:

```make
ios-build: ios-project
	xcodebuild build -project $(IOS_PROJECT) -scheme MyApp $(IOS_SIM_BUILD_FLAGS)

ios-test:
	@$(IOS_SIM_UDID); \
	  xcodebuild test -scheme MyAppIOSKit-Package -workspace Packages/MyAppIOSKit \
	  -destination "id=$$UDID"

ios-test-all:
	$(MAKE) ios-test IOS_SIM="$(IOS_SIM_NAME)"
	$(MAKE) ios-test IOS_SIM="$(IOS_SIM_PHONE)"

ios-run: ios-build
	@$(IOS_SIM_UDID); \
	  APP_PATH=$$(xcodebuild -project $(IOS_PROJECT) -scheme MyApp \
	    -destination 'generic/platform=iOS Simulator' -showBuildSettings 2>/dev/null \
	    | awk -F' = ' '/ BUILT_PRODUCTS_DIR/ {d=$$2} / FULL_PRODUCT_NAME/ {n=$$2} END {print d"/"n}'); \
	  xcrun simctl boot "$$UDID" 2>/dev/null || true; \
	  xcrun simctl install "$$UDID" "$$APP_PATH" && \
	  xcrun simctl launch "$$UDID" $(IOS_BUNDLE_ID) && open -a Simulator
```

Keep any flags the project already passes (pinned packages, for example).

**4. Say so in the project's build documentation**: `make ios-sims` after
an Xcode update, and move `IOS_PHONE_RUNTIME` when the phone updates.

## Verify

- `make ios-sims`, twice: `xcrun simctl list devices | grep MyApp` shows
  exactly one `MyApp` (on the newest iOS) and one `MyApp Phone OS` (under
  the phone's runtime heading).
- `make ios-test IOS_SIM=Nope` fails with "no simulator named Nope: run
  make ios-sims".
- `make ios-test-all` reports a test run on each simulator — look for the
  test counts, not just exit 0.
- `make ios-run` and `make ios-run IOS_SIM="MyApp Phone OS"` each print
  `<bundle id>: <pid>`, and the app is open in Simulator.

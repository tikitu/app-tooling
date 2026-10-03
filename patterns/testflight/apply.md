# Applying testflight

Read [`README.md`](README.md) first for what this does and why, and in
particular "iCloud and CloudKit".

## Detect

- **Already adopted:** `peru.yaml` imports `app-tooling|testflight`.
  Updates come with `make app-tooling-update`.
- **Something else distributing the app.** Look for:
  - `fastlane/` or a `Fastfile`;
  - `xcrun altool`, `-exportArchive`, `ExportOptions.plist` or `.ipa` in
    the Makefile or scripts;
  - `ci_scripts/` (Xcode Cloud), or CI workflows that archive;
  - an `ios-archive`, `ios-release` or similar target.

  If any exist, describe what the project does and what this pattern would
  do instead to the user, and ask, before changing anything.
- **iCloud or push entitlements.** Look in `project.yml` for
  `com.apple.developer.icloud-*` and `aps-environment`. If the app uses
  CloudKit, **stop here** and go through README's "iCloud and CloudKit"
  with the user: TestFlight builds will use the Production environment. Do
  not continue until the user has decided how the app's data moves (schema
  deployed, which clients move and when, a backup), and record the decision
  in `app-tooling.toml`. For `aps-environment` alone, tell the user that
  TestFlight builds register for production push.
- **Entitlements that need Apple's approval to distribute**, such as
  `com.apple.developer.family-controls`: see README's "When not to use
  it", and ask the user before going on.
- **Requirements:** `peru.yaml` imports `git-commit-stamp`; there is an
  XcodeGen `project.yml` and a make target that generates the project. If
  not, those come first.

## Parameters

| Parameter | Where to find it |
|---|---|
| Xcode project and scheme | the Makefile's iOS variables (often `IOS_PROJECT`, `IOS_SCHEME`) |
| Team id | `DEVELOPMENT_TEAM` in `project.yml` |
| The target that generates the project | the Makefile, usually `ios-project` |
| Extra xcodebuild flags | whatever the Makefile passes to its other `xcodebuild` calls for pinned packages (`-onlyUsePackageVersionsFromResolvedFile`, `-skipMacroValidation`) |
| Release branch | the branch the project releases from; usually `main` |
| Export compliance | **the user's answer**, never a guess: does the app use encryption beyond what the OS provides (HTTPS, Keychain, CryptoKit used for its own data)? Apple's [guide](https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations) has the detail |
| Internal testing only | the user's choice: `YES` if builds should never go to external testers |

## Steps

**1. Import the pattern.** In `peru.yaml`, under `imports:`:

```yaml
    app-tooling|testflight: ./
    app-tooling|testflight-docs: docs/app-tooling/testflight/
```

and beside the other rules:

```yaml
rule testflight:
    export: patterns/testflight/files
rule testflight-docs:
    pick: [patterns/testflight/README.md, patterns/testflight/apply.md, patterns/testflight/CHANGELOG.md]
    export: patterns/testflight
```

Then `uvx peru@1.3.5 sync`.

**2. Declare export compliance** in the app target's `info: properties:`
in `project.yml`, with the user's answer:

```yaml
        # Export compliance, declared by the app's owner: the app uses no
        # encryption beyond the OS's own (HTTPS). See
        # docs/app-tooling/testflight/README.md.
        ITSAppUsesNonExemptEncryption: false
```

(`true` also needs `ITSEncryptionExportComplianceCode`, from App Store
Connect.)

**3. The Makefile.** After the `include mk/app-tooling.mk`, with `=` rather
than `:=`, since the variables it names may be defined further down:

```make
# Distribution through TestFlight (app-tooling: testflight).
TESTFLIGHT_PROJECT     = $(IOS_PROJECT)
TESTFLIGHT_SCHEME      = $(IOS_SCHEME)
TESTFLIGHT_TEAM        = <team id>
TESTFLIGHT_PREPARE     = ios-project
TESTFLIGHT_XCODE_FLAGS = $(XCODE_PINNED)
include mk/testflight.mk
```

`TESTFLIGHT_PREPARE` must come before the `include`. Add the two targets
to `help`:

```make
	@echo "  testflight-validate  Archive and have App Store Connect check it; uploads nothing"
	@echo "  testflight-upload    Archive a clean commit on main and upload it to TestFlight"
```

**4. One-time setup, by the user**, in
[App Store Connect](https://appstoreconnect.apple.com). An agent cannot do
these; list them for the user:

- **Create the app record**: Apps → + → New App, iOS, with the bundle id
  from `project.yml`. The name must be unique on the App Store; it can be
  changed until the app is released.
- **Testers**: in the app's TestFlight tab, an internal testing group with
  the user in it, and automatic distribution turned on, so each processed
  build reaches their devices without a click.
- On each device, the TestFlight app, signed into the same Apple account.

**5. `AGENTS.md`**: where it describes installing on a device, say that
devices get builds through TestFlight (`make testflight-upload`), that
`make testflight-validate` checks without uploading, and that uploads are
for the user to ask for: an upload uses a build number and puts a build on
testers' devices. For an app with CloudKit, add what was decided in the
Detect step, and that development builds go to the simulator or a spare
device only.

**6. Record it** in `app-tooling.toml`, with the export compliance answer
and, for CloudKit apps, the decision:

```toml
[patterns.testflight]
params = { export_compliance = "no non-exempt encryption (HTTPS only), declared by the owner" }
```

## Verify

- `make testflight-validate` prints
  `✓ App Store Connect accepts <bundle id> <version> (<count>.0, <commit>)`.
  Before the app record exists it fails with "App Store Connect has no app
  with the bundle id …", which is the expected state until step 4.
- Refusals, without archiving: with an uncommitted change it says
  "commit or stash first"; on another branch, "on <branch>, not main".
- **Only when the user asks for it:** `make testflight-upload`, then the
  build appears in App Store Connect's TestFlight tab (processing takes
  minutes), and installs from the TestFlight app. After installing,
  `make ios-device-which` names the commit.

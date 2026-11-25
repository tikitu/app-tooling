# Applying mac-dist

Read [`README.md`](README.md) first for what this does and why.

## Detect

- **Already adopted:** `peru.yaml` imports `app-tooling|mac-dist`.
- **Copied from the starter:** the `Makefile` has `dist`, `check-version`,
  `sign`, `zip-notary`, `notarize`, `staple`, `zip-release`, `checksum`,
  `verify-release`, `github-release` and `print-version` targets, and a
  "Release variables" block (`GIT_TAG_VERSION`, `FILE_VERSION`, `VERSION`,
  `DIST_DIR`, `NOTARY_ZIP`, `RELEASE_ZIP`, `CERT_NAME`, `NOTES_FILE`). The
  steps below replace them. Compare each with this pattern's
  `mk/mac-dist.mk` first, and list what the project's do that the
  pattern's do not; usually:
  - extra `codesign` lines in `sign` for nested code: these become the
    project's `MAC_DIST_SIGN_NESTED` target (step 3);
  - a `notary-setup` that takes only one kind of credential: the pattern
    takes both;
  - anything else: describe it to the user before replacing it. It may
    belong in the pattern instead.
- **Something else doing this job.** Look for `notarytool`, `altool`,
  `stapler`, `--options runtime` or `Developer ID` in the `Makefile`,
  scripts and CI configuration; an Xcode archive with an export options
  plist (`method` `developer-id`); fastlane's `notarize`; Sparkle's
  tooling. Describe what is there to the user, and ask, before changing
  anything.
- **Not adopted:** the app has never been released outside the App Store.

## Parameters

| Parameter | Where to find it |
|---|---|
| `MAC_DIST_APP` | the built bundle: the `Makefile`'s `APP`, usually `build/<App>.app` |
| `MAC_DIST_NAME` | the app's name as it should appear in `<Name>-<version>-macos.zip`: the `Makefile`'s `APP_NAME`. Changing it changes the asset's name, which a cask or a download link may depend on |
| `MAC_DIST_ENTITLEMENTS` | the entitlements `build.sh` signs with: the `Makefile`'s `ENTITLEMENTS` |
| `MAC_DIST_BUILD` | the target that builds `MAC_DIST_APP` in its release configuration: `release` in the starter |
| `MAC_DIST_CLEAN` | only if the clean target is not `clean`. It must remove `dist/` |
| `MAC_DIST_SIGN_NESTED` | only for nested code: the project's own target (step 3) |
| `TEAM_ID`, `DEVELOPER_NAME` | from the Developer ID Application certificate: `security find-identity -v -p codesigning` shows `Developer ID Application: <DEVELOPER_NAME> (<TEAM_ID>)` |
| `NOTARY_PROFILE` | the keychain profile `notary-setup` stores the credentials as. One profile can serve every app of the team |

## Steps

The project must already have `pattern-imports`.

**1. Import the pattern.** In `peru.yaml`, under `imports:`:

```yaml
    app-tooling|mac-dist: ./
    app-tooling|mac-dist-docs: docs/app-tooling/mac-dist/
```

and beside the other rules:

```yaml
rule mac-dist:
    export: patterns/mac-dist/files
rule mac-dist-docs:
    pick: [patterns/mac-dist/README.md, patterns/mac-dist/apply.md, patterns/mac-dist/CHANGELOG.md]
    export: patterns/mac-dist
```

Then `uvx peru@1.3.5 sync`, which puts `mk/mac-dist.mk` in place.

**2. The `Makefile`.** Delete the release variables and targets listed
under Detect, and their `.PHONY` entries (keep `DEV_IDENTITY` and anything
else the everyday build uses). In their place, before any line that reads
`VERSION` with `:=`:

```make
# `make dist`: signed with the Developer ID, notarized, stapled, zipped and
# checked; `make github-release` publishes it (app-tooling: mac-dist).
# docs/app-tooling/mac-dist/.
TEAM_ID               ?= XXXXXXXXXX
DEVELOPER_NAME        ?= My Company Ltd
NOTARY_PROFILE        ?= myapp-notary
MAC_DIST_APP          := $(APP)
MAC_DIST_NAME         := $(APP_NAME)
MAC_DIST_ENTITLEMENTS := $(ENTITLEMENTS)
MAC_DIST_BUILD        := release
include mk/mac-dist.mk
```

The `MAC_DIST_*` variables must be set before the `include`. Recipes that
read `$(VERSION)` (the build passing it to `build.sh`) can be anywhere.

**3. Nested code, if any.** A target of the project's, set as
`MAC_DIST_SIGN_NESTED` before the `include`. It depends on the build and
signs each piece inside out, each with its own identifier:

```make
MAC_DIST_SIGN_NESTED := sign-nested
sign-nested: release
	$(mac_dist_codesign) --identifier com.example.myapp.helper "$(APP)/Contents/MacOS/MyAppHelper"
```

Add it to `.PHONY`. Entitlements of its own, if the nested code has any,
go on its line with `--entitlements`.

**4. `help`.** If the `Makefile`'s `help` lists the release targets, keep
the lines; check they still name `$(RELEASE_ZIP)` and `$(NOTARY_PROFILE)`,
which the pattern defines.

**5. The release notes.** Where the project's docs say how to release
(`docs/releasing.md`, a README section), link
`docs/app-tooling/mac-dist/README.md` for the targets, and keep only what
is the project's: who releases, on which Mac, where the secrets are kept.

## Verify

Without a signing identity, and without uploading anything:

```sh
make -n dist VERSION=0.0.0 | grep -E 'codesign|notarytool|stapler|ditto|spctl'
make print-version
```

- `make -n` lists, in order: `codesign` for each nested piece (from step 3)
  and then the app, each with `--options runtime --timestamp --sign
  "Developer ID Application: …"`; `ditto` to the `-notary.zip`;
  `notarytool submit … --keychain-profile <NOTARY_PROFILE> --wait`;
  `stapler staple` and `validate`; `ditto` to the `-macos.zip`; `spctl` and
  `codesign --verify --deep`. A nested piece missing here is missing from
  the release.
- Where the project already released with its own targets, compare: `make
  -n dist VERSION=0.0.0` before the change and after should differ only in
  the order of `codesign`'s options.
- `print-version` shows the `VERSION` file's version, and `(none)` for the
  tag unless `HEAD` has one.

On the Mac that releases, the real check is the next release: `make dist`
must end with `spctl` printing `accepted` and `source=Notarized Developer
ID`. `make verify-release VERSION=<x>` does the same without a tag, but
uploads to Apple and asks to use the signing key.

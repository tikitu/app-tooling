# testflight changelog

## v0.6.0 (2026-10-24)

- **`TESTFLIGHT_ARCHIVE_CHECK`**: a shell command `scripts/testflight.sh`
  runs on the archived app, with its path as the last argument, after its
  own checks and before the export; a failure stops the upload. Nothing to
  do unless the project checks archives: then set it (with
  `sync-configuration`, `$(SYNC_CHECK) --expect production`) and remove
  the project's own archive check (`apply.md` step 3).

## v0.4.0 (2026-10-20)

- **`testflight-device-guard`** refuses a development install on a device
  that gets builds only through TestFlight. To take it: set
  `TESTFLIGHT_ONLY_DEVICES` (comma-separated, the user's answer) before the
  `include mk/testflight.mk`, and list `$(TESTFLIGHT_DEVICE_GUARD)` first
  among the install target's prerequisites, after the include; if the
  device variable is not `IOS_DEVICE`, set `TESTFLIGHT_INSTALL_DEVICE`.
  Replace any guard of the project's own. `apply.md` step 3 has the text,
  step 5 what `AGENTS.md` says, and Verify how to test it without a real
  device.

## v0.1.0 (2026-10-05)

First version: `make testflight-validate` and `make testflight-upload`
archive a clean commit on the release branch, check its stamp and export
compliance, and send it to App Store Connect with a cloud-managed
distribution certificate.

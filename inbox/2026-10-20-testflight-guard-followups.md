# After the TestFlight device guard: an empty list, and a development app

Left over when `testflight-device-guard` was promoted (2026-10-20, from
ReadingRecord, 2026-10-01).

- **An empty `TESTFLIGHT_ONLY_DEVICES`** guards nothing. The pattern cannot
  know which devices hold real data, so `apply.md` asks the user. Open:
  whether `make testflight-upload` should warn when the list is empty, since
  the safe default is not obvious.
- **A separate development app** (its own bundle id and database, on
  CloudKit Development) would mean development builds cannot touch real data
  at all. ReadingRecord meant to try it next. If it works, it may be the
  better thing to promote, with the guard as the cheap first step.

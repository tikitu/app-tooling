# `URL.path()` keeps the percent-encoding

**Rule:** `url-path-keeps-percent-encoding`, in `semgrep/url-path.yml`

It has cost an evening in an earlier app.

## The rule

Never call `URL.path()`. Call `path(percentEncoded: false)` for a filesystem
path.

## Why it fails silently

`path()` is the RFC 3986 accessor: it returns the path *as it appears in a
URL*, escaped. Under the sandbox every path this app uses is inside
`~/Library/Containers/…/Application Support/…` or `…/tmp/…`, and the first of
those has a space in it. Hand `…/Application%20Support/…` to SQLite, to
`FileManager`, or to a subprocess, and it names a directory that does not
exist.

What happens then is the quiet part. When the database open threw inside
`withErrorReporting` at the entry point, the app launched, drew its window,
showed an empty list and wrote no file — which looks exactly like "no data
yet".

## What to do instead

`url.path(percentEncoded: false)`. For display, `lastPathComponent`.

## When a finding is not a bug

When the escaped form is what is wanted — building another URL string by
hand. There is no such case in the template; if one appears, say why in a
comment and suppress with `// nosemgrep: url-path-keeps-percent-encoding`.

## What would break the rule

It matches the zero-argument call only. `path` (the deprecated property) is
not flagged, because it does *not* percent-encode.

## Validated against

A reconstruction: `let path = url.path()` in `bootstrapDatabase` is flagged;
the file as it is, with `path(percentEncoded: false)`, is not.

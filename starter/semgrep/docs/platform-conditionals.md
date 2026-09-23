# Platforms are split by package, not by `#if`

**Rule:** `platform-conditional-compilation`, in
`semgrep/platform-conditionals.yml`

## The rule

No `#if os(…)`, `#if canImport(…)` or `#if targetEnvironment(…)` in the
packages. Code for one platform lives in that platform's package:

- `Packages/StarterKit` declares macOS and iOS, and holds everything that is
  not specific to one of them. `make check` compiles it for iOS as well as
  the Mac, so a Mac-only API there is a build error.
- `Packages/StarterMacKit` declares macOS only, and holds the Mac app and its
  Mac-only views. An iOS app would get its own iOS-only package beside it.

`#if DEBUG` and other conditions that are not about the platform are not
affected.

## Why it fails silently

A platform `#if` compiles on the platform you are building, and says nothing
about the other branch, which nobody is building. Each guard looks harmless;
together they turn the shared code into two programs interleaved, where the
one not currently built rots unseen until someone builds it.

They also fight the tools. `swift format` moves a `#if` that sits between
view modifiers onto the end of the previous line, which does not compile
(`docs/gotchas.md`). And unless `indentConditionalCompilationBlocks` is off
(it is, in `.swift-format`), wrapping a block in a new `#if` reindents every
line inside it, so a one-line change arrives as a diff of hundreds.

The package boundary does the same job at compile time, for free: code in
the Mac package cannot be imported by the shared one, and code in the shared
one has to compile for every platform it declares.

## What to do instead

Move the code to the package for its platform. If shared code needs
something only one platform can provide, give the shared code a protocol or
a dependency (`@Dependency`) and have each platform's package supply the
implementation.

## When a finding is not a bug

A dependency's API that genuinely differs by platform, with no sensible
split — rare. Say why in a comment and suppress with
`// nosemgrep: platform-conditional-compilation`.

## What would break the rule

It is a regular expression over lines beginning `#if` or `#elseif` that
mention `os(`, `canImport(` or `targetEnvironment(`. A condition split across
lines, or built from a custom compilation flag set per platform, slips
past; widen the pattern if either appears.

## Validated against

A reconstruction: a file with `#if os(macOS)`, `#elseif canImport(UIKit)`
and `#if DEBUG` gives two findings, the first two. The template as it is
gives none.

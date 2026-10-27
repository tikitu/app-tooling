# Prototypes: safe-area insets over split views (research, not a pattern)

On macOS, a `.safeAreaInset`/`.safeAreaBar` over a view that contains a split
view (`HSplitView`, `VSplitView`, `NavigationSplitView`, or `.inspector`) does
not inset the split view's panes: their scroll views run under the bar, and
the last rows hide behind it. The findings and the recommendation are on the
hub ticket "app-tooling: lint for safe-area insets over split views
(research)". Nothing here is imported by projects.

- `inset-lint/`: static. It has since grown into its own project,
  [muography](https://github.com/tikitu/muography), private for now, where
  it is maintained; this copy is the prototype as it was. A whole-repo checker on swift-syntax that follows
  view composition by type name (`body`, view members, wrappers, custom
  modifiers) and reports each inset whose receiver reaches a split view, with
  the chain. `make test` runs the fixtures; `inset-lint <root>...` exits 1
  when it flags something.
- `scroll-check/`: runtime. A dylib injected into a debug build
  (`DYLD_INSERT_LIBRARIES`) that, once the windows are up, hit-tests a row of
  points just inside the bottom and top of every scroll view's unobscured
  area. A point that hits something other than the scroll view means it is
  covered. Reports on stderr, exits 3 if covered. `SCROLL_CHECK_DELAY`
  (seconds, default 4); `SCROLL_CHECK_HOLD=1` keeps the app running, with
  the flagged views scrolled to their end, for a screenshot.

      swift build --package-path scroll-check
      DYLD_INSERT_LIBRARIES=scroll-check/.build/debug/libScrollCheck.dylib \
        build/MyApp.app/Contents/MacOS/MyApp --scratch-database

- `inset-probe/`: the experiment. Hosts the same layouts in windows and runs
  the runtime check on each: which ones drop the inset, and that the
  correct ones pass.

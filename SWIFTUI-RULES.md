# SwiftUI Rules

Rules for SwiftUI on the Mac, each an imperative followed by the failure
that taught it. Skim the imperatives; read the failure when something
inexplicable breaks. Apply them up front when building a view, and use them
as a checklist when reviewing one.

These are trimmed and adapted from the SwiftUI rules that came with Thomas
Ptacek's swiftui-app template, which the lineage's build system also came
from. What was dropped: process advice this repo already covers
(`PROGRESS.md`, gotchas, commit messages), rules tied to that template's own
app, and idioms that predate macOS 26.

They sit alongside the `swiftui-pro` skill rather than repeating it. That
skill reviews for modern API, data flow, accessibility and style; these are
the failures on the Mac that compile, pass their tests, and then break at
runtime. Where the two touch, they agree.

> **The meta-rule.** SwiftUI's compile-time guarantees are weaker than they
> look. Tests catch logic; they miss layout, constraint, animation and
> hosting bugs. **A passing test suite is not a passing app.** Every
> non-trivial view change needs a live run.

---

## 1. Animation and transitions: the silent constraint-engine crashes

### 1.1 Never insert or remove a view with a transition inside hosted SwiftUI.

```swift
// BAD — `_postWindowNeedsUpdateConstraintsUnlessPostingDisabled` crash
if isVisible {
    SomeView()
        .transition(.move(edge: .trailing).combined(with: .opacity))
}

// GOOD — always mounted, dimension animated
SomeView()
    .frame(width: isVisible ? targetWidth : 0)
    .clipped()
    .accessibilityHidden(!isVisible)
```

**Why.** When SwiftUI is hosted in a constraint-based hosting view (a
`Window` scene inside a `NavigationSplitView`, a sheet, a popover), the
constraint engine lays out in passes. A transition that inserts or removes a
view during a pass calls `setNeedsUpdateConstraints` from inside the update,
which `NSWindow` guards with an `NSInternalInconsistencyException`. It works
on some Macs and not others; strictness varies by hardware and OS minor
version.

**The fix is always the same.** Keep the view in the tree; animate a
*dimension* (width, height, opacity), not its *presence*. `.clipped()` hides
the content while collapsed.

### 1.2 `withAnimation { flag.toggle() }` is fine if the change is dimensional, not structural.

If the flag flips `if visible { … }`, you are back at 1.1. If it flips
`.frame(width: visible ? w : 0)`, you are safe.

### 1.3 A crash naming a private AppKit symbol only narrows it down.

`_postWindowNeedsUpdateConstraintsUnlessPostingDisabled` does not say which
view caused it. Reason from the stack (a recursive
`_informContainerThatSubviewsNeedUpdateConstraints` means "view modified
during update"), list the suspects in the recent diff, fix the likeliest, and
run again. Two attempts is normal.

### 1.4 Scope `TimelineView` to the smallest view that needs it.

```swift
// BAD — every tick redraws the whole row
TimelineView(.periodic(from: .now, by: 1)) { context in
    HStack { Image(…); Text(elapsed(at: context.date)); Spacer() }
}

// GOOD — only the digits redraw
HStack {
    Image(…)
    TimelineView(.periodic(from: startedAt, by: 1)) { context in
        Text(elapsed(at: context.date))
    }
    Spacer()
}
```

Every tick re-evaluates the body of whatever is inside. The same goes for
`Timer.publish` and `onReceive`. Prefer `TimelineView` to a timer: it pauses
off screen. Tick every 60s for clock times, every 1s for elapsed counters,
never faster without a reason.

---

## 2. Layout

### 2.1 Don't combine `.frame(maxWidth: .infinity)` with `.layoutPriority(n)`.

Priority asks for the *ideal* size first, and `maxWidth: .infinity` makes the
ideal effectively infinite; siblings get 0pt. To give a title space first,
use a trailing `Spacer(minLength:)`, or cap the *other* sibling's
`maxWidth`, or both.

### 2.2 `.fixedSize(horizontal: true, vertical: false)` makes a view inflexible.

It claims its ideal width whatever the context. Use it for things that must
never compress (a counter, a fixed-width chip), not on text that could
truncate, which then overflows the row when the parent shrinks.

### 2.3 Every `Text` in a row needs `.lineLimit(1).truncationMode(.tail)`.

Without `lineLimit`, text wraps, and a capsule background around it becomes
a tall pill that eats its siblings' space. Without the truncation mode you
may get leading truncation ("…long title").

### 2.4 Centralise layout metrics in one enum.

```swift
enum PaneMetrics {
    static let horizontalInset: CGFloat = 24
    static let rowMinHeight: CGFloat = 60
}
```

When you type `12` for the fifth time, it is a metric. When alignment drifts
between panes by 2pt, a scattered literal is why.

### 2.5 Push with `Spacer`, rather than grow with `frame(maxWidth: .infinity, alignment:)`.

Pushing is local and predictable. Growing with an alignment composes oddly
with priorities and parent proposals.

---

## 3. State and observation

### 3.1 A cache holding a snapshot of an `@Observable` value goes stale. Rebuild it.

```swift
struct AvailableThread {
    var thread: Thread        // ← a frozen copy
}

func setVisibility(_ thread: Thread, to visibility: Visibility) {
    threads[index].visibility = visibility   // mutates the source
    rebuildAvailable()                        // REQUIRED, or the cache lies
}
```

Observation propagates "this property changed" through the direct graph; it
does not chase copies embedded in other properties. The bug that taught
this: a setting only took effect for the first item changed, and later
changes looked like no-ops until something unrelated rebuilt the cache.

### 3.2 Don't build caches that patch themselves incrementally.

A rebuild from source is correct by construction. A patch that has to mirror
every setter's side effects will eventually miss one.

### 3.3 Changing a stored default does not change it for existing users.

`@SceneStorage` and `@AppStorage` defaults apply only when nothing is stored
yet. Flipping a default from `true` to `false` leaves everyone who has run
the app on the old value. If the change matters, migrate: write the new
value explicitly, once.

### 3.4 Identify `@Observable` objects by an immutable id, never by the instance.

In `ForEach` or `id:`, use a stored `UUID`. Don't rely on `==` between
observable reference types to mean equal values.

### 3.5 Read state at the last possible moment.

Don't capture a value into a `let` when a view appears and write it back
later: a change in between is clobbered. Read fresh in the action, mutate,
write.

---

## 4. Lists and rows

### 4.1 `.swipeActions` only works inside `List` or `Form`.

Cards in a `ScrollView` need `.contextMenu` instead. Offering both is fine.

### 4.2 Don't fork row code per pane.

Build one row view parameterised by data (with `@ViewBuilder` slots for the
parts that differ), so the eye moves between panes without retraining and a
change lands once. The same for a concept shown in several places, such as a
status chip: one component.

### 4.3 Hover-revealed actions fade; they are never inserted on hover.

```swift
hoverActions()
    .opacity(isHovered ? 1 : 0)
    .allowsHitTesting(isHovered)
    .animation(.easeOut(duration: 0.12), value: isHovered)
```

Inserting reflows the row as the pointer crosses it, which feels broken
(and see 1.1).

### 4.4 On the Mac, hover is `.onHover { isHovered = $0 }`.

`.hoverEffect()` is an iOS modifier and does nothing on the Mac.

### 4.5 Make a row's background priority explicit.

```swift
// Order is priority: selected > next > hovered > clear.
private var background: AnyShapeStyle {
    if isSelected { return AnyShapeStyle(.tint.opacity(0.12)) }
    if isNext { return AnyShapeStyle(.tint.opacity(0.06)) }
    if isHovered { return AnyShapeStyle(.gray.opacity(0.08)) }
    return AnyShapeStyle(.clear)
}
```

Same hue, different intensity, so "what to do next" reads differently from
"what I clicked".

### 4.6 Don't suppress the focus ring.

No `.focusEffectDisabled()` without a real reason. The ring on a focused
row is the affordance keyboard users navigate by.

---

## 5. Text

### 5.1 Use semantic font styles, not sizes.

`.font(.callout)`, not `.font(.system(size: 12))`; for emphasis, `.bold()`,
which lets the system pick the right weight for the context. Reach for other
weights only with a reason. Where a control brings its own typography
(button styles, `LabeledContent`), don't override it.

### 5.2 Don't build formatters in `body`.

Use `FormatStyle` (`Text(date, format: .dateTime…)`), or a `static let` if
you need a `Formatter`. A formatter built in `body` is built on every
render, and a ticking row renders constantly.

### 5.3 Clean strings at the data layer, not in the view.

A subtitle that already ends in `...`, shown with tail truncation, gets
`...` *and* `…`. It looks like a rendering glitch; it is data hygiene.

### 5.4 Compute time-dependent state in the view that shows it.

Pass a deadline chip the raw `Date`; let the chip tick (`TimelineView`) and
derive overdue / today / later itself. Callers then never have to decide
whether they need to tick.

### 5.5 `foregroundStyle` resolves innermost-wins.

```swift
HStack {
    Text(reading)        // inherits the container's tint
    DeltaTag(delta)      // sets its own style, which wins for its content
}
.foregroundStyle(tint)
```

You can tint a whole line and let one child reassert its own colour. The
corollary: setting `.foregroundStyle(.primary)` on a child "to be explicit"
silently opts it *out* of a tint you may have wanted.

---

## 6. Settings, windows and toolbars

### 6.1 Open Settings with `@Environment(\.openSettings)`, especially inside hosted containers.

`SettingsLink` brings its own hosting shim, which has caused constraint
invalidation inside `safeAreaInset` and list insets. A plain
`Button { openSettings() }` reaches the same `Settings` scene. The trade-off:
`openSettings()` cannot pre-select a tab. If that matters, put `SettingsLink`
at the root or in a toolbar.

### 6.2 Don't lead a `.primaryAction` toolbar group with `Spacer()`.

The placement already trails its items. A leading `Spacer` has caused a
launch crash through the toolbar's size computation. Just list the items.

### 6.3 Keep toolbar items' reads of observable state shallow.

A toolbar item that reads an expensive computed property re-evaluates it on
every redraw. Cache it, or move the read into a small dedicated view so
dependency tracking scopes the redraw.

### 6.4 A window whose state has gone must close itself.

A window opened for some state (`pendingFlow != nil`) can be restored by
SwiftUI at the next launch without that state, leaving a ghost window on
its "not found" branch. Have it dismiss itself when what it expects is
absent.

---

## 7. Swift Charts

### 7.1 A second line needs its own `series`, or the marks merge into one path.

```swift
// BAD — both default to the same series; Charts joins every point
Chart {
    ForEach(indoor) { LineMark(x: .value("t", $0.t), y: .value("v", $0.v)) }
    ForEach(outdoor) { LineMark(x: .value("t", $0.t), y: .value("v", $0.v)) }
}

// GOOD — distinct series, independently styled
Chart {
    ForEach(indoor) { LineMark(x: …, y: …, series: .value("Series", "Indoor")) }
    ForEach(outdoor) { LineMark(x: …, y: …, series: .value("Series", "Outdoor")) }
}
```

Discrete marks (`BarMark`, `RuleMark`) don't need this; colour distinguishes
them.

### 7.2 The x-domain is the union of everything plotted. Clip overlays to match.

A month of one series overlaid on a year of another shows the whole year,
the short one squashed against the right edge. Clip every overlay to the
primary series' window before plotting, or set `chartXScale(domain:)`.

---

## 8. Concurrency

### 8.1 A `@MainActor` type adopting a delegate protocol needs an isolated conformance.

```swift
// BAD — "conformance … crosses into main actor-isolated code"
@MainActor final class LocationProvider: NSObject, CLLocationManagerDelegate { … }

// GOOD
@MainActor final class LocationProvider: NSObject, @MainActor CLLocationManagerDelegate { … }
```

When the callbacks really do arrive on the main thread (as for a
`CLLocationManager` created there), isolate the conformance. Marking each
method `nonisolated` and hopping back with `MainActor.assumeIsolated` is
more ceremony for nothing.

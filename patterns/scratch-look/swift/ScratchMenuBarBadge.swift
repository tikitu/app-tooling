// ScratchMenuBarBadge.swift — a menu-bar app's icon on a scratch build.
//
// Imported by peru from app-tooling's pattern `scratch-look`
// (https://github.com/tikitu/app-tooling/tree/main/patterns/scratch-look).
// Never edit it here: the change belongs in app-tooling, and
// `make app-tooling-check` fails while this copy differs.

#if os(macOS)
  import AppKit
  import SwiftUI

  /// The menu-bar icon of a scratch build: the app's own mark beside
  /// "SCRATCH", black on caution yellow, so a scratch menu-bar app is never
  /// taken for the real one. A menu-bar app has no Dock icon and often no
  /// window, so this is where it shows.
  ///
  /// In the strip's colours (`ScratchDataBanner`, beside it). Drawn as an
  /// image that is not a template: a menu-bar label is otherwise tinted to
  /// the menu bar, and loses the yellow. The fixed colours read the same on a
  /// light or a dark menu bar. AppKit and SwiftUI only; macOS only.
  @MainActor
  public enum ScratchMenuBarBadge {
    /// `mark` (the real icon's glyph, at menu-bar size) and "SCRATCH" on the
    /// badge, for a `MenuBarExtra` label (`Image(nsImage:)`) or an
    /// `NSStatusItem` button. Render it again when the mark changes.
    public static func image(@ViewBuilder mark: () -> some View) -> NSImage {
      let renderer = ImageRenderer(content: ScratchMenuBarBadgeView(mark: mark()))
      renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
      let image = renderer.nsImage ?? NSImage()
      image.isTemplate = false
      return image
    }
  }

  /// What `ScratchMenuBarBadge` draws.
  struct ScratchMenuBarBadgeView<Mark: View>: View {
    let mark: Mark

    var body: some View {
      HStack(spacing: 3) {
        mark
        Text(verbatim: "SCRATCH")
      }
      .font(.system(size: 10, weight: .heavy))
      .foregroundStyle(ScratchDataBanner.ink)
      .padding(.horizontal, 5)
      .frame(height: 18)
      .background(ScratchDataBanner.caution, in: .rect(cornerRadius: 4))
    }
  }

  #Preview("Scratch menu-bar badge") {
    ScratchMenuBarBadgeView(mark: Image(systemName: "tray.and.arrow.down")).padding()
  }
#endif

// ScratchDockIcon.swift — a caution band on a Mac app's Dock icon while it
// runs on scratch data.
//
// Imported by peru from app-tooling's pattern `scratch-look`
// (https://github.com/tikitu/app-tooling/tree/main/patterns/scratch-look).
// Never edit it here: the change belongs in app-tooling, and
// `make app-tooling-check` fails while this copy differs.

#if os(macOS)
  import AppKit

  /// Puts the scratch icon's caution band on the Dock icon of a run on
  /// scratch data, so the Dock and the app switcher tell it from the real app.
  ///
  /// The band is drawn over the app's own icon at launch, in the look of
  /// `scripts/make-scratch-icon.py`, so it works for a real build run with
  /// `--scratch-database`, whatever its icon is made from. Self-contained
  /// AppKit, with no dependencies. iOS cannot change the home screen icon
  /// silently, so there is no iOS side.
  @MainActor
  public enum ScratchDockIcon {
    /// Bands the Dock icon when `isScratch`; does nothing otherwise, or when
    /// the build's own icon is already a scratch set (`AppIcon-Scratch`, or
    /// any icon name ending `-Scratch`). Call it at launch: from the entry
    /// point before the app runs, `App.init`, or
    /// `applicationDidFinishLaunching`.
    public static func apply(isScratch: Bool) {
      guard isScratch, !buildIconIsScratch else { return }
      // The bundle's icon, which draws sharp at any size: at launch,
      // `applicationIconImage` is a 256 px snapshot, blurred at 1024.
      let icon = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
      NSApplication.shared.applicationIconImage = bandedIcon(icon)
    }

    /// A scratch build already carries a banded icon; banding it again would
    /// draw a second band.
    private static var buildIconIsScratch: Bool {
      let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleIconName") as? String
      return name?.hasSuffix("-Scratch") ?? false
    }

    /// `icon` with the band across its lower right corner.
    static func bandedIcon(_ icon: NSImage) -> NSImage {
      NSImage(size: NSSize(width: 1024, height: 1024), flipped: true) { rect in
        icon.draw(
          in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true,
          hints: nil)
        guard let context = NSGraphicsContext.current?.cgContext else { return false }
        drawBand(in: context, size: rect.width)
        return true
      }
    }

    // The colours and proportions of make-scratch-icon.py at 128 px and up.
    private static let caution = NSColor(srgbRed: 250 / 255, green: 204 / 255, blue: 21 / 255, alpha: 1)
    private static let ink = NSColor(srgbRed: 24 / 255, green: 24 / 255, blue: 27 / 255, alpha: 1)

    /// Draws a horizontal band on a canvas twice the icon's size, turned 45°
    /// about its centre, with that centre moved down and right of the icon's
    /// so the band crosses the corner. The context is flipped (y down).
    private static func drawBand(in context: CGContext, size: CGFloat) {
      let height = (size * 0.22).rounded()
      let top = size - (height / 2).rounded(.down)
      let edge = max(1, (height * 0.16).rounded())
      let stripe = max(2, (height * 0.5).rounded())
      let offset = (size * 0.3).rounded()

      context.saveGState()
      defer { context.restoreGState() }
      context.translateBy(x: size / 2 + offset, y: size / 2 + offset)
      context.rotate(by: -.pi / 4)
      context.translateBy(x: -size, y: -size)

      context.setFillColor(caution.cgColor)
      context.fill(CGRect(x: 0, y: top, width: size * 2, height: height))

      context.setFillColor(ink.cgColor)
      for edgeTop in [top, top + height - edge] {
        var x = -stripe
        while x < size * 2 + stripe {
          context.move(to: CGPoint(x: x, y: edgeTop + edge))
          context.addLine(to: CGPoint(x: x + stripe, y: edgeTop + edge))
          context.addLine(to: CGPoint(x: x + stripe * 2, y: edgeTop))
          context.addLine(to: CGPoint(x: x + stripe, y: edgeTop))
          context.closePath()
          x += stripe * 2
        }
      }
      context.fillPath()

      let text = NSAttributedString(
        string: "SCRATCH",
        attributes: [
          .font: NSFont.systemFont(ofSize: ((height - 2 * edge) * 0.72).rounded(), weight: .bold),
          .foregroundColor: ink,
        ])
      let textSize = text.size()
      text.draw(at: CGPoint(x: size - textSize.width / 2, y: top + (height - textSize.height) / 2))
    }
  }
#endif

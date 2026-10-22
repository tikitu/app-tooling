// ScratchDataBanner.swift — a caution strip on windows that show scratch
// data.
//
// Imported by peru from app-tooling's pattern `scratch-look`
// (https://github.com/tikitu/app-tooling/tree/main/patterns/scratch-look).
// Never edit it here: the change belongs in app-tooling, and
// `make app-tooling-check` fails while this copy differs.

import SwiftUI

/// A caution strip across the top of a column: this run is on scratch data,
/// not the real data, and nothing in it syncs.
///
/// In the colours of the scratch icon's band (`scripts/make-scratch-icon.py`),
/// so a scratch run is never mistaken for the real app. Self-contained
/// SwiftUI, with no dependencies. Usually applied with
/// `.scratchDataBanner(_:short:)`.
public struct ScratchDataBanner: View {
  private let text: String
  private let short: String

  /// - Parameters:
  ///   - text: what the strip says where there is room, and what VoiceOver
  ///     reads everywhere.
  ///   - short: what it says in a narrow column, such as a sidebar.
  public init(_ text: String, short: String = "Scratch") {
    self.text = text
    self.short = short
  }

  public var body: some View {
    // The whole text where it fits; a narrow column says less.
    ViewThatFits(in: .horizontal) {
      Label(text, systemImage: "exclamationmark.triangle.fill")
      Label(short, systemImage: "exclamationmark.triangle.fill")
      Image(systemName: "exclamationmark.triangle.fill")
    }
    .font(.caption.weight(.semibold))
    .foregroundStyle(Self.ink)
    .lineLimit(1)
    .padding(.horizontal, Self.stripeWidth + 8)
    .padding(.vertical, 3)
    .frame(maxWidth: .infinity)
    .background(Self.caution)
    .overlay(alignment: .leading) { CautionStripes().frame(width: Self.stripeWidth) }
    .overlay(alignment: .trailing) { CautionStripes().frame(width: Self.stripeWidth) }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(text)
  }

  // The icon band's colours: fixed, not adaptive, because a caution strip
  // reads as one in either appearance.
  static let caution = Color(red: 250 / 255, green: 204 / 255, blue: 21 / 255)
  static let ink = Color(red: 24 / 255, green: 24 / 255, blue: 27 / 255)
  static let stripeWidth: CGFloat = 28
}

/// Black diagonal stripes on the caution yellow.
private struct CautionStripes: View {
  var body: some View {
    Canvas { context, size in
      context.fill(
        Path(CGRect(origin: .zero, size: size)), with: .color(ScratchDataBanner.caution))
      let stripe: CGFloat = 6
      var x = -size.height
      while x < size.width {
        var path = Path()
        path.move(to: CGPoint(x: x, y: size.height))
        path.addLine(to: CGPoint(x: x + stripe, y: size.height))
        path.addLine(to: CGPoint(x: x + stripe + size.height, y: 0))
        path.addLine(to: CGPoint(x: x + size.height, y: 0))
        path.closeSubpath()
        context.fill(path, with: .color(ScratchDataBanner.ink))
        x += stripe * 2
      }
    }
    .accessibilityHidden(true)
  }
}

extension View {
  /// Puts a `ScratchDataBanner` across the top of this view, or nothing
  /// when `text` is nil (a run on the real data).
  ///
  /// Apply it to each column of a `NavigationSplitView`, not to the split
  /// view: on macOS 26 the floating sidebar ignores an inset on the window,
  /// and the strip would cover its first row.
  public func scratchDataBanner(_ text: String?, short: String = "Scratch") -> some View {
    safeAreaInset(edge: .top, spacing: 0) {
      if let text {
        ScratchDataBanner(text, short: short)
      }
    }
  }
}

#Preview("Scratch run") {
  Text("Content")
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .scratchDataBanner("MyApp Scratch: scratch data, never synced")
}

#Preview("Narrow column") {
  Text("Sidebar")
    .frame(width: 180, height: 200)
    .scratchDataBanner("MyApp Scratch: scratch data, never synced")
}

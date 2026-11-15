// ScratchBuild.swift — whether this app is a scratch build.
//
// Imported by peru from app-tooling's pattern `scratch-data`
// (https://github.com/tikitu/app-tooling/tree/main/patterns/scratch-data).
// Never edit it here: the change belongs in app-tooling, and
// `make app-tooling-check` fails while this copy differs.

import Foundation

/// Whether this app is a scratch build: "MyApp Scratch", its own app with
/// its own bundle id (`<id>.scratch`), and so its own data, never synced.
///
/// A scratch build has no real mode and a real build has no scratch mode:
/// nothing about how the app was launched changes this. It is read from the
/// `ScratchBuild` key of the app's Info.plist, which only a scratch build
/// sets (`scripts/make-scratch-app.sh`, a scratch build configuration, or
/// on iOS every simulator build). Self-contained Foundation, for the Mac and
/// iOS alike.
public enum ScratchBuild {
  /// The Info.plist key a scratch build sets to `YES`.
  public static let infoPlistKey = "ScratchBuild"

  /// True in a scratch build, false in a real one.
  public static let isScratch = isSet(Bundle.main.object(forInfoDictionaryKey: infoPlistKey))

  /// Whether an Info.plist value says yes: a Boolean (`make-scratch-app.sh`
  /// writes one), or a string such as `YES` (a build setting substituted
  /// into the Info.plist). Anything else, absence included, is a real build.
  static func isSet(_ value: Any?) -> Bool {
    switch value {
    case let flag as Bool: flag
    case let text as String: (text as NSString).boolValue
    default: false
    }
  }
}

import Foundation
import Sharing

// What the app remembers between launches that is not data: view options and
// the like. User defaults, through Sharing's `appStorage`, so each is one line
// to declare and the model and a script see the same value.
//
// A `--scratch-database` run points `defaultAppStorage` at a suite of its own
// (`Entry`), so a script changing these never touches the real ones.

extension SharedKey where Self == AppStorageKey<Bool>.Default {
    static var showsDone: Self { Self[.appStorage("showsDone"), default: true] }
}

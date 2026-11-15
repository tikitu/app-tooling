import Foundation
import Sharing

// What the app remembers between launches that is not data: view options and
// the like. User defaults, through Sharing's `appStorage`, so each is one line
// to declare and the model and a script see the same value.
//
// The scratch build's are its own (its bundle id gives it its own container),
// so a script changing these never touches the real ones.

extension SharedKey where Self == AppStorageKey<Bool>.Default {
    static var showsDone: Self { Self[.appStorage("showsDone"), default: true] }
}

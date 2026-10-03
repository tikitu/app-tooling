# Applying privileged-helper

Read [`README.md`](README.md) first for what this does and why. The code
below is a shape to follow, not a file to copy whole: the names are the
examples', and the command is whatever the app runs as root.

## Detect

- **Already adopted:** `peru.yaml` imports `app-tooling|privileged-helper-docs`,
  and the package has a helper executable target whose plist is copied into
  `Contents/Library/LaunchDaemons` by `build.sh`.
- **Something else doing this job.** Look for:
  - `with administrator privileges` (AppleScript, `NSAppleScript`,
    `osascript`): the password dialog, which this pattern keeps as the
    fallback;
  - `SMJobBless`, `AuthorizationCreate` or `AuthorizationExecuteWithPrivileges`,
    or a helper in `Contents/Library/LaunchServices`: the older ways;
  - `sudo` in Swift or a script the app runs, or a file the project asks
    people to put in `/etc/sudoers.d`;
  - `SMAppService.daemon`, `NSXPCConnection(machServiceName:options: .privileged)`.

  If any exist, describe what the project does and what this pattern would
  do instead to the user, and ask, before changing anything.
- **Not adopted:** the app runs its command through the password dialog, or
  asks the person to run it in a terminal. That is the usual starting point.

Check too that the app is not sandboxed (`com.apple.security.app-sandbox` in
its entitlements). If it is, stop and ask: this has only been tried without
the sandbox.

## Parameters

| Parameter | Example | Where to find it |
|---|---|---|
| The app's bundle id | `com.example.myapp` | `BUNDLE_ID` in the Makefile, or `Resources/Info.plist` |
| The helper's label, Mach service and signing identifier | `com.example.myapp.helper` | the bundle id with `.helper`; one string for all three |
| The helper's executable name | `MyAppHelper` | the app's name with `Helper`; this is what Login Items shows |
| The command, and its one input | `/usr/bin/pmset -a disablesleep 0\|1`, a `Bool` | wherever the app runs it now, usually through the password dialog |
| The risky direction, if there is one | disabling sleep | ask the user; there may be none, and then there is no Touch ID |
| The installed path | `/Applications/MyApp.app` | the app's name |

## Steps

The project must already have `pattern-imports`: a `peru.yaml` with the
`app-tooling` module.

**1. Import the documents.** This pattern has no `files/`, so there is one
rule. In `peru.yaml`, under `imports:`:

```yaml
    app-tooling|privileged-helper-docs: docs/app-tooling/privileged-helper/
```

and beside the other rules:

```yaml
rule privileged-helper-docs:
    pick: [patterns/privileged-helper/README.md, patterns/privileged-helper/apply.md, patterns/privileged-helper/CHANGELOG.md]
    export: patterns/privileged-helper
```

Then `uvx peru@1.3.5 sync`.

**2. Two targets in the package**, beside the app's. The protocol is a
target of its own, Foundation only, so the helper links nothing else:

```swift
// What the app and its privileged helper say to each other over XPC.
.target(name: "HelperProtocol", swiftSettings: shared),
// The privileged helper: a launchd daemon, run as root (docs/design.md).
.executableTarget(
    name: "MyAppHelper", dependencies: ["HelperProtocol"], swiftSettings: shared),
```

and `"HelperProtocol"` in the dependencies of the target that talks to it.

**3. The protocol, and who may talk to whom.** One method, taking only what
the command needs. The requirement uses the process's own team, so both
sides agree without a team id in the source:

```swift
import Foundation
import Security

/// What the privileged helper does for the app, over XPC. Deliberately one
/// thing, and nothing else a caller could ask root for.
@objc
public protocol MyHelperProtocol {
    /// Runs the one command as root. Replies with `nil` on success, or what
    /// went wrong.
    func setEnabled(_ enabled: Bool, reply: @escaping @Sendable (String?) -> Void)
}

public enum MyHelper {
    /// The launchd label and the Mach service the helper listens on.
    public static let machServiceName = "com.example.myapp.helper"
    /// Its launchd plist, in the app's `Contents/Library/LaunchDaemons`.
    public static let plistName = "com.example.myapp.helper.plist"

    /// Who may connect to the helper: the app.
    public static var clientRequirement: String { requirement("com.example.myapp") }
    /// Who the app will talk to: the helper.
    public static var helperRequirement: String { requirement("com.example.myapp.helper") }

    /// Code signed with `identifier` and, when this process is signed with a
    /// Developer ID, with a Developer ID of the same team. Signed ad hoc, the
    /// identifier alone, which anything can claim: ad-hoc builds cannot
    /// register the helper (only `/Applications` can), so that is only ever
    /// a build talking to itself.
    static func requirement(_ identifier: String) -> String {
        guard let team = ownTeamID else { return #"identifier "\#(identifier)""# }
        // Apple's designated requirement for Developer ID code, with the team.
        return #"identifier "\#(identifier)" and anchor apple generic"#
            + #" and certificate 1[field.1.2.840.113635.100.6.2.6] exists"#
            + #" and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"#
            + #" and certificate leaf[subject.OU] = "\#(team)""#
    }

    /// The team this process is signed by; `nil` when signed ad hoc.
    static let ownTeamID: String? = {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var information: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
            SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
            SecCodeCopySigningInformation(
                staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information)
                == errSecSuccess
        else { return nil }
        return (information as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String
    }()
}
```

**4. The helper.** It checks the client's signature before accepting a
connection, runs the command by absolute path, and exits when idle:

```swift
import Foundation
import HelperProtocol
import OSLog

private let logger = Logger(subsystem: "com.example.myapp", category: "Helper")

final class Helper: NSObject, NSXPCListenerDelegate, MyHelperProtocol, @unchecked Sendable {
    /// Everything happens on this queue, so `requests` needs no lock.
    private let queue = DispatchQueue(label: "helper")
    private var requests = 0

    func listener(
        _ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection
    ) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: MyHelperProtocol.self)
        connection.exportedObject = self
        connection.resume()
        return true
    }

    func setEnabled(_ enabled: Bool, reply: @escaping @Sendable (String?) -> Void) {
        queue.async {
            let process = Process()
            process.executableURL = URL(filePath: "/usr/bin/the-command")
            process.arguments = ["--set", enabled ? "1" : "0"]
            let errors = Pipe()
            process.standardError = errors
            do {
                try process.run()
                let complaint = String(
                    decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    reply(nil)
                } else {
                    reply(complaint.isEmpty ? "exited with status \(process.terminationStatus)" : complaint)
                }
            } catch { reply("could not run the command: \(error)") }
            self.exitWhenIdle()
        }
    }

    /// Exits 10 seconds after the last request, or after launch if none
    /// comes, so a rebuilt helper is the one that runs next time.
    func exitWhenIdle() {
        queue.async {
            self.requests += 1
            let request = self.requests
            self.queue.asyncAfter(deadline: .now() + 10) { if request == self.requests { exit(0) } }
        }
    }
}

let helper = Helper()
let listener = NSXPCListener(machServiceName: MyHelper.machServiceName)
listener.setConnectionCodeSigningRequirement(MyHelper.clientRequirement)
listener.delegate = helper
listener.resume()
helper.exitWhenIdle()
dispatchMain()
```

**5. Its launchd plist**, as `Resources/com.example.myapp.helper.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<!--
	  The privileged helper's launchd plist, copied by build.sh into
	  Contents/Library/LaunchDaemons and registered by the app with
	  SMAppService.daemon(plistName:) (app-tooling: privileged-helper).
	-->
	<key>Label</key>
	<string>com.example.myapp.helper</string>
	<key>BundleProgram</key>
	<string>Contents/MacOS/MyAppHelper</string>
	<key>MachServices</key>
	<dict>
		<key>com.example.myapp.helper</key>
		<true/>
	</dict>
	<key>AssociatedBundleIdentifiers</key>
	<array>
		<string>com.example.myapp</string>
	</array>
</dict>
</plist>
```

**6. Bundle and sign it.** In `build.sh`, after the app's executable is
copied in:

```bash
# The privileged helper and its launchd plist (app-tooling: privileged-helper).
cp "$BIN_PATH/MyAppHelper" "$APP/Contents/MacOS/MyAppHelper"
mkdir -p "$APP/Contents/Library/LaunchDaemons"
cp Resources/com.example.myapp.helper.plist "$APP/Contents/Library/LaunchDaemons/"
```

and in its `codesign` section, before the app is signed:

```bash
# Inside out: the helper first, with its own identifier, then the app,
# whose signature seals it. The app checks that identifier.
codesign --force --sign "$SIGN_IDENTITY" --identifier com.example.myapp.helper \
	"$APP/Contents/MacOS/MyAppHelper"
```

In the Makefile's `sign` target, the same before the app's `codesign`,
with what notarizing needs:

```make
	@# Inside out: the helper first, then the app, whose signature seals it.
	@# Notarization refuses nested code without the Developer ID, the
	@# hardened runtime and a timestamp.
	codesign --force --options runtime --timestamp \
	  --identifier com.example.myapp.helper \
	  --sign "$(CERT_NAME)" "$(APP)/Contents/MacOS/MyAppHelper"
```

**7. `HelperClient`, a dependency.** Registering, removing and asking
about the helper, so scratch mode and the tests never touch a real daemon.
Its status is the app's own, because `SMAppService.Status` says too little
(the traps in `README.md`):

```swift
public enum HelperStatus: Equatable, Sendable {
    /// No record of it: registering makes macOS ask, the only time it will.
    case neverRegistered
    /// Not installed, but macOS remembers it: approval is in System Settings.
    case notRegistered
    /// Registered, waiting to be allowed in Login Items.
    case requiresApproval
    case enabled
    /// The helper or its plist is missing from the app bundle.
    case missingFromApp
    /// Not in `/Applications`, the only place it registers from.
    case notInApplications
    /// Running from a temporary copy (App Translocation).
    case translocated
}

public struct HelperClient: Sendable {
    public var status: @Sendable () -> HelperStatus
    public var register: @Sendable () throws -> Void
    public var unregister: @Sendable () async throws -> Void
    /// Opens System Settings at Login Items, where the helper is allowed.
    public var openSettings: @Sendable () -> Void
    /// What macOS says about the helper, in lines for a bug report.
    public var describe: @Sendable () -> [String]
}
```

The live value:

- `status`: if the app is not in `/Applications` and the service is
  `.notRegistered` or `.notFound`, `.translocated` when the bundle's path
  contains `/AppTranslocation/`, else `.notInApplications`. Otherwise map
  `SMAppService.daemon(plistName:).status`, with `.notFound` (and
  `@unknown default`) as `.neverRegistered` when both
  `Contents/MacOS/MyAppHelper` and the plist are in the bundle, else
  `.missingFromApp`.
- `register`: throws, saying to move the app, unless it is in
  `/Applications`; then `service.register()`.
- `unregister`: `try await service.unregister()`.
- `openSettings`: `SMAppService.openSystemSettingsLoginItems()`.
- `describe`: where the app runs from, the service's status by a name of
  your own, and the lines of `launchctl print system/<label>` containing
  `state =`, `program identifier`, `last exit`, `runs =`, `spawn type` or
  `Could not find`.

Compare paths with the trailing slash trimmed, and test that
`/Applications/MyApp.app/` counts:

```swift
static func isInApplications(_ bundleURL: URL) -> Bool { path(bundleURL) == path(installedURL) }

private static func path(_ url: URL) -> String {
    var path = url.standardizedFileURL.path(percentEncoded: false)
    while path.count > 1, path.hasSuffix("/") { path.removeLast() }
    return path
}
```

The test value reports an issue for every call not overridden. The scratch
value is a helper that registers at once, needing no approval:

```swift
public static func scratch() -> HelperClient {
    let status = Mutex(HelperStatus.neverRegistered)
    return HelperClient(
        status: { status.withLock { $0 } }, register: { status.withLock { $0 = .enabled } },
        unregister: { status.withLock { $0 = .notRegistered } }, openSettings: {},
        describe: { ["Scratch mode: a pretend helper, \(status.withLock { $0 })"] })
}
```

prepared in `Entry.main()` with scratch mode's other dependencies, before
anything reads the model (the starter's `docs/gotchas.md` says why).

**8. Calling it, with a deadline.** Over a privileged Mach connection,
checking the helper's signature, and giving up after five seconds. The
reply and the error handler can both be called, so the first one wins:

```swift
enum HelperConnection {
    /// launchd does not fail a connection to a helper it cannot start: it
    /// retries for ever (docs/gotchas.md).
    static let timeoutSeconds = 5

    static func setEnabled(_ enabled: Bool) async throws {
        let connection = NSXPCConnection(
            machServiceName: MyHelper.machServiceName, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: MyHelperProtocol.self)
        connection.setCodeSigningRequirement(MyHelper.helperRequirement)
        connection.resume()
        defer { connection.invalidate() }

        let answered = Mutex(false)
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, any Error>) in
            @Sendable
            func finish(_ error: String?) {
                guard
                    answered.withLock({ was in
                        defer { was = true };
                        return !was
                    })
                else { return }
                if let error {
                    continuation.resume(throwing: MyError.failed(error))
                } else {
                    continuation.resume()
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(timeoutSeconds)) {
                finish("The helper did not answer. Remove the helper, then install it again.")
            }
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                finish("could not reach the helper: \(error.localizedDescription)")
            }
            guard let helper = proxy as? MyHelperProtocol else {
                return finish("the helper does not speak MyHelperProtocol")
            }
            helper.setEnabled(enabled) { finish($0) }
        }
    }
}
```

Where the app ran the command through the password dialog, it now uses
the helper when `status()` is `.enabled`, and the dialog otherwise.

**9. The owner check, for the risky direction only.** Skip this step if
the user said there is none:

```swift
/// Touch ID (or the password, where there is none) before the risky
/// direction, remembered for five minutes. The other direction asks
/// nothing. A guard against accidents, not a security boundary: it is in
/// the app, not the helper.
enum OwnerCheck {
    static let reuse = Duration.seconds(5 * 60)
    private static let lastPassed = Mutex<ContinuousClock.Instant?>(nil)

    static func confirm(_ reason: String) async throws {
        if let last = lastPassed.withLock({ $0 }), ContinuousClock.now - last < reuse { return }
        let context = LAContext()
        do {
            try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch let error as LAError
            where error.code == .userCancel || error.code == .appCancel
            || error.code == .systemCancel
        { throw MyError.cancelled } catch {
            throw MyError.failed("could not confirm it is you: \(error.localizedDescription)")
        }
        lastPassed.withLock { $0 = .now }
    }
}
```

`reason` finishes the sentence "MyApp is trying to …". A cancel is not an
error: nothing changes and nothing is shown.

**10. The model and the command inbox become async.** `perform(_:)`,
`attempt(_:)`, `CommandInbox.processInbox()` and `CommandInbox.run(_:on:)`
all gain `async`; the Darwin notification's callback becomes
`Task { @MainActor in await CommandInbox.shared.processInbox() }`. Two
things change with it:

- **The inbox file is removed before its commands run**, not after, and
  if it cannot be removed they are not run: while one file's commands wait
  for Touch ID, a second notification would otherwise run them again.
- **One change at a time.** A `isChanging` flag on the model, and a
  `CommandError.busy` thrown while it is set. `attempt` logs `busy` and
  shows nothing: a second click while Touch ID is up is ignored, not
  queued.

**11. Three commands**, each with its row in `docs/commands.md` and its
case in the decoder:

| Command | Does |
|---|---|
| `installHelper` | Registers the helper. The first time, macOS asks; after that, Login Items is opened instead. In scratch mode, a pretend helper, enabled at once |
| `removeHelper` | Unregisters it: the command asks for the password again |
| `openLoginItems` | Opens System Settings at Login Items, to allow it |

`installHelper` is where two traps meet:

```swift
case .installHelper:
    // macOS asks "App Background Activity … Do you want to allow this?"
    // only the first time; after that the approval is in System Settings.
    let asks = helperClient.status() == .neverRegistered
    // Until it is allowed, `register()` throws "Operation not permitted",
    // having registered it. The status says which it was.
    do { try helperClient.register() } catch {
        helperStatus = helperClient.status()
        guard helperStatus == .requiresApproval else { throw error }
    }
    helperStatus = helperClient.status()
    if helperStatus == .requiresApproval, !asks { helperClient.openSettings() }
    return "helper: \(helperStatus)"
```

Ask for the status when the menu or window that shows it opens, not on
every poll: each ask is a round trip to Background Task Management. Show
the person, in words, what the status means and the one thing they can do
about it (install, open Login Items, remove, or move the app to
Applications).

**12. Documents.** In the project's own:

- `docs/gotchas.md`: the traps in `README.md` that the code now avoids,
  each naming the code that avoids it, so that nobody "simplifies" it.
- `docs/design.md` (or wherever the command is described): the helper,
  what it runs and nothing else, who it accepts, that it registers only
  from `/Applications`, and the owner check, saying plainly that it guards
  against accidents and is not a security boundary.
- `AGENTS.md`: that scripts and agents never register, remove or call the
  real helper, and never allow it in System Settings: that is for the
  person at the keyboard. Scratch mode's pretend helper is what they use.

**13. Record it** in `app-tooling.toml`:

```toml
[patterns.privileged-helper]
params = { label = "com.example.myapp.helper", command = "/usr/bin/the-command" }
```

with a `deviations` line for anything left out on purpose (no owner check
because there is no risky direction, say).

## Verify

Run each and compare with the expected output. The person, not an agent,
installs and allows the real helper, and runs the command through it.

- **The bundle.** After `make build`:

  ```sh
  ls build/MyApp.app/Contents/MacOS build/MyApp.app/Contents/Library/LaunchDaemons
  codesign -dv build/MyApp.app/Contents/MacOS/MyAppHelper 2>&1 | grep Identifier
  codesign --verify --strict --verbose=2 build/MyApp.app
  ```

  lists both executables and the plist; says
  `Identifier=com.example.myapp.helper`, not the app's identifier or the
  file name; and ends `valid on disk` and `satisfies its Designated
  Requirement`.
- **Scratch mode.** `make run-scratch`, then through
  `scripts/send-commands.sh`: `installHelper` reports `helper: enabled`,
  the command in each direction completes, and `removeHelper` reports
  `helper: notRegistered`. No prompt appears.
- **Tests.** `make test`, with tests for the path comparison (with and
  without the slash, and a translocated path), for `installHelper` when
  `register()` throws and the status is `.requiresApproval` (it succeeds)
  and when it is anything else (it throws), and for `busy`.
- **Release build.** After `make sign`, the same `codesign -dv` on the
  helper shows `TeamIdentifier=` the team, and `codesign -d -r-` on both
  shows the Developer ID requirement.
- **The real helper, by the person.** With a signed build in
  `/Applications`: they install it from the app, and allow it in Login
  Items. Then `launchctl print system/com.example.myapp.helper` shows the
  job; running the command through the app shows Touch ID for the risky
  direction only; and
  `/usr/bin/log show --last 5m --predicate 'subsystem == "com.example.myapp"'`
  shows the helper's lines. (`/usr/bin/log`: in zsh, `log` is a builtin
  that prints nothing.) The app's copied bug report names the status as
  `enabled`.
- **The deadline.** Not reproducible on purpose. If a switch ever says the
  helper did not answer, `launchctl print` in the bug report says why.

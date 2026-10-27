// inset-lint: find `.safeAreaInset` / `.safeAreaBar` attached to a view whose
// content reaches an HSplitView, VSplitView or NavigationSplitView, following
// view type names across every Swift file under the given roots.
//
// Names, not types: a type is identified by its simple name, extensions merge
// into it, and two types with the same name in different modules are merged.

import Foundation
import SwiftParser
import SwiftSyntax

/// `.inspector` is listed too: on macOS it is a split view, and drops the inset
/// the same way (checked at runtime).
let splitNames: Set<String> = ["HSplitView", "VSplitView", "NavigationSplitView", ".inspector"]
let insetNames: Set<String> = ["safeAreaInset", "safeAreaBar"]
/// Modifiers whose closures are not laid out inside the modified view: their
/// content is presented elsewhere (sheet, popover, menu) or is an action.
let detachedModifiers: Set<String> = [
    "sheet", "popover", "fullScreenCover", "alert", "confirmationDialog", "contextMenu",
    "toolbar", "help", "onAppear", "onDisappear", "task", "onChange",
    "onReceive", "onTapGesture", "onSubmit", "onKeyPress", "dropDestination", "onDrop",
    "fileImporter", "fileExporter", "focusedSceneValue", "searchSuggestions", "dialogSuppressionToggle",
]
let skipDirs: Set<String> = [".build", "DerivedData", ".git", "peru", "vendor", "Vendor", "Pods", "Carthage", ".swiftpm", "checkouts", "node_modules"]

// MARK: - Arguments

var roots: [String] = []
var verbose = false
for arg in CommandLine.arguments.dropFirst() {
    if arg == "-v" || arg == "--verbose" { verbose = true } else { roots.append(arg) }
}
if roots.isEmpty {
    FileHandle.standardError.write("usage: inset-lint [-v] <root>...\n".data(using: .utf8)!)
    exit(2)
}

func swiftFiles(under root: String) -> [String] {
    let fm = FileManager.default
    var isDir: ObjCBool = false
    guard fm.fileExists(atPath: root, isDirectory: &isDir) else { return [] }
    if !isDir.boolValue { return root.hasSuffix(".swift") ? [root] : [] }
    var out: [String] = []
    let url = URL(fileURLWithPath: root)
    guard let e = fm.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
    for case let u as URL in e {
        if (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            if skipDirs.contains(u.lastPathComponent) { e.skipDescendants() }
            continue
        }
        if u.pathExtension == "swift" { out.append(u.path) }
    }
    return out.sorted()
}

struct SourceFile {
    let path: String
    let tree: SourceFileSyntax
    let converter: SourceLocationConverter
    func line(_ n: some SyntaxProtocol) -> Int {
        converter.location(for: n.positionAfterSkippingLeadingTrivia).line
    }
}

let files: [SourceFile] = roots.flatMap(swiftFiles(under:)).map { path in
    let text = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    let tree = Parser.parse(source: text)
    return SourceFile(path: path, tree: tree, converter: SourceLocationConverter(fileName: path, tree: tree))
}

// MARK: - Helpers

func simpleTypeName(_ t: TypeSyntax) -> String {
    var s = t.trimmedDescription
    if let i = s.firstIndex(of: "<") { s = String(s[..<i]) }
    return String(s.split(separator: ".").last ?? Substring(s))
}

func typeName(of decl: some SyntaxProtocol) -> String? {
    if let d = decl.as(StructDeclSyntax.self) { return d.name.text }
    if let d = decl.as(ClassDeclSyntax.self) { return d.name.text }
    if let d = decl.as(EnumDeclSyntax.self) { return d.name.text }
    if let d = decl.as(ActorDeclSyntax.self) { return d.name.text }
    if let d = decl.as(ExtensionDeclSyntax.self) { return simpleTypeName(d.extendedType) }
    return nil
}

func enclosingType(_ node: Syntax) -> String? {
    var p = node.parent
    while let n = p {
        if let name = typeName(of: n) { return name }
        p = n.parent
    }
    return nil
}

/// The member (computed var or func) a node sits in, if any.
func enclosingMember(_ node: Syntax) -> (name: String, decl: Syntax)? {
    var p = node.parent
    while let n = p {
        if let f = n.as(FunctionDeclSyntax.self) { return (f.name.text, n) }
        if let v = n.as(VariableDeclSyntax.self),
            let id = v.bindings.first?.pattern.as(IdentifierPatternSyntax.self)
        {
            return (id.identifier.text, n)
        }
        if typeName(of: n) != nil { return nil }
        p = n.parent
    }
    return nil
}

func isExtensionOfView(_ node: Syntax) -> Bool {
    var p = node.parent
    while let n = p {
        if let e = n.as(ExtensionDeclSyntax.self) { return simpleTypeName(e.extendedType) == "View" }
        if typeName(of: n) != nil { return false }
        p = n.parent
    }
    return false
}

func hasViewBuilder(_ attrs: AttributeListSyntax) -> Bool {
    attrs.contains { $0.as(AttributeSyntax.self)?.attributeName.trimmedDescription == "ViewBuilder" }
}

func looksLikeView(_ t: TypeSyntax?) -> Bool {
    guard let s = t?.trimmedDescription else { return false }
    return s.contains("View") || s.contains("Scene") || s.contains("Content")
}

func isUpper(_ s: String) -> Bool { s.first.map { $0.isUppercase } ?? false }

// MARK: - Pass 1: declarations

final class TypeInfo {
    var viewMembers: [String: [Syntax]] = [:]  // member name -> decl(s); "body" included
    var storedViews: [String: String] = [:]  // stored prop -> declared type
    var storedTyped: [String: String] = [:]  // stored prop -> simple type name, resolved in pass 2
    var genericParams: Set<String> = []
    var isViewModifier = false
    var files: Set<String> = []
}
var types: [String: TypeInfo] = [:]

final class DeclCollector: SyntaxVisitor {
    let file: String
    init(file: String) {
        self.file = file
        super.init(viewMode: .sourceAccurate)
    }
    func info(_ n: some SyntaxProtocol) -> TypeInfo? {
        guard let name = typeName(of: n) else { return nil }
        let t = types[name] ?? TypeInfo()
        types[name] = t
        t.files.insert(file)
        return t
    }
    func record(_ t: TypeInfo, members: MemberBlockItemListSyntax, generics: GenericParameterClauseSyntax?, inherits: InheritanceClauseSyntax?) {
        for g in generics?.parameters ?? [] { t.genericParams.insert(g.name.text) }
        if inherits?.inheritedTypes.contains(where: { simpleTypeName($0.type) == "ViewModifier" }) == true {
            t.isViewModifier = true
        }
        for item in members {
            if let f = item.decl.as(FunctionDeclSyntax.self) {
                if f.name.text == "body" || looksLikeView(f.signature.returnClause?.type) || hasViewBuilder(f.attributes) {
                    t.viewMembers[f.name.text, default: []].append(Syntax(f))
                }
            } else if let v = item.decl.as(VariableDeclSyntax.self) {
                for b in v.bindings {
                    guard let id = b.pattern.as(IdentifierPatternSyntax.self) else { continue }
                    let name = id.identifier.text
                    let type = b.typeAnnotation?.type
                    let computed = b.accessorBlock.map { block -> Bool in
                        if case .accessors(let list) = block.accessors {
                            return list.contains { $0.accessorSpecifier.text == "get" }
                        }
                        return true
                    } ?? false
                    if computed {
                        if name == "body" || looksLikeView(type) || hasViewBuilder(v.attributes) {
                            t.viewMembers[name, default: []].append(Syntax(v))
                        }
                    } else if let type {
                        let s = type.trimmedDescription
                        let generic = t.genericParams.contains { g in
                            s == g || s.hasSuffix("-> \(g)") || s.hasSuffix("->\(g)")
                        }
                        if generic || s.contains("AnyView") || s.contains("any View") || hasViewBuilder(v.attributes) {
                            t.storedViews[name] = s
                        } else {
                            t.storedTyped[name] = simpleTypeName(type)
                        }
                    } else if b.initializer != nil, v.bindingSpecifier.text == "let" || v.bindingSpecifier.text == "var",
                        let initr = b.initializer, isUpper(initr.value.as(FunctionCallExprSyntax.self)?.calledExpression.trimmedDescription ?? "")
                    {
                        // `let panes = Panes()` stored with an initial value: treat like a member.
                        t.viewMembers[name, default: []].append(Syntax(v))
                    }
                }
            }
        }
    }
    override func visit(_ n: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        if let t = info(n) { record(t, members: n.memberBlock.members, generics: n.genericParameterClause, inherits: n.inheritanceClause) }
        return .visitChildren
    }
    override func visit(_ n: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        if let t = info(n) { record(t, members: n.memberBlock.members, generics: n.genericParameterClause, inherits: n.inheritanceClause) }
        return .visitChildren
    }
    override func visit(_ n: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        if let t = info(n) { record(t, members: n.memberBlock.members, generics: n.genericParameterClause, inherits: n.inheritanceClause) }
        return .visitChildren
    }
    override func visit(_ n: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        if let t = info(n) { record(t, members: n.memberBlock.members, generics: nil, inherits: n.inheritanceClause) }
        return .visitChildren
    }
}
for f in files { DeclCollector(file: f.path).walk(f.tree) }

// MARK: - References

struct Edge: Hashable {
    let target: String  // "Type", "Type.member", "Type#callers" or a split view name
}

/// Collects the view names an expression or member body refers to.
final class RefCollector: SyntaxVisitor {
    let ctx: String?
    let resolveStored: Bool
    var edges: [Edge] = []
    var unresolvedLower: Set<String> = []
    var external: Set<String> = []
    var stored: Set<String> = []
    init(ctx: String?, resolveStored: Bool) {
        self.ctx = ctx
        self.resolveStored = resolveStored
        super.init(viewMode: .sourceAccurate)
    }
    func upper(_ name: String) {
        if splitNames.contains(name) || types[name] != nil {
            edges.append(Edge(target: name))
        } else {
            external.insert(name)
        }
    }
    func lower(_ name: String, in type: String?) {
        guard let type, let t = types[type] else { unresolvedLower.insert(name); return }
        if t.viewMembers[name] != nil {
            edges.append(Edge(target: name == "body" ? type : "\(type).\(name)"))
        } else if let st = t.storedTyped[name], types[st] != nil || splitNames.contains(st) {
            edges.append(Edge(target: st))  // `let detail: DetailView`, constructed elsewhere
        } else if t.storedViews[name] != nil {
            stored.insert("\(type).\(name)")
            if resolveStored { edges.append(Edge(target: "\(type)#callers")) }
        } else {
            unresolvedLower.insert(name)
        }
    }
    override func visit(_ n: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        if let m = n.calledExpression.as(MemberAccessExprSyntax.self), m.declName.baseName.text == "inspector" {
            edges.append(Edge(target: ".inspector"))
            if let base = m.base { walk(base) }
            return .skipChildren
        }
        if let m = n.calledExpression.as(MemberAccessExprSyntax.self), detachedModifiers.contains(m.declName.baseName.text) {
            if let base = m.base { walk(base) }
            return .skipChildren
        }
        return .visitChildren
    }
    override func visit(_ n: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        let member = n.declName.baseName.text
        if let base = n.base?.as(DeclReferenceExprSyntax.self) {
            let b = base.baseName.text
            if b == "self" || b == "Self" { lower(member, in: ctx); return .skipChildren }
            if isUpper(b), let t = types[b], t.viewMembers[member] != nil {
                edges.append(Edge(target: "\(b).\(member)"))
                return .skipChildren
            }
        }
        if let base = n.base { walk(base) }
        return .skipChildren  // never treat `.padding` etc. as a name
    }
    override func visit(_ n: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        let name = n.baseName.text
        if isUpper(name) { upper(name) } else { lower(name, in: ctx) }
        return .skipChildren
    }
    override func visit(_ n: IdentifierTypeSyntax) -> SyntaxVisitorContinueKind {
        let name = n.name.text
        if splitNames.contains(name) || types[name] != nil { edges.append(Edge(target: name)) }
        return .visitChildren
    }
    override func visit(_ n: ClosureParameterClauseSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
}

/// The part of a member declaration that produces its view.
func memberBodies(_ decl: Syntax) -> [Syntax] {
    if let f = decl.as(FunctionDeclSyntax.self) { return f.body.map { [Syntax($0)] } ?? [] }
    if let v = decl.as(VariableDeclSyntax.self) {
        return v.bindings.compactMap { b in b.accessorBlock.map(Syntax.init) ?? b.initializer.map(Syntax.init) }
    }
    return []
}

// MARK: - Pass 2: graph

var graph: [String: Set<String>] = [:]
var storedRefs: [String: Set<String>] = [:]  // node -> stored props it shows (blind spots)
var externalRefs: [String: Set<String>] = [:]

for (name, t) in types {
    for (member, decls) in t.viewMembers {
        let node = member == "body" ? name : "\(name).\(member)"
        for d in decls {
            for b in memberBodies(d) {
                let c = RefCollector(ctx: name, resolveStored: false)
                c.walk(b)
                graph[node, default: []].formUnion(c.edges.map(\.target))
                storedRefs[node, default: []].formUnion(c.stored)
                externalRefs[node, default: []].formUnion(c.external)
            }
        }
    }
}

/// Every place a type is constructed, `Name(...)` or `Name { }`: what is passed
/// in is what its stored content properties show.
final class CallSiteCollector: SyntaxVisitor {
    init() { super.init(viewMode: .sourceAccurate) }
    override func visit(_ n: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        var callee: String?
        if let d = n.calledExpression.as(DeclReferenceExprSyntax.self) { callee = d.baseName.text }
        if let s = n.calledExpression.as(GenericSpecializationExprSyntax.self)?.expression.as(DeclReferenceExprSyntax.self) {
            callee = s.baseName.text
        }
        if let callee, let t = types[callee], !t.storedViews.isEmpty {
            let c = RefCollector(ctx: enclosingType(Syntax(n)), resolveStored: false)
            c.walk(n.arguments)
            if let tc = n.trailingClosure { c.walk(tc) }
            c.walk(n.additionalTrailingClosures)
            graph["\(callee)#callers", default: []].formUnion(c.edges.map(\.target))
        }
        return .visitChildren
    }
}
for f in files { CallSiteCollector().walk(f.tree) }

// MARK: - Inset sites

/// Inset-like modifiers: the SwiftUI ones, plus `extension View` funcs and
/// ViewModifiers that apply one to the view they are given.
var insetFuncs = insetNames
var insetModifiers: Set<String> = []

struct Site {
    let file: SourceFile
    let call: FunctionCallExprSyntax
    let via: String  // the modifier as written at the site
}

final class SiteFinder: SyntaxVisitor {
    let file: SourceFile
    var sites: [Site] = []
    var newFuncs: Set<String> = []
    var newModifiers: Set<String> = []
    init(file: SourceFile) {
        self.file = file
        super.init(viewMode: .sourceAccurate)
    }
    override func visit(_ n: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        var via: String?
        let m = n.calledExpression.as(MemberAccessExprSyntax.self)
        let d = n.calledExpression.as(DeclReferenceExprSyntax.self)
        let name = m?.declName.baseName.text ?? d?.baseName.text
        if let name, insetFuncs.contains(name) { via = name }
        if name == "modifier", let arg = n.arguments.first?.expression.as(FunctionCallExprSyntax.self),
            let mod = arg.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text, insetModifiers.contains(mod)
        {
            via = "modifier(\(mod))"
        }
        guard let via else { return .visitChildren }
        let baseText = m?.base?.trimmedDescription
        if baseText == nil || baseText == "self" {
            // Applied to whatever view the enclosing `extension View` func is called on.
            if isExtensionOfView(Syntax(n)), let f = enclosingMember(Syntax(n)), !insetFuncs.contains(f.name) {
                newFuncs.insert(f.name)
            }
        } else if baseText == "content", let ty = enclosingType(Syntax(n)), types[ty]?.isViewModifier == true {
            if !insetModifiers.contains(ty) { newModifiers.insert(ty) }
        } else {
            sites.append(Site(file: file, call: n, via: via))
        }
        return .visitChildren
    }
}

var sites: [Site] = []
while true {
    sites = []
    var nf: Set<String> = []
    var nm: Set<String> = []
    for f in files {
        let s = SiteFinder(file: f)
        s.walk(f.tree)
        sites += s.sites
        nf.formUnion(s.newFuncs)
        nm.formUnion(s.newModifiers)
    }
    if nf.isEmpty && nm.isEmpty { break }
    insetFuncs.formUnion(nf)
    insetModifiers.formUnion(nm)
}

/// Local `let x = ...` declarations visible from a node, by name.
func localInitializers(named name: String, above node: Syntax) -> [Syntax] {
    var out: [Syntax] = []
    var p = node.parent
    while let n = p {
        if let list = n.as(CodeBlockItemListSyntax.self) {
            for item in list {
                guard let v = item.item.as(VariableDeclSyntax.self) else { continue }
                for b in v.bindings where b.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == name {
                    if let i = b.initializer { out.append(Syntax(i)) }
                }
            }
        }
        if typeName(of: n) != nil { break }
        p = n.parent
    }
    return out
}

func chain(from start: [String]) -> [String]? {
    var parent: [String: String] = [:]
    var queue = start
    var seen = Set(start)
    var i = 0
    while i < queue.count {
        let n = queue[i]
        i += 1
        if splitNames.contains(n) {
            var path = [n]
            var c = n
            while let p = parent[c] { path.append(p); c = p }
            return path.reversed()
        }
        for next in (graph[n] ?? []).sorted() where !seen.contains(next) {
            seen.insert(next)
            parent[next] = n
            queue.append(next)
        }
    }
    return nil
}

func reachable(from start: [String]) -> Set<String> {
    var seen = Set(start)
    var queue = start
    while let n = queue.popLast() {
        for next in graph[n] ?? [] where seen.insert(next).inserted { queue.append(next) }
    }
    return seen
}

var flagged = 0
for site in sites.sorted(by: { ($0.file.path, $0.file.line($0.call)) < ($1.file.path, $1.file.line($1.call)) }) {
    let n = Syntax(site.call)
    let ctx = enclosingType(n)
    let member = enclosingMember(n)?.name
    let here = [ctx, member == "body" ? nil : member].compactMap { $0 }.joined(separator: ".")
    guard let base = site.call.calledExpression.as(MemberAccessExprSyntax.self)?.base else { continue }
    let c = RefCollector(ctx: ctx, resolveStored: true)
    c.walk(base)
    for name in c.unresolvedLower {
        for i in localInitializers(named: name, above: n) { c.walk(i) }
    }
    let start = "(\(here.isEmpty ? "top level" : here): \(base.trimmedDescription.prefix(1) == "." ? "" : "receiver"))"
    graph[start] = Set(c.edges.map(\.target))
    let mark: Syntax = site.call.calledExpression.as(MemberAccessExprSyntax.self).map { Syntax($0.declName) } ?? n
    let line = site.file.line(mark)
    if let path = chain(from: [start]) {
        flagged += 1
        var shown = path
        shown[0] = here.isEmpty ? "(top level)" : here
        print("\(site.file.path):\(line): .\(site.via) over a split view: \(shown.joined(separator: " → "))")
    } else if verbose {
        print("\(site.file.path):\(line): .\(site.via) ok (\(here))")
    }
    if verbose {
        let reach = reachable(from: [start])
        let blind = Set(reach.flatMap { storedRefs[$0] ?? [] }).union(c.stored)
        let ext = Set(reach.flatMap { externalRefs[$0] ?? [] }).union(c.external)
        if !blind.isEmpty { print("    stored content seen only through call sites: \(blind.sorted().joined(separator: ", "))") }
        if !ext.isEmpty { print("    names not defined here (SDK or other repos): \(ext.sorted().joined(separator: ", "))") }
    }
}
if verbose {
    print("\(files.count) files, \(types.count) types, \(sites.count) inset sites, \(flagged) flagged; inset-like: \(insetFuncs.subtracting(insetNames).sorted() + insetModifiers.sorted())")
}
exit(flagged > 0 ? 1 : 0)

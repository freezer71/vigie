import Darwin
import Foundation

/// Pastille dessinée pour les outils sans icône d'app (Node.js, Next.js, Python…).
struct RuntimeBadge: Sendable, Hashable {
    enum Shape: Sendable, Hashable { case circle, hexagon, rounded }
    let text: String
    let background: UInt32
    let foreground: UInt32
    let shape: Shape

    static let node = RuntimeBadge(text: "JS", background: 0x5FA04E, foreground: 0xFFFFFF, shape: .hexagon)
    static let next = RuntimeBadge(text: "N", background: 0x000000, foreground: 0xFFFFFF, shape: .circle)
    static let vite = RuntimeBadge(text: "V", background: 0x646CFF, foreground: 0xFFFFFF, shape: .rounded)
    static let typescript = RuntimeBadge(text: "TS", background: 0x3178C6, foreground: 0xFFFFFF, shape: .rounded)
    static let firebase = RuntimeBadge(text: "F", background: 0xFFA000, foreground: 0xFFFFFF, shape: .rounded)
    static let playwright = RuntimeBadge(text: "Pw", background: 0x2EAD33, foreground: 0xFFFFFF, shape: .rounded)
    static let eslint = RuntimeBadge(text: "ES", background: 0x4B32C3, foreground: 0xFFFFFF, shape: .hexagon)
    static let vitest = RuntimeBadge(text: "Vt", background: 0x6E9F18, foreground: 0xFFFFFF, shape: .rounded)
    static let nest = RuntimeBadge(text: "Ne", background: 0xE0234E, foreground: 0xFFFFFF, shape: .rounded)
    static let prisma = RuntimeBadge(text: "Pr", background: 0x2D3748, foreground: 0xFFFFFF, shape: .rounded)
    static let mcp = RuntimeBadge(text: "MCP", background: 0x3A3A3C, foreground: 0xFFFFFF, shape: .rounded)
    static let npm = RuntimeBadge(text: "npm", background: 0xCB3837, foreground: 0xFFFFFF, shape: .rounded)
    static let pnpm = RuntimeBadge(text: "pn", background: 0xF69220, foreground: 0xFFFFFF, shape: .rounded)
    static let bun = RuntimeBadge(text: "B", background: 0xFBF0DF, foreground: 0x14151A, shape: .circle)
    static let deno = RuntimeBadge(text: "D", background: 0x000000, foreground: 0xFFFFFF, shape: .circle)
    static let python = RuntimeBadge(text: "Py", background: 0x3776AB, foreground: 0xFFD43B, shape: .rounded)
    static let django = RuntimeBadge(text: "dj", background: 0x0C4B33, foreground: 0xFFFFFF, shape: .rounded)
    static let ruby = RuntimeBadge(text: "Rb", background: 0xCC342D, foreground: 0xFFFFFF, shape: .rounded)
    static let java = RuntimeBadge(text: "J", background: 0xE76F00, foreground: 0xFFFFFF, shape: .rounded)
    static let claude = RuntimeBadge(text: "✳", background: 0xD97757, foreground: 0xFFFFFF, shape: .rounded)
}

enum ProcessIcon: Sendable, Hashable {
    /// Icône du Finder pour ce chemin (bundle .app ou exécutable).
    case file(String?)
    case badge(RuntimeBadge)
}

struct ProcessDescription: Sendable {
    var title: String
    /// Répertoire de travail lisible (« ~/Workspace/govo », worktree mis en évidence).
    var detail: String?
    var cwd: String?
    var icon: ProcessIcon
}

/// Donne un nom parlant aux processus d'outils de dev (node, python, binaires versionnés…).
enum ProcessIdentifier {
    private static let home = NSHomeDirectory()
    private static let argMax: Int = {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname("kern.argmax", &value, &size, nil, 0) == 0 ? Int(value) : 262_144
    }()
    private static let claudeApp = FileManager.default.fileExists(atPath: "/Applications/Claude.app") ? "/Applications/Claude.app" : nil

    static func describe(pid: pid_t, name: String, path: String) -> ProcessDescription {
        let cwd = workingDirectory(pid: pid)
        var result = ProcessDescription(title: name, detail: cwd.flatMap(projectLabel), cwd: cwd, icon: .file(path))
        let args = arguments(pid: pid)
        let argv0 = args.first ?? name
        let lower = name.lowercased()

        // Claude Code : binaire nommé d'après sa version (~/.local/share/claude/versions/2.1.316).
        if path.contains("/claude/versions/") || lower == "claude" {
            result.title = "Claude Code"
            result.icon = claudeApp.map { .file($0) } ?? .badge(.claude)
            return result
        }

        if lower == "node" || lower == "bun" || lower == "deno" || argv0.hasPrefix("next-") {
            describeJavaScript(argv0: argv0, args: args, runtime: lower, into: &result)
        } else if lower.hasPrefix("python") {
            describePython(args: args, into: &result)
        } else if lower == "ruby" {
            result.icon = .badge(.ruby)
            if let script = firstScript(args) { result.title = "ruby \((script as NSString).lastPathComponent)" }
        } else if lower == "java" {
            result.icon = .badge(.java)
        } else if name.allSatisfy({ $0.isNumber || $0 == "." }), !name.isEmpty {
            // Autre binaire nommé par sa version : on prend le dossier parent (…/outil/versions/1.2.3).
            let parts = path.split(separator: "/").map(String.init)
            if let i = parts.lastIndex(of: "versions"), i > 0 { result.title = "\(parts[i - 1]) \(name)" }
        }
        return result
    }

    // MARK: JavaScript

    private static func describeJavaScript(argv0: String, args: [String], runtime: String, into r: inout ProcessDescription) {
        r.icon = .badge(runtime == "bun" ? .bun : runtime == "deno" ? .deno : .node)

        // Next.js renomme son processus serveur : « next-server (v16.4.2) ».
        if argv0.hasPrefix("next-server") || argv0.hasPrefix("next-router") || argv0.hasPrefix("next-render") {
            r.title = "Serveur Next.js"
            r.icon = .badge(.next)
            return
        }

        // npm / pnpm / yarn réécrivent aussi leur titre : « npm exec firebase-tools mcp --dir . ».
        let words = args.joined(separator: " ").split(separator: " ").map(String.init)
        if let tool = words.first, ["npm", "npx", "pnpm", "yarn"].contains(tool) {
            r.title = words.prefix { !$0.hasPrefix("-") }.prefix(3).joined(separator: " ")
            r.icon = .badge(tool == "pnpm" ? .pnpm : .npm)
            return
        }

        guard let script = firstScript(args) else { return }
        let rest = arguments(after: script, in: args)
        let port = port(in: rest).map { " :\($0)" } ?? ""

        if script.contains("/.next/") {
            r.title = "Worker Next.js"
            r.icon = .badge(.next)
            return
        }
        if script.contains("/npm/bin/npm-cli") || script.hasSuffix("/bin/npm") {
            r.title = (["npm"] + rest.prefix(2)).joined(separator: " ")
            r.icon = .badge(.npm)
            return
        }
        if script.contains("/npm/bin/npx-cli") || script.hasSuffix("/bin/npx") {
            r.title = (["npx"] + rest.prefix(2)).joined(separator: " ")
            r.icon = .badge(.npm)
            return
        }
        if script.contains("/pnpm/") || script.hasSuffix("/bin/pnpm") {
            r.title = (["pnpm"] + rest.prefix(2)).joined(separator: " ")
            r.icon = .badge(.pnpm)
            return
        }

        if let package = packageName(fromScript: script) {
            let command = rest.first { !$0.hasPrefix("-") && $0.count < 20 && !$0.contains("/") && Int($0) == nil }
            let (label, badge) = known(package: package, script: script)
            r.title = [label, command].compactMap { $0 }.joined(separator: " ") + port
            if let badge { r.icon = .badge(badge) }
            return
        }

        // Script du projet : « node mcp/server.mjs ».
        let file = (script as NSString).lastPathComponent
        let folder = ((script as NSString).deletingLastPathComponent as NSString).lastPathComponent
        r.title = "\(runtime) " + (["", ".", "src", "dist", "bin", "lib"].contains(folder) ? file : "\(folder)/\(file)") + port
        if script.lowercased().contains("mcp") { r.icon = .badge(.mcp) }
    }

    private static func known(package: String, script: String) -> (String, RuntimeBadge?) {
        switch package {
        case "next": return ("Next.js", .next)
        case "vite": return ("Vite", .vite)
        case "typescript", "tsc", "tsserver":
            return (script.contains("tsserver") ? "Serveur TypeScript" : "TypeScript", .typescript)
        case "firebase", "firebase-tools": return ("Firebase", .firebase)
        case "playwright", "playwright-core", "@playwright/test", "@playwright/mcp": return ("Playwright", .playwright)
        case "eslint", "eslint_d": return ("ESLint", .eslint)
        case "vitest": return ("Vitest", .vitest)
        case "jest": return ("Jest", nil)
        case "@nestjs/cli", "nest": return ("NestJS", .nest)
        case "prisma", "@prisma/client": return ("Prisma", .prisma)
        case "tsx", "ts-node": return (package, .typescript)
        case "turbo": return ("Turborepo", nil)
        default:
            if package.hasPrefix("@modelcontextprotocol/") || package.contains("mcp") { return (package, .mcp) }
            return (package, nil)
        }
    }

    // MARK: Python

    private static func describePython(args: [String], into r: inout ProcessDescription) {
        r.icon = .badge(.python)
        if let m = args.firstIndex(of: "-m"), m + 1 < args.count {
            let module = args[m + 1]
            r.title = "python -m \(module)"
            if ["uvicorn", "gunicorn", "flask", "streamlit", "jupyter", "http.server"].contains(module) { r.title = module }
            return
        }
        guard let script = firstScript(args) else { return }
        let file = (script as NSString).lastPathComponent
        if file == "manage.py" {
            r.title = (["Django"] + arguments(after: script, in: args).prefix(1)).joined(separator: " ")
            r.icon = .badge(.django)
        } else if ["uvicorn", "gunicorn", "flask", "streamlit", "jupyter", "jupyter-lab", "celery"].contains(file) {
            r.title = file
        } else {
            r.title = "python \(file)"
        }
    }

    // MARK: Lecture système

    /// Arguments du processus (même utilisateur uniquement) via KERN_PROCARGS2.
    /// Tampon réutilisé (appelé uniquement depuis la file d'échantillonnage) : évite d'allouer
    /// et d'effacer `kern.argmax` (1 Mo) pour chaque nouveau processus.
    nonisolated(unsafe) private static var argsBuffer = UnsafeMutableRawBufferPointer.allocate(byteCount: argMax, alignment: 8)

    static func arguments(pid: pid_t) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = argMax
        guard sysctl(&mib, 3, argsBuffer.baseAddress, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return [] }
        let buffer = UnsafeRawBufferPointer(rebasing: argsBuffer[0..<size])
        let argc = Int(buffer.loadUnaligned(as: Int32.self))
        var index = MemoryLayout<Int32>.size
        while index < size, buffer[index] != 0 { index += 1 }   // chemin de l'exécutable
        while index < size, buffer[index] == 0 { index += 1 }   // bourrage
        var args: [String] = []
        while args.count < argc, index < size {
            let start = index
            while index < size, buffer[index] != 0 { index += 1 }
            args.append(String(decoding: buffer[start..<index], as: UTF8.self))
            index += 1
        }
        return args
    }

    static func workingDirectory(pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        let path = withUnsafeBytes(of: info.pvi_cdir.vip_path) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
        return path.isEmpty ? nil : path
    }

    /// « ~/Workspace/govo » ; un worktree devient « govo-console-admin ⎇ mon-sujet ».
    static func projectLabel(_ directory: String) -> String? {
        guard directory != "/", directory != home else { return nil }
        let short = directory.hasPrefix(home) ? "~" + directory.dropFirst(home.count) : directory
        if let range = short.range(of: "/.worktrees/") {
            let repo = (String(short[..<range.lowerBound]) as NSString).lastPathComponent
            let worktree = short[range.upperBound...].split(separator: "/").first ?? ""
            return "\(repo) ⎇ \(worktree)"
        }
        return short
    }

    // MARK: Utilitaires

    /// « --port 5201 », « --port=5201 », « -p 3000 ».
    private static func port(in args: [String]) -> String? {
        for (i, arg) in args.enumerated() {
            if arg.hasPrefix("--port=") { return String(arg.dropFirst(7)) }
            if (arg == "--port" || arg == "-p"), i + 1 < args.count, Int(args[i + 1]) != nil { return args[i + 1] }
        }
        return nil
    }

    private static func firstScript(_ args: [String]) -> String? {
        var skipNext = false
        for arg in args.dropFirst() {
            if skipNext { skipNext = false; continue }
            if ["-r", "--require", "--import", "--loader", "-e", "--eval"].contains(arg) { skipNext = true; continue }
            if arg.hasPrefix("-") { continue }
            return arg
        }
        return nil
    }

    private static func arguments(after script: String, in args: [String]) -> [String] {
        guard let index = args.firstIndex(of: script) else { return [] }
        return Array(args[(index + 1)...])
    }

    /// « …/node_modules/.bin/../next/dist/bin/next » → « next » ; gère les paquets « @scope/nom ».
    private static func packageName(fromScript script: String) -> String? {
        guard let range = script.range(of: "node_modules/", options: .backwards) else { return nil }
        var rest = String(script[range.upperBound...])
        if rest.hasPrefix(".bin/") {
            rest.removeFirst(5)
            if rest.hasPrefix("../") { rest.removeFirst(3) }
        }
        let parts = rest.split(separator: "/")
        guard let first = parts.first else { return nil }
        if first.hasPrefix("@"), parts.count > 1 { return "\(first)/\(parts[1])" }
        return String(first)
    }
}

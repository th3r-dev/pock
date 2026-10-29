import AppKit

// One button in the widget's quick-actions menu. `command` runs through a
// login zsh so Homebrew tools (claude, codex, codexbar) are on PATH.
// `process` lists the CLI binary names whose interactive sessions this
// button counts; their total is the number on the ⚡ button.
struct QuickAction: Codable {
    var title: String
    var symbol: String?   // SF Symbol name
    var command: String
    var process: [String]?
}

// Lives in its own file, not config.json: agents-stat's Settings window
// re-encodes config.json from its own Config struct and would drop the key.
enum QuickActions {
    static let file = Config.dir.appendingPathComponent("quick-actions.json")

    static let defaults: [QuickAction] = [
        QuickAction(title: "Claude", symbol: "plus", command: terminal("claude"), process: ["claude"]),
        QuickAction(title: "Codex", symbol: "plus", command: terminal("codex"), process: ["codex"]),
        QuickAction(title: "Antigravity", symbol: "plus", command: terminal("agy"), process: ["agy"]),
        QuickAction(title: "Kilo", symbol: "plus", command: terminal("kilo"), process: ["kilo", "kilocode"]),
    ]

    private static func terminal(_ cmd: String) -> String {
        #"osascript -e 'tell application "Terminal" to do script "\#(cmd)"' -e 'tell application "Terminal" to activate'"#
    }

    static func load() -> [QuickAction] {
        if let data = try? Data(contentsOf: file),
           let actions = try? JSONDecoder().decode([QuickAction].self, from: data) {
            return actions
        }
        // Write defaults only if no file exists — never clobber a malformed user edit.
        if !FileManager.default.fileExists(atPath: file.path) {
            try? FileManager.default.createDirectory(at: Config.dir, withIntermediateDirectories: true)
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try? (try? enc.encode(defaults))?.write(to: file)
        }
        return defaults
    }

    static func run(_ action: QuickAction) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
        proc.arguments = ["-lc", action.command]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        do { try proc.run() } catch {
            NSLog("AgentStats: quick action %@ failed: %@", action.title, "\(error)")
        }
    }
}

// Interactive sessions per binary name. Only processes with a controlling
// terminal count, so daemons and helpers (codex app-server, claude
// --chrome-native-host) don't inflate the number.
func runningSessions(_ names: Set<String>) -> [String: Int] {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/bin/ps")
    proc.arguments = ["-axo", "tty=,comm="]
    let out = Pipe()
    proc.standardOutput = out
    guard (try? proc.run()) != nil else { return [:] }
    let data = out.fileHandleForReading.readDataToEndOfFile()
    proc.waitUntilExit()
    var counts: [String: Int] = [:]
    for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
        let cols = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard cols.count == 2, cols[0] != "??" else { continue }
        let name = (cols[1].trimmingCharacters(in: .whitespaces) as NSString).lastPathComponent
        if names.contains(name) { counts[name, default: 0] += 1 }
    }
    return counts
}

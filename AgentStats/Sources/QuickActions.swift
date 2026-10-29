import AppKit

// One button in the widget's quick-actions menu. `command` runs through a
// login zsh so Homebrew tools (claude, codex, codexbar) are on PATH.
struct QuickAction: Codable {
    var title: String
    var symbol: String?   // SF Symbol name
    var command: String
}

// Lives in its own file, not config.json: agents-stat's Settings window
// re-encodes config.json from its own Config struct and would drop the key.
enum QuickActions {
    static let file = Config.dir.appendingPathComponent("quick-actions.json")

    static let defaults: [QuickAction] = [
        QuickAction(title: "Claude", symbol: "plus",
                    command: terminal("claude")),
        QuickAction(title: "Codex", symbol: "plus",
                    command: terminal("codex")),
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

// Number of live agent CLI processes (claude / codex sessions).
func runningAgents() -> Int {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    proc.arguments = ["-x", "claude|codex"]
    let out = Pipe()
    proc.standardOutput = out
    guard (try? proc.run()) != nil else { return 0 }
    let data = out.fileHandleForReading.readDataToEndOfFile()
    proc.waitUntilExit()
    return String(decoding: data, as: UTF8.self).split(separator: "\n").count
}

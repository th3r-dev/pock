import Foundation

// Per-provider display overrides. Cards themselves are created dynamically
// from whatever providers the codexbar usage call returns.
struct AgentConfig: Codable {
    var provider: String        // codexbar provider id: "claude", "codex", ...
    var name: String?           // card title; defaults to capitalized provider
    var model: String?          // gray subtitle; auto-detected when omitted
    var icon: String?           // png path; defaults to ~/.usagebar/<provider>-icon.png
    var appPath: String?        // fallback: NSWorkspace icon of this app

    init(provider: String, name: String? = nil, model: String? = nil) {
        self.provider = provider
        self.name = name
        self.model = model
    }
}

struct Config: Codable {
    var refreshInterval: Double = 60
    var codexbarPath: String?
    var providerArg: String = "all"    // passed to codexbar --provider
    var enabledProviders: [String]?    // nil = show every provider codexbar returns
    var cardWidth: Double = 244
    var warnPercent: Double = 70
    var dangerPercent: Double = 90
    var quickApp: String?      // .app shown right of the clock; tap launches it (1 slot)
    var quickAppAction = "minimize"  // tap while running: "minimize" | "close" | "fullscreen"
    var closeWindowOnQuickAdd = true  // shake-to-add: close the shaken window after adding
    var agents: [AgentConfig] = [
        AgentConfig(provider: "claude", name: "Claude"),  // model auto-detected
        AgentConfig(provider: "codex", name: "Codex", model: "GPT-5"),
    ]

    static let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".usagebar")
    static let file = dir.appendingPathComponent("config.json")

    init() {}

    // Every key optional so a hand-edited partial config still loads.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Config()
        refreshInterval = try c.decodeIfPresent(Double.self, forKey: .refreshInterval) ?? d.refreshInterval
        codexbarPath = try c.decodeIfPresent(String.self, forKey: .codexbarPath)
        providerArg = try c.decodeIfPresent(String.self, forKey: .providerArg) ?? d.providerArg
        enabledProviders = try c.decodeIfPresent([String].self, forKey: .enabledProviders)
        cardWidth = try c.decodeIfPresent(Double.self, forKey: .cardWidth) ?? d.cardWidth
        warnPercent = try c.decodeIfPresent(Double.self, forKey: .warnPercent) ?? d.warnPercent
        dangerPercent = try c.decodeIfPresent(Double.self, forKey: .dangerPercent) ?? d.dangerPercent
        quickApp = try c.decodeIfPresent(String.self, forKey: .quickApp)
        quickAppAction = try c.decodeIfPresent(String.self, forKey: .quickAppAction) ?? d.quickAppAction
        closeWindowOnQuickAdd = try c.decodeIfPresent(Bool.self, forKey: .closeWindowOnQuickAdd)
            ?? d.closeWindowOnQuickAdd
        agents = try c.decodeIfPresent([AgentConfig].self, forKey: .agents) ?? d.agents
    }

    func save() {
        try? FileManager.default.createDirectory(at: Config.dir, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? (try? enc.encode(self))?.write(to: Config.file)
    }

    static func load() -> Config {
        if let data = try? Data(contentsOf: file),
           let cfg = try? JSONDecoder().decode(Config.self, from: data) {
            return cfg
        }
        let cfg = Config()
        // Write defaults only if no file exists — never clobber a malformed user edit.
        if !FileManager.default.fileExists(atPath: file.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            try? (try? enc.encode(cfg))?.write(to: file)
        }
        return cfg
    }
}

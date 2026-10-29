import Foundation

struct WindowUsage {
    var usedPercent: Double
    var resetsAt: Date?
}

struct ProviderUsage {
    var primary: WindowUsage?    // 5-hour window
    var secondary: WindowUsage?  // weekly window
}

private func resolveCodexbar(_ cfg: Config) -> String {
    if let p = cfg.codexbarPath { return (p as NSString).expandingTildeInPath }
    for p in ["/opt/homebrew/bin/codexbar", "/usr/local/bin/codexbar"]
    where FileManager.default.isExecutableFile(atPath: p) { return p }
    return "codexbar"  // hope it's on PATH via /usr/bin/env
}

func fetchUsage(config: Config) -> [String: ProviderUsage] {
    let path = resolveCodexbar(config)
    let proc = Process()
    let args = ["--provider", config.providerArg, "--format", "json"]
    if path.contains("/") {
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = args
    } else {
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = [path] + args
    }
    let out = Pipe()
    proc.standardOutput = out
    proc.standardError = Pipe()
    do { try proc.run() } catch {
        NSLog("agents-stat: failed to run codexbar (%@): %@", path, "\(error)")
        return [:]
    }
    let data = out.fileHandleForReading.readDataToEndOfFile()
    proc.waitUntilExit()
    return parseUsage(data)
}

// Accepts either a top-level array of {provider, usage:{primary, secondary}}
// or a dict keyed by provider (or wrapping a "providers" array).
func parseUsage(_ data: Data) -> [String: ProviderUsage] {
    guard let root = try? JSONSerialization.jsonObject(with: data) else { return [:] }
    var entries: [[String: Any]] = []
    if let arr = root as? [[String: Any]] {
        entries = arr
    } else if let dict = root as? [String: Any] {
        if let arr = dict["providers"] as? [[String: Any]] {
            entries = arr
        } else {
            for (key, value) in dict {
                if var d = value as? [String: Any] {
                    if d["provider"] == nil { d["provider"] = key }
                    entries.append(d)
                }
            }
        }
    }
    var result: [String: ProviderUsage] = [:]
    for entry in entries {
        guard let provider = entry["provider"] as? String else { continue }
        let usage = (entry["usage"] as? [String: Any]) ?? entry
        result[provider.lowercased()] = ProviderUsage(
            primary: parseWindow(usage["primary"]),
            secondary: parseWindow(usage["secondary"]))
    }
    return result
}

private func parseWindow(_ any: Any?) -> WindowUsage? {
    guard let d = any as? [String: Any], let pct = d["usedPercent"] as? Double else { return nil }
    var resets: Date?
    if let s = d["resetsAt"] as? String {
        resets = parseDate(s)
    } else if let n = d["resetsAt"] as? Double {
        resets = Date(timeIntervalSince1970: n > 1e12 ? n / 1000 : n)
    }
    return WindowUsage(usedPercent: pct, resetsAt: resets)
}

private let isoFractional: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()
private let isoPlain = ISO8601DateFormatter()

private func parseDate(_ s: String) -> Date? {
    isoFractional.date(from: s) ?? isoPlain.date(from: s)
}

// Model auto-detection — used when an agent's config doesn't pin a "model" label.
func detectModel(provider: String) -> String? {
    let home = FileManager.default.homeDirectoryForCurrentUser
    switch provider {
    case "claude":
        guard let data = try? Data(contentsOf: home.appendingPathComponent(".claude/settings.json")),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = obj["model"] as? String else { return nil }
        return prettyModel(raw)
    case "codex":
        guard let text = try? String(contentsOf: home.appendingPathComponent(".codex/config.toml"),
                                     encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2,
                  parts[0].trimmingCharacters(in: .whitespaces) == "model",
                  let q1 = parts[1].firstIndex(of: "\"") else { continue }
            let rest = parts[1][parts[1].index(after: q1)...]
            guard let q2 = rest.firstIndex(of: "\"") else { continue }
            return prettyModel(String(rest[..<q2]))
        }
        return nil
    default:
        return nil
    }
}

// "fable[1m]" → "Fable", "claude-opus-4-8" → "Opus 4.8",
// "claude-haiku-4-5-20251001" → "Haiku 4.5", "gpt-5-codex" → "GPT 5 Codex"
func prettyModel(_ raw: String) -> String {
    var s = raw
    if let bracket = s.firstIndex(of: "[") { s = String(s[..<bracket]) }
    s = s.trimmingCharacters(in: .whitespaces).lowercased()
    if s.hasPrefix("claude-") { s.removeFirst("claude-".count) }
    var tokens = s.split(whereSeparator: { $0 == "-" || $0 == "_" }).map(String.init)
    if let last = tokens.last, last.count >= 8, last.allSatisfy(\.isNumber) { tokens.removeLast() }
    var out: [String] = []
    for t in tokens {
        if t.allSatisfy(\.isNumber), let prev = out.last, prev.last?.isNumber == true {
            out[out.count - 1] = prev + "." + t
        } else {
            out.append(t == "gpt" ? "GPT" : t.capitalized)
        }
    }
    return out.joined(separator: " ")
}

func countdown(to date: Date?) -> String {
    guard let date else { return "–" }
    let secs = date.timeIntervalSinceNow
    guard secs > 0 else { return "now" }
    let mins = Int(secs / 60)
    if mins >= 24 * 60 { return "\(mins / 1440)d\((mins % 1440) / 60)h" }
    if mins >= 60 { return "\(mins / 60)h\(mins % 60)m" }
    return "\(mins)m"
}

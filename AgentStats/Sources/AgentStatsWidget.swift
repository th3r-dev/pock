import AppKit
import PockKit

// Pock widget: agent quota cards (same cards as agents-stat), the Quick App
// slot, and a ⚡ button showing how many interactive agent sessions are
// running. Tapping ⚡ swaps the cards for the quick-actions menu, each button
// with its own session count, plus "＋ Custom" to add one; ‹ swaps back.
@objc(AgentStatsWidget)
final class AgentStatsWidget: NSObject, PKWidget {
    static var identifier: String { "dev.th3r.pock.agentstats" }
    var customizationLabel = "Agent Stats"
    var view: NSView!

    private var config = Config.load()
    private let root = NSStackView()
    private var strip: NSView?
    private var cards: [(provider: String, view: AgentCardView)] = []
    private var lastUsage: [String: ProviderUsage] = [:]
    private var refreshTimer: Timer?
    private var tickTimer: Timer?
    private var menuOpen = false
    private var sessions: [String: Int] = [:]
    private var quickAppPath: String?
    private lazy var quickAppButton = NSButton(image: NSImage(), target: self,
                                               action: #selector(quickAppTapped))
    private lazy var menuButton = NSButton(title: "–", image: symbolImage("bolt.fill") ?? NSImage(),
                                           target: self, action: #selector(toggleMenu))

    required override init() {
        super.init()
        root.orientation = .horizontal
        root.spacing = 8
        menuButton.imagePosition = .imageLeading
        view = root
        setQuickApp(config.quickApp)
        let enabled: (String) -> Bool = { [config] in config.enabledProviders?.contains($0) ?? true }
        buildCards(config.agents.map { $0.provider.lowercased() }.filter(enabled))
    }

    func viewDidAppear() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: max(10, config.refreshInterval),
                                            repeats: true) { [weak self] _ in self?.refresh() }
        tickTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.cards.forEach { $0.view.tick() }
        }
        refresh()
    }

    func viewWillDisappear() {
        refreshTimer?.invalidate()
        tickTimer?.invalidate()
    }

    // MARK: - Data

    @objc private func refresh() {
        let cfg = Config.load()  // pick up agents-stat Settings edits
        let names = Set(QuickActions.load().flatMap { $0.process ?? [] })
        // Separate jobs: codexbar can take ~40s, the process count is instant.
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let counts = runningSessions(names)
            DispatchQueue.main.async { self?.applySessions(counts) }
        }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let usage = Self.fetchAll(cfg)
            DispatchQueue.main.async { self?.apply(usage, config: cfg) }
        }
    }

    // codexbar takes one --provider value, so with an explicit provider list
    // (enabledProviders) poll each in parallel. Providers that only return an
    // error (e.g. not logged in) carry no windows and get no card.
    private static func fetchAll(_ cfg: Config) -> [String: ProviderUsage] {
        guard let providers = cfg.enabledProviders, !providers.isEmpty else {
            return fetchUsage(config: cfg)
        }
        let lock = NSLock()
        var merged: [String: ProviderUsage] = [:]
        DispatchQueue.concurrentPerform(iterations: providers.count) { i in
            var one = cfg
            one.providerArg = providers[i]
            let usage = fetchUsage(config: one)
            lock.lock()
            merged.merge(usage) { a, _ in a }
            lock.unlock()
        }
        return merged.filter { $0.value.primary != nil || $0.value.secondary != nil }
    }

    private func applySessions(_ counts: [String: Int]) {
        sessions = counts
        menuButton.title = "\(counts.values.reduce(0, +))"
        if menuOpen { layout() }
    }

    private func apply(_ usage: [String: ProviderUsage], config cfg: Config) {
        config = cfg
        setQuickApp(cfg.quickApp)
        lastUsage = usage
        // Rebuild only when the provider set changes, never on a plain refresh.
        let incoming = usage.keys.filter { cfg.enabledProviders?.contains($0) ?? true }.sorted()
        if !incoming.isEmpty, Set(incoming) != Set(cards.map(\.provider)) {
            buildCards(incoming)
        }
        for (provider, card) in cards { card.update(usage[provider]) }
    }

    private func buildCards(_ providers: [String]) {
        cards = providers.map { provider in
            let agent = config.agents.first { $0.provider.lowercased() == provider }
                ?? AgentConfig(provider: provider)
            return (provider, AgentCardView(agent: agent, config: config))
        }
        strip = cards.isEmpty ? nil
            : CardsStrip(cards: cards.map(\.view), cardWidth: max(180, config.cardWidth))
        layout()
    }

    // MARK: - Menu

    private func layout() {
        root.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard menuOpen else {
            if let strip { root.addArrangedSubview(strip) }
            if quickAppPath != nil { root.addArrangedSubview(quickAppButton) }
            root.addArrangedSubview(menuButton)
            return
        }
        root.addArrangedSubview(button(nil, "chevron.left", #selector(toggleMenu)))
        root.addArrangedSubview(button(nil, "arrow.clockwise", #selector(refresh)))
        for (i, action) in QuickActions.load().enumerated() {
            let n = (action.process ?? []).reduce(0) { $0 + (sessions[$1] ?? 0) }
            let b = button(n > 0 ? "\(action.title) \(n)" : action.title, action.symbol,
                           #selector(runAction(_:)))
            b.tag = i
            root.addArrangedSubview(b)
        }
        root.addArrangedSubview(button("Custom", "plus.circle", #selector(addCustom)))
    }

    // Quick App: same config key and tap behaviour as agents-stat.
    private func setQuickApp(_ path: String?) {
        let expanded = path.map { ($0 as NSString).expandingTildeInPath }
            .flatMap { FileManager.default.fileExists(atPath: $0) ? $0 : nil }
        guard expanded != quickAppPath else { return }
        quickAppPath = expanded
        if let expanded {
            let icon = NSWorkspace.shared.icon(forFile: expanded)
            icon.size = NSSize(width: 22, height: 22)
            quickAppButton.image = icon
        }
        layout()
    }

    @objc private func quickAppTapped() {
        guard let quickAppPath else { return }
        QuickApp.tap(path: quickAppPath, action: config.quickAppAction)
    }

    @objc private func addCustom() {
        ProviderForm.show { [weak self] in
            self?.menuOpen = false
            self?.refresh()
            self?.layout()
        }
    }

    private func button(_ title: String?, _ symbol: String?, _ sel: Selector) -> NSButton {
        let image = symbol.flatMap { symbolImage($0) }
        let b: NSButton
        if let title, let image {
            b = NSButton(title: title, image: image, target: self, action: sel)
            b.imagePosition = .imageLeading
        } else if let image {
            b = NSButton(image: image, target: self, action: sel)
        } else {
            b = NSButton(title: title ?? "?", target: self, action: sel)
        }
        return b
    }

    @objc private func toggleMenu() {
        menuOpen.toggle()
        layout()
    }

    @objc private func runAction(_ sender: NSButton) {
        let actions = QuickActions.load()
        guard actions.indices.contains(sender.tag) else { return }
        QuickActions.run(actions[sender.tag])
        toggleMenu()
    }
}

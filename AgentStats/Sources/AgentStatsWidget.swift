import AppKit
import PockKit

// Pock widget: agent quota cards (same cards as agents-stat) plus a ⚡ button
// showing how many agent sessions are running. Tapping ⚡ swaps the cards for
// the quick-actions menu; ‹ swaps back.
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
    private lazy var menuButton = NSButton(title: "–", image: symbolImage("bolt.fill") ?? NSImage(),
                                           target: self, action: #selector(toggleMenu))

    required override init() {
        super.init()
        root.orientation = .horizontal
        root.spacing = 8
        menuButton.imagePosition = .imageLeading
        view = root
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
        // Separate jobs: codexbar can take ~40s, the process count is instant.
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let running = runningAgents()
            DispatchQueue.main.async { self?.menuButton.title = "\(running)" }
        }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let usage = fetchUsage(config: cfg)
            DispatchQueue.main.async { self?.apply(usage, config: cfg) }
        }
    }

    private func apply(_ usage: [String: ProviderUsage], config cfg: Config) {
        config = cfg
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
            root.addArrangedSubview(menuButton)
            return
        }
        root.addArrangedSubview(button(nil, "chevron.left", #selector(toggleMenu)))
        root.addArrangedSubview(button(nil, "arrow.clockwise", #selector(refresh)))
        for (i, action) in QuickActions.load().enumerated() {
            let b = button(action.title, action.symbol, #selector(runAction(_:)))
            b.tag = i
            root.addArrangedSubview(b)
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

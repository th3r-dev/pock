import AppKit

// Single control point for every SF Symbol the app draws — menu bar, menus,
// pills, settings — so icon weight/sizing stays consistent.
func symbolImage(_ name: String, size: CGFloat = 13, weight: NSFont.Weight = .regular) -> NSImage? {
    NSImage(systemSymbolName: name, accessibilityDescription: name)?
        .withSymbolConfiguration(.init(pointSize: size, weight: weight))
}

func makeLabel(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular,
               color: NSColor = .labelColor, mono: Bool = false) -> NSTextField {
    let l = NSTextField(labelWithString: text)
    l.font = mono ? .monospacedDigitSystemFont(ofSize: size, weight: weight)
                  : .systemFont(ofSize: size, weight: weight)
    l.textColor = color
    l.lineBreakMode = .byClipping
    return l
}

final class GaugeView: NSView {
    var warn: Double = 70
    var danger: Double = 90
    var percent: Double = 0 { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds
        NSColor(white: 1, alpha: 0.18).setFill()
        NSBezierPath(roundedRect: r, xRadius: r.height / 2, yRadius: r.height / 2).fill()
        let fraction = max(0, min(percent, 100)) / 100
        guard fraction > 0.01 else { return }
        let color: NSColor = percent >= danger ? .systemRed : percent >= warn ? .systemOrange : .systemGreen
        color.setFill()
        let fill = NSRect(x: 0, y: 0, width: max(r.height, r.width * fraction), height: r.height)
        NSBezierPath(roundedRect: fill, xRadius: r.height / 2, yRadius: r.height / 2).fill()
    }
}

func loadIcon(for agent: AgentConfig) -> NSImage {
    let fm = FileManager.default
    var candidates: [String] = []
    if let p = agent.icon { candidates.append((p as NSString).expandingTildeInPath) }
    candidates.append(Config.dir.appendingPathComponent("\(agent.provider)-icon.png").path)
    for p in candidates where fm.fileExists(atPath: p) {
        if let img = NSImage(contentsOfFile: p) { return img }
    }
    let appPath = agent.appPath ?? (agent.provider == "claude" ? "/Applications/Claude.app" : nil)
    if let appPath, fm.fileExists(atPath: appPath) {
        return NSWorkspace.shared.icon(forFile: appPath)
    }
    return letterIcon(agent.name ?? agent.provider)
}

private func letterIcon(_ name: String) -> NSImage {
    let letter = String(name.prefix(1)).uppercased()
    return NSImage(size: NSSize(width: 24, height: 24), flipped: false) { rect in
        NSColor(white: 0.28, alpha: 1).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
        let s = NSAttributedString(string: letter, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .bold),
            .foregroundColor: NSColor.white,
        ])
        let size = s.size()
        s.draw(at: NSPoint(x: (rect.width - size.width) / 2, y: (rect.height - size.height) / 2))
        return true
    }
}

// Horizontal strip holding the agent cards: at most `maxVisible` cards wide,
// finger-pannable on the Touch Bar when there are more, snapping to card slots.
final class CardsStrip: NSView {
    private let content = NSView()
    private var lead: NSLayoutConstraint!
    private var startX: CGFloat = 0
    private let slot: CGFloat
    private let minOffset: CGFloat

    init(cards: [NSView], cardWidth: CGFloat, gap: CGFloat = 8, maxVisible: Int = 4) {
        let n = cards.count
        let visible = min(n, maxVisible)
        let contentW = CGFloat(n) * cardWidth + CGFloat(max(0, n - 1)) * gap
        let visibleW = CGFloat(visible) * cardWidth + CGFloat(max(0, visible - 1)) * gap
        slot = cardWidth + gap
        minOffset = min(0, visibleW - contentW)
        super.init(frame: NSRect(x: 0, y: 0, width: visibleW, height: 30))
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.masksToBounds = true
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        lead = content.leadingAnchor.constraint(equalTo: leadingAnchor)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: visibleW),
            heightAnchor.constraint(equalToConstant: 30),
            lead,
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
            content.widthAnchor.constraint(equalToConstant: contentW),
        ])
        var x: CGFloat = 0
        for card in cards {
            content.addSubview(card)
            NSLayoutConstraint.activate([
                card.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: x),
                card.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            ])
            x += cardWidth + gap
        }
        guard minOffset < 0 else { return }
        let pan = NSPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        pan.allowedTouchTypes = [.direct]
        addGestureRecognizer(pan)
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func panned(_ g: NSPanGestureRecognizer) {
        switch g.state {
        case .began:
            startX = lead.constant
        case .changed:
            lead.constant = max(minOffset, min(0, startX + g.translation(in: self).x))
        case .ended, .cancelled:
            let snapped = max(minOffset, min(0, (lead.constant / slot).rounded() * slot))
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.25
                ctx.allowsImplicitAnimation = true
                lead.animator().constant = snapped
                layoutSubtreeIfNeeded()
            }
        default:
            break
        }
    }
}

final class AgentCardView: NSView {
    private let pGauge = GaugeView()
    private let sGauge = GaugeView()
    private let pPct = makeLabel("–", size: 9, mono: true)
    private let sPct = makeLabel("–", size: 9, mono: true)
    private let pReset = makeLabel("–", size: 9, color: .secondaryLabelColor, mono: true)
    private let sReset = makeLabel("–", size: 9, color: .secondaryLabelColor, mono: true)
    private let modelLabel = makeLabel("", size: 9, color: .secondaryLabelColor)
    private var pDate: Date?
    private var sDate: Date?
    private let provider: String
    private let modelPinned: Bool  // explicit config "model" wins over detection

    init(agent: AgentConfig, config: Config) {
        provider = agent.provider.lowercased()
        modelPinned = agent.model != nil
        let w = max(180, config.cardWidth)
        super.init(frame: NSRect(x: 0, y: 0, width: w, height: 30))
        // Explicit size constraints — without these the touch bar compresses
        // the card and clips the gauges.
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: w),
            heightAnchor.constraint(equalToConstant: 30),
        ])
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 1, alpha: 0.08).cgColor
        layer?.cornerRadius = 6

        let icon = NSImageView(frame: NSRect(x: 3, y: 3, width: 24, height: 24))
        icon.image = loadIcon(for: agent)
        icon.imageScaling = .scaleProportionallyUpOrDown
        addSubview(icon)

        let name = makeLabel(agent.name ?? agent.provider.capitalized, size: 10, weight: .semibold)
        name.frame = NSRect(x: 31, y: 15, width: 68, height: 13)
        addSubview(name)

        modelLabel.stringValue = agent.model ?? detectModel(provider: agent.provider) ?? ""
        modelLabel.frame = NSRect(x: 31, y: 3, width: 68, height: 11)
        addSubview(modelLabel)

        let gaugeW = max(30, w - 194)
        let rows: [(String, GaugeView, NSTextField, NSTextField, CGFloat)] = [
            ("5h", pGauge, pPct, pReset, 16),
            ("wk", sGauge, sPct, sReset, 3),
        ]
        for (tag, gauge, pct, reset, y) in rows {
            let t = makeLabel(tag, size: 9, color: .secondaryLabelColor)
            t.frame = NSRect(x: 100, y: y, width: 16, height: 11)
            addSubview(t)
            gauge.warn = config.warnPercent
            gauge.danger = config.dangerPercent
            gauge.frame = NSRect(x: 118, y: y + 2.5, width: gaugeW, height: 6)
            addSubview(gauge)
            pct.frame = NSRect(x: 118 + gaugeW + 4, y: y, width: 32, height: 11)
            addSubview(pct)
            reset.frame = NSRect(x: 118 + gaugeW + 36, y: y, width: 40, height: 11)
            addSubview(reset)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(_ usage: ProviderUsage?) {
        pDate = usage?.primary?.resetsAt
        sDate = usage?.secondary?.resetsAt
        setRow(usage?.primary, pGauge, pPct)
        setRow(usage?.secondary, sGauge, sPct)
        if !modelPinned, let model = detectModel(provider: provider),
           modelLabel.stringValue != model {
            modelLabel.stringValue = model
        }
        tick()
    }

    // Re-render countdowns between fetches.
    func tick() {
        pReset.stringValue = countdown(to: pDate)
        sReset.stringValue = countdown(to: sDate)
    }

    private func setRow(_ w: WindowUsage?, _ gauge: GaugeView, _ pct: NSTextField) {
        gauge.percent = w?.usedPercent ?? 0
        pct.stringValue = w.map { "\(Int($0.usedPercent.rounded()))%" } ?? "–"
    }
}

import AppKit

// "＋ Custom" in the quick-actions menu opens this window. Adding saves a new
// quick action (launch button + session count) and, when a codexbar provider
// id is given, turns on that provider's quota card.
final class ProviderForm: NSObject, NSWindowDelegate {
    private static var open: ProviderForm?  // keeps the window alive while shown

    private let window: NSPanel
    private let name = NSTextField()
    private let command = NSTextField()
    private let process = NSTextField()
    private let provider = NSTextField()
    private let symbol = NSTextField()
    private let onAdd: () -> Void

    static func show(onAdd: @escaping () -> Void) {
        let form = open ?? ProviderForm(onAdd: onAdd)
        open = form
        NSApp.activate(ignoringOtherApps: true)
        form.window.center()
        form.window.makeKeyAndOrderFront(nil)
    }

    private init(onAdd: @escaping () -> Void) {
        self.onAdd = onAdd
        window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 230),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init()
        window.title = "Add Custom Provider"
        window.isReleasedWhenClosed = false
        window.delegate = self

        name.placeholderString = "Kilo"
        command.placeholderString = "kilo"
        process.placeholderString = "kilo, kilocode (default: first word of command)"
        provider.placeholderString = "kilo (optional, for the quota card)"
        symbol.placeholderString = "plus"
        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Name"), name],
            [NSTextField(labelWithString: "Command"), command],
            [NSTextField(labelWithString: "Process names"), process],
            [NSTextField(labelWithString: "codexbar provider"), provider],
            [NSTextField(labelWithString: "SF Symbol"), symbol],
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).width = 260
        grid.rowSpacing = 8

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelTapped))
        cancel.keyEquivalent = "\u{1b}"
        let add = NSButton(title: "Add", target: self, action: #selector(addTapped))
        add.keyEquivalent = "\r"
        let buttons = NSStackView(views: [cancel, add])

        let stack = NSStackView(views: [grid, buttons])
        stack.orientation = .vertical
        stack.alignment = .trailing
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        window.contentView = stack
    }

    @objc private func addTapped() {
        let title = trimmed(name)
        let cmd = trimmed(command)
        guard !title.isEmpty, !cmd.isEmpty else {
            NSSound.beep()  // name and command are required
            return
        }
        var names = trimmed(process).split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if names.isEmpty, let first = cmd.split(separator: " ").first {
            names = [(String(first) as NSString).lastPathComponent]
        }
        let sym = trimmed(symbol)
        QuickActions.add(QuickAction(title: title, symbol: sym.isEmpty ? "plus" : sym,
                                     command: QuickActions.terminal(cmd), process: names))

        let id = trimmed(provider).lowercased()
        if !id.isEmpty {
            var cfg = Config.load()
            if var enabled = cfg.enabledProviders, !enabled.contains(id) {
                enabled.append(id)
                cfg.enabledProviders = enabled
                cfg.save()
            }
        }
        onAdd()
        window.close()
    }

    @objc private func cancelTapped() { window.close() }

    func windowWillClose(_ notification: Notification) { ProviderForm.open = nil }

    private func trimmed(_ field: NSTextField) -> String {
        field.stringValue.trimmingCharacters(in: .whitespaces)
    }
}

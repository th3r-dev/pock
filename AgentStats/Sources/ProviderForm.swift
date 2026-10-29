import AppKit

// "＋ Custom" in the quick-actions menu opens this window. Adding saves a new
// quick action (launch button + session count) and, when a codexbar provider
// id is given, turns on that provider's quota card.
//
// Layout follows the macOS form pattern: right-aligned labels, required fields
// first, optional ones grouped below with their help text under the field, and
// Add disabled until the required fields are filled (inline validation, no
// beep on submit). The header icon previews the SF Symbol as it is typed.
final class ProviderForm: NSObject, NSWindowDelegate, NSTextFieldDelegate {
    private static var open: ProviderForm?  // keeps the window alive while shown

    private let window: NSPanel
    private let name = NSTextField()
    private let command = NSTextField()
    private let process = NSTextField()
    private let provider = NSTextField()
    private let symbol = NSTextField()
    private let preview = NSImageView()
    private let previewTitle = NSTextField(labelWithString: "New Provider")
    private lazy var add = NSButton(title: "Add", target: self, action: #selector(addTapped))
    private let onAdd: () -> Void

    private static let fieldWidth: CGFloat = 260

    static func show(onAdd: @escaping () -> Void) {
        let form = open ?? ProviderForm(onAdd: onAdd)
        open = form
        NSApp.activate(ignoringOtherApps: true)
        form.window.center()
        form.window.makeKeyAndOrderFront(nil)
        form.window.makeFirstResponder(form.name)
    }

    private init(onAdd: @escaping () -> Void) {
        self.onAdd = onAdd
        window = NSPanel(contentRect: .zero, styleMask: [.titled, .closable],
                         backing: .buffered, defer: false)
        super.init()
        window.title = "Add Custom Provider"
        window.isReleasedWhenClosed = false
        window.delegate = self

        name.placeholderString = "Kilo"
        command.placeholderString = "kilo"
        process.placeholderString = "kilo"
        provider.placeholderString = "kilo"
        symbol.placeholderString = "plus"
        for field in [name, command, process, provider, symbol] {
            field.delegate = self
            field.widthAnchor.constraint(equalToConstant: Self.fieldWidth).isActive = true
        }

        let grid = NSGridView(views: [
            row("Name:", name),
            row("Command:", command),
            help("Runs in a new Terminal window."),
            section("Optional"),
            row("Count processes:", process),
            help("Comma-separated. Defaults to the command."),
            row("Quota card:", provider),
            help("codexbar provider id, e.g. antigravity."),
            row("Icon:", symbol),
            help("Any SF Symbol name."),
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        grid.rowSpacing = 8
        grid.columnSpacing = 8
        for i in 0..<grid.numberOfRows {
            let r = grid.row(at: i)
            if (r.cell(at: 1).contentView as? NSTextField)?.isEditable == false {
                r.topPadding = -4  // help text hugs the field it describes
            }
        }
        let optional = grid.row(at: 3)  // "Optional" section header spans both columns
        optional.mergeCells(in: NSRange(location: 0, length: 2))
        optional.cell(at: 0).xPlacement = .leading
        optional.topPadding = 12

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelTapped))
        cancel.keyEquivalent = "\u{1b}"
        add.keyEquivalent = "\r"
        add.isEnabled = false
        let buttons = NSStackView(views: [cancel, add])
        buttons.spacing = 12

        let stack = NSStackView(views: [header(), grid, buttons])
        stack.orientation = .vertical
        stack.alignment = .trailing
        stack.spacing = 20
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)
        // Pin every row inside the margins so the window grows to fit the grid
        // (NSStackView otherwise sizes from the header and clips the rest).
        stack.views.first?.leadingAnchor.constraint(equalTo: stack.leadingAnchor,
                                                    constant: 24).isActive = true
        grid.leadingAnchor.constraint(greaterThanOrEqualTo: stack.leadingAnchor,
                                      constant: 24).isActive = true
        for view in [grid, buttons] {
            view.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -24).isActive = true
        }
        window.contentView = stack
        updatePreview()
        window.setContentSize(stack.fittingSize)
    }

    // MARK: - Layout pieces

    private func header() -> NSView {
        preview.wantsLayer = true
        preview.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.15).cgColor
        preview.layer?.cornerRadius = 9
        preview.contentTintColor = .controlAccentColor
        preview.imageScaling = .scaleNone
        NSLayoutConstraint.activate([
            preview.widthAnchor.constraint(equalToConstant: 40),
            preview.heightAnchor.constraint(equalToConstant: 40),
        ])
        previewTitle.font = .systemFont(ofSize: 15, weight: .semibold)
        let subtitle = NSTextField(wrappingLabelWithString:
            "Adds a launch button with a session count to the Touch Bar menu.")
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = .secondaryLabelColor
        subtitle.preferredMaxLayoutWidth = 300
        let text = NSStackView(views: [previewTitle, subtitle])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2
        let row = NSStackView(views: [preview, text])
        row.alignment = .centerY
        row.spacing = 12
        return row
    }

    private func row(_ label: String, _ field: NSTextField) -> [NSView] {
        [NSTextField(labelWithString: label), field]
    }

    private func help(_ text: String) -> [NSView] {
        let l = NSTextField(wrappingLabelWithString: text)
        l.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        l.textColor = .secondaryLabelColor
        l.preferredMaxLayoutWidth = Self.fieldWidth  // wrap under the field, never past it
        return [NSGridCell.emptyContentView, l]
    }

    private func section(_ title: String) -> [NSView] {
        let l = NSTextField(labelWithString: title)
        l.font = .systemFont(ofSize: 12, weight: .semibold)
        l.textColor = .secondaryLabelColor
        return [l, NSGridCell.emptyContentView]
    }

    // MARK: - Live feedback

    func controlTextDidChange(_ obj: Notification) { updatePreview() }

    private func updatePreview() {
        let sym = trimmed(symbol)
        preview.image = NSImage(systemSymbolName: sym.isEmpty ? "plus" : sym,
                                accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 18, weight: .medium))
            ?? NSImage(systemSymbolName: "questionmark", accessibilityDescription: nil)
        previewTitle.stringValue = trimmed(name).isEmpty ? "New Provider" : trimmed(name)
        // Show the real default the empty field will use.
        process.placeholderString = defaultProcess() ?? "kilo"
        add.isEnabled = !trimmed(name).isEmpty && !trimmed(command).isEmpty
    }

    private func defaultProcess() -> String? {
        trimmed(command).split(separator: " ").first.map { (String($0) as NSString).lastPathComponent }
    }

    // MARK: - Actions

    @objc private func addTapped() {
        let title = trimmed(name)
        let cmd = trimmed(command)
        guard !title.isEmpty, !cmd.isEmpty else { return }
        var names = trimmed(process).split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if names.isEmpty, let first = defaultProcess() { names = [first] }
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

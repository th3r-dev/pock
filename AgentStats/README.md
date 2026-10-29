# Agent Stats widget

A Pock widget that shows the AI agent quota cards from
[agents-stat](https://github.com/th3r-dev/agents-stat) (5h / weekly gauges
from the [CodexBar](https://github.com/steipete/CodexBar) CLI). Next to the
cards, a ⚡ button shows how many interactive agent sessions are running.
Only processes attached to a terminal count, so background daemons don't.

Between the cards and ⚡ sits the **Quick App** slot from agents-stat (the
`quickApp` app in `config.json`). Tap it to launch the app, or, while it's
running, to minimize, close or fullscreen it (`quickAppAction`). Those three
need Accessibility for Pock; without it, the tap hides or unhides the app.

Tap ⚡ to open the quick-actions menu on the Touch Bar: ‹ back, ↻ refresh,
then one button per quick action, each showing its own session count
("Claude 2"), then **＋ Custom**. Tap ‹ to go back to the cards.

**＋ Custom** opens an Add Custom Provider window. Fill in a name, the command
to run in Terminal, optionally the process names to count and the codexbar
provider id for a quota card, then click Add. The button appears in the menu
right away.

## Build

```sh
# 1. Pock itself (once). Xcode 27 needs the 12.0 deployment target override.
pod install
xcodebuild -workspace Pock.xcworkspace -scheme Pock -configuration Debug \
  -derivedDataPath build CODE_SIGN_IDENTITY=- MACOSX_DEPLOYMENT_TARGET=12.0 build

# 2. The widget (links PockKit from step 1), installed into Pock's widget folder
make -C AgentStats install
open build/Build/Products/Debug/Pock.app
```

Then open Pock → Customize Touch Bar and drag **Agent Stats** onto the bar.
Quit the standalone agents-stat app first. Both present a full-width bar, and
the last one presented wins.

## Configuration

- `~/.usagebar/config.json`: shared with agents-stat (refresh interval,
  card width, thresholds, enabled providers). Re-read on every refresh.
  When `enabledProviders` is set, each provider is polled separately, so any
  codexbar provider works: add `"antigravity"`, `"kilo"`, `"cursor"`,
  `"gemini"`, and so on. A provider that only returns an error (for example,
  not logged in) gets no card.
- `~/.usagebar/quick-actions.json`: the menu buttons. It's created with
  defaults on first run (new session for Claude, Codex, Antigravity `agy`).
  ＋ Custom appends to it. Each entry runs `command` in a login zsh. `process` lists the CLI
  binary names whose sessions the button counts:

```json
[
  { "title": "Antigravity", "symbol": "plus", "process": ["agy"],
    "command": "osascript -e 'tell application \"Terminal\" to do script \"agy\"'" },
  { "title": "Stop all", "symbol": "stop.fill", "command": "pkill -x claude; pkill -x codex" }
]
```

`symbol` is any SF Symbol name. The file is separate from `config.json`
because agents-stat's Settings window rewrites `config.json` and would drop
unknown keys.

`Usage.swift`, `Config.swift`, `Cards.swift` and `QuickApp.swift` are copied
from agents-stat.
Re-copy them when they change there.

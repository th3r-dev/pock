# Agent Stats widget

A Pock widget that shows the AI agent quota cards from
[agents-stat](../../agents-stat) (5h / weekly gauges from the
[CodexBar](https://github.com/steipete/CodexBar) CLI). Next to the cards, a
⚡ button shows how many `claude` / `codex` sessions are running.

Tap ⚡ to open the quick-actions menu on the Touch Bar: ‹ back, ↻ refresh,
then one button per quick action. Tap ‹ to go back to the cards.

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
- `~/.usagebar/quick-actions.json`: the menu buttons. It's created with
  defaults on first run (new Claude session, new Codex session). Each entry
  runs `command` in a login zsh:

```json
[
  { "title": "Claude", "symbol": "plus", "command": "osascript -e 'tell application \"Terminal\" to do script \"claude\"'" },
  { "title": "Stop all", "symbol": "stop.fill", "command": "pkill -x claude; pkill -x codex" }
]
```

`symbol` is any SF Symbol name. The file is separate from `config.json`
because agents-stat's Settings window rewrites `config.json` and would drop
unknown keys.

`Usage.swift`, `Config.swift` and `Cards.swift` are copied from agents-stat.
Re-copy them when they change there.

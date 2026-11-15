# Brian Computer Use

A macOS command panel: **press a shortcut → type an instruction → press Enter → act**.

This initial slice is text-only and executes supported commands immediately. It is a working native launcher, not yet a general-purpose AI computer-use agent.

## Run

Requires macOS 14+ and Swift 6+ (Xcode or Command Line Tools). No API key or third-party dependencies.

```sh
swift run Brian
```

Brian opens on launch and stays in the menu bar. Press **Control + Option + Space** to show or hide the panel. Type an instruction and press **Enter** to execute; **Escape** dismisses the panel. Clicking an example only fills the input. Successful actions dismiss the panel; errors keep the instruction available to edit.

## Supported instructions

| Instruction | Action |
| --- | --- |
| `Open Notes` / `Launch Safari` | Open an installed application |
| `Open github.com/use-brian` | Open a website in the default browser |
| `https://example.com` | Open a web URL directly |
| `Search for coffee nearby` / `Google SwiftUI examples` | Search Google in the default browser |

Application lookup supports common app aliases and exact bundle names in `/Applications`, `~/Applications`, `/System/Applications`, and its Utilities directory. This first version does not recursively discover apps in other folders.

The parser handles the phrases above, not arbitrary natural language or multi-step tasks. Unsupported instructions display an error. Web actions accept HTTP/HTTPS only; app actions resolve installed bundles. Instructions are never passed to a shell. Opening a URL confirms the OS accepted the request, not that the page finished loading.

Instructions remain in memory only. There is no recording, screen capture, telemetry, or model service. Web searches send the query to Google through your browser. These initial actions do not require Accessibility or Screen Recording permissions.

## Build a local app

```sh
bash scripts/build-app.sh
open dist/Brian.app
```

The script creates an ad-hoc signed app for local development. Distribution signing, notarization, an app icon, and updates are not configured.

## Develop

Tests require full Xcode with XCTest. If your selected developer directory points to Command Line Tools, prefix `swift test` with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

```sh
swift test
swift build
```

- `Sources/BrianApp`: SwiftUI input, AppKit panel/menu bar, global shortcut, native execution.
- `Sources/BrianCore`: typed actions and deterministic instruction interpretation.
- `Tests/BrianCoreTests`: parsing, URL constraints, and search-query handling.
- `Resources` and `scripts`: local app packaging.

The execution boundary is `Action`. Extend the interpreter independently of the native UI. A future model-backed planner should produce typed actions through this boundary and report progress/errors through the command model.

## Next slices

1. Configurable keyboard shortcut and launch at login.
2. Model-backed instruction interpretation with an explicit provider setup.
3. Context from the active app and a cancellable multi-step action runner.
4. Accessibility-driven interaction with apps, with task progress and interruption.

Voice is outside the initial scope.

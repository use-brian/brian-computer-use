# Brian Computer Use

**Control + Option + Space → type a task → Enter → local agent loop.**

Brian is a native macOS command panel. It runs the fine-tuned model from
`llm-research` locally, repeatedly observing the selected app, proposing one
action, executing it, and checking the resulting accessibility tree.

The floating **Brian companion** uses the existing cyan pixel mascot. Click it
to open the command panel, drag it to reposition, or right-click for Open, Stop,
and Hide. Its position is remembered. It blinks and bobs while idle, moves its
feet while working, and smiles after verified completion. macOS Reduce Motion
disables the motion. Restore a hidden companion from the menu-bar menu.

## Current scope

- **Model:** Qwen3.5-4B, MLX 4-bit conversion, with the `mac-ax-bootstrap-v0` LoRA adapter.
- **Apps:** Finder and TextEdit. Select the target in **Work in**. Opening Brian
  while either app is frontmost selects that app automatically.
- **Actions:** accessibility press and text replacement. Input is accessibility
  text; screenshots and voice are not used.
- **Loop:** at most 12 actions per submission, fresh observation after each
  action, stop on repeated states, invalid actions, runtime failure, or model stop.
- **Control:** Stop or Escape cancels the run, including model/native subprocesses.
  Closing the panel keeps work running; quitting Brian stops the runtime.

The adapter was trained on synthetic single-action examples. This loop adds
execution orchestration; it does not retrain the model or turn it into a proven
general-purpose planner. Complex instructions can still stop early or fail.
Runtime rules can refine model proposals, including binding exact user text.

## Build the full app

The repository lives at `~/work-dev/use-brian/brian-computer-use`.
Requires Apple Silicon and Swift 6+/Xcode. The supplied research runtime's native
helper targets **macOS 27.2**, so full app builds currently require macOS 27.2+.
The Swift UI alone targets macOS 14+. Older runtime compatibility is unverified.

First build `dist/mac-control` in your `llm-research` checkout using its packaging
instructions. Then, from this repository:

```sh
bash scripts/build-app.sh --research-root /absolute/path/to/llm-research
open dist/Brian.app
```

Alternatively, supply an already packaged runtime:

```sh
bash scripts/build-app.sh --runtime-bundle /absolute/path/to/mac-control
```

The resulting **approximately 3.3 GB `Brian.app` contains the base weights,
adapter, Python, MLX, MCP server, and native accessibility helper**. It needs no
separate Python installation, research checkout, API key, network listener, or
model download at runtime. The model stays loaded between tasks. Cancelling an
in-flight runtime request terminates its process group; quitting always shuts
the runtime down. A later task restarts the runtime when needed.

Weights and generated bundles stay out of Git. The bundle contains model
attribution, licensing, resource hashes, and (when `--research-root` is used)
the research model card and dependency lockfile. Packaging uses ad-hoc signing
for local development; distribution signing/notarization is not configured.

## First run

1. Open Finder or TextEdit and select the window to work in.
2. Open Brian, choose the target app, type an instruction, and press Enter.
3. If prompted, open the privacy pane using Brian's settings button. Enable
   **Brian** in **Accessibility** (named **Device Control and Data Access** on
   newer macOS versions), then retry. macOS may require restarting Brian.

After rebuilding an ad-hoc-signed app, macOS can retain an enabled switch for
the old signature while denying the new copy. Remove the stale **Brian** entry,
then add the current `dist/Brian.app` with the **+** button and enable it again.
Do not rebuild between granting access and testing that copy.

The model can read the selected app's open windows. This is app-level access,
not file isolation. Start with a new, disposable document. Applied edits are
not rolled back by Stop, and an interrupted text action can leave a partial edit.

For a small action:

```text
Press the "File" menu.
```

For a verifiable text task in the selected TextEdit document:

```text
Replace the entire contents of the editable text area with exactly this text: "Hello from Brian."
```

The exact-replacement form accepts a JSON string (use `\n` for line breaks).
Brian pins it to the main document window and verifies exact text readback.
Other tasks use app-wide context, including menus. The app does not claim an
arbitrary task succeeded just because the policy returned `stop`.

Existing launcher commands still work immediately without model inference:
`Open Notes`, `Open github.com`, and `Search for coffee nearby`.

## Develop and test

```sh
swift build
swift test
```

Tests require full Xcode with XCTest. If Command Line Tools is selected:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

To run from source after `swift build`, point at the research runtime:

```sh
BRIAN_RUNTIME_BUNDLE=/absolute/path/to/llm-research/dist/mac-control swift run Brian
```

For a lightweight UI/CI build without proprietary/local model artifacts:

```sh
bash scripts/build-app.sh --shell-only
```

A shell-only build displays a missing-runtime error for agent tasks; it never
falls back to a cloud model. CI runs mock-backed loop and real-stdio transport
tests, not inference or desktop-control tests against the local weights.

Local validation on 2026-11-15: all 22 tests passed. The full bundled 0.2.0 app
also completed a TextEdit replacement with `Brian final build: Café 新加坡.`;
both Brian's fresh readback and an independent UI inspection confirmed the
exact text. The companion displayed its happy **Done!** state. This validates
one live text action, not general multi-step task reliability.

## Architecture

```text
SwiftUI command panel
  ├─ launcher command → NSWorkspace
  └─ agent task → AgentLoop
       ├─ mac_status
       ├─ mac_observe → current accessibility snapshot
       ├─ mac_propose → local Qwen + LoRA + runtime rules
       ├─ validate → mac_execute (single-use token; stale snapshot rejected)
       └─ observe again → verify / continue / stop
```

- `Sources/BrianCore/AgentLoop.swift`: bounded orchestration and verification.
- `Sources/BrianCore/MCPRuntime.swift`: async stdio MCP client, deadlines, cancellation.
- `Sources/BrianRuntimeHost`: process-group isolation for model/native shutdown.
- `Sources/BrianApp`: input, target app, progress, native launcher commands.
- `Tests/BrianCoreTests`: loop behavior and subprocess protocol tests.
- `scripts/build-app.sh`: self-contained app packaging.

No instructions, snapshots, or model outputs are persisted by Brian. The runtime
holds bounded, expiring proposal/snapshot records in memory. Search commands
still send the search query to Google through the default browser.

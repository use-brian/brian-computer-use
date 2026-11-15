# Brian Computer Use

**Control + Option + Space → say what you want → Brian plans and acts locally.**

The app keeps a single input line and an animated cyan companion. Brian runs to
the bar when it opens, shrinks beside the current action target while working,
and returns to the bar afterward. Closing the bar sends Brian back to the screen
edge nearest its resting position; a running task keeps target-following active
and returns to the edge when finished. Manual dragging takes priority; motion respects
Reduce Motion and stays within the active display. Click the pet
to open the input, drag it to move, or right-click for Open/Stop/Hide. Replies,
clarifications, and action confirmations appear only when relevant. The lower
name badge is removed. Reduce Motion is respected.

## Natural language, not command templates

Every request now goes to the bundled language model. The old launcher/mail
regex parsers remain as legacy utilities and regression tests; they do not gate
or route the live input. Examples:

- “Could you pull up the most recent email I got from Draper?”
- “Bring up my calculator please.”
- “Open Calculator and work out 17 times 23.”
- “I need a new text document with a short thank-you note to Sam.”
- “What about invoices from them?” after an email search.

The planner sees the installed apps, current accessibility snapshot, recent
conversation, and this task's tool results. It chooses one action, executes it,
re-observes, and chooses the next step. It asks a question if information or a
capability is missing. Conversation context stays in memory; **New conversation**
in the menu bar clears it. Stop/Escape cancels the current run.

### Available actions

Open installed apps, open HTTP(S) addresses, search the web, search Apple Mail,
press accessible controls, replace text, use a small set of keyboard shortcuts,
and scroll supported areas. When Accessibility is blocked, capture the current
window, locate a visible target, then click or scroll using vision. Mail search uses All Mailboxes and preserves
the existing sort order; Mail's normal search can match sender,
subject, and message content. Results stay in Mail.

Generic app control is no longer limited to Finder and TextEdit. It relies on
Accessibility first, then uses local vision for custom canvases or missing
controls. Hidden controls and complex workflows may still fail. Visual navigation
currently supports clicking and scrolling; text entry requires an accessible
field or an offered keyboard shortcut. There is no arbitrary shell, script
execution, or guarantee that every request can be completed. Terminal, Script Editor, system/security settings, and secure text
fields require manual control.

Each run is limited to 32 planning steps. Invalid or stale targets, changed documents,
uncertain execution failures, and cancellation stop the run. A capability check
that proves no action was dispatched, or repeated unchanged Accessibility actions,
can trigger vision recovery. Partially applied edits are never blindly retried.
Text actions verify exact readback. The original request is preserved verbatim.
A proposed completion triggers another fresh observation and a separate local
review against the whole request. The review must cite actual observation IDs;
tool acknowledgments and search hit counts cannot establish an information answer.
Rejected completion feeds the missing work back into planning and requires a
further tool action before another completion proposal. Three consecutive
unsupported completion proposals stop with an explicit incomplete result.

The last eight bounded observations are retained in memory so earlier-read facts
remain available while navigating. Accessible result rows can be selected and
content regions inspected directly. Relative dates use the request's local date;
flight searches must check departure dates in the content, not received dates.
The reviewer uses the same local base model in a separate inference pass. Citation
validation prevents invented sources, but semantic judgment can still be wrong;
this is not a guarantee of arbitrary task completion. No successful action is blindly
retried after an execution error. Consequential controls such as Send/Delete and
submission/paste/save shortcuts request confirmation; review these in the app.
This confirmation layer is heuristic, not a complete security boundary for all
possible third-party interfaces.

## Accessibility-first navigation and visible focus

Every planning turn starts with fresh Accessibility data. A missing/unsupported
control triggers `vision_observe` with a reason; screenshots are not the default.
A dedicated visual step uses the same local multimodal model with a smaller
action set, then a short, separate grounding pass locates the target. Images are single-use and kept in memory only.
After a visual action, Brian returns to Accessibility and requests another image
only if needed. Screenshots and image bytes never enter conversation history.

A click-through overlay shows the current app/target and action: **teal for
Accessibility**, **orange for vision**. A virtual cursor previews the target
without warping your real pointer. The overlay does not activate windows or
intercept clicks, and disappears on Stop/completion/error. It uses global display
coordinates, including screens to the left/above the main display. There is no
motion animation in the overlay. The pet indicates Thinking/Looking/Working; the single chat line shows the current
action while running and returns to the input afterward.

Vision captures only the selected application window through ScreenCaptureKit,
without audio or the overlay. It needs macOS **Screen & System Audio Recording**
access; the guide opens the relevant pane when fallback first needs it. Visual
clicks ask for confirmation because their semantics cannot be validated through
Accessibility. The preview marks the proposed target on the captured window, both in the
confirmation popover and in the desktop overlay. Before dispatch, Brian
checks the same process/window/frame, the image age, and a fresh screenshot;
a changed target or page stops execution. This is conservative and may stop on
animated content. It is not a guarantee of semantic correctness.

## Local model

The app bundles **Qwen3.5-4B MLX 4-bit language and vision weights**, Python, MLX-VLM, MCP, and native
helpers (~3.6 GB). General planning uses the **base instruction model** without
the narrow AX adapter. The `mac-ax-bootstrap-v0` LoRA adapter remains bundled
and available through legacy research MCP tools, but it was trained on synthetic
single-action Finder/TextEdit examples and is not a general planner.

No API key, cloud model, listening server, external Python install, or runtime
model download is needed. Local observations and conversation are not written
to logs by Brian. Web search/open actions use the selected browser and transmit
normal requests there. Email content in observations is treated as untrusted
application data, not instructions.

## Build

Checkout: `~/work-dev/use-brian/brian-computer-use`.
Requires Apple Silicon and full Xcode/Swift 6+. The packaged research native
helper targets **macOS 27.2**, so the full bundle advertises 27.2+. The Swift UI
alone targets macOS 14+.

First prepare `dist/mac-control` in the local `llm-research` checkout. Its virtual
environment must contain the pinned dependencies and PyInstaller. Then:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  bash scripts/build-app.sh --research-root /absolute/path/to/llm-research
```

This freezes Brian's planner alongside the existing research MCP tools without
modifying the research checkout. No dependencies are downloaded. For repeated
UI builds, reuse the already frozen planner:

```sh
bash scripts/build-app.sh --runtime-bundle "$PWD/dist/planner-runtime/mac-control"
```

The runtime must contain `resources/planner-version.json`; an old research-only
runtime cannot handle natural-language planning. To rebuild just the runtime:

```sh
bash scripts/build-planner-runtime.sh /absolute/path/to/llm-research
```

Full builds include model licenses, weights/adapter hashes, and research
provenance when `--research-root` is supplied. Weights, runtime binaries, and build
outputs stay out of Git. Signing is ad hoc for local development; release signing
and notarization are not configured.

## Accessibility setup

When control requires access, a guide stays visible beside System Settings.
Click **Open Accessibility Settings**, drag the Brian icon into the list, enable
its switch, then click **I’ve enabled it — retry**. This exports the actual app
URL, not a temporary copy. New macOS versions name this pane **Device Control
and Data Access**.

Ad-hoc rebuilds can invalidate the saved grant even when the switch is on.
Remove the stale Brian entry and add the final `.app` again. Do not rebuild after
authorizing the copy you intend to use. Stop does not roll back actions; an
interrupted text operation can leave a partial edit.

## Test and architecture

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
python3 -m unittest discover -s PlannerRuntime -p 'test_*.py'
bash scripts/build-app.sh --shell-only
```

CI runs Swift orchestration/transport tests and Python schema-validation tests.
These do not establish real model planning accuracy or every app's compatibility.
A shell-only build has no inference runtime and never falls back to cloud.

```text
Input + in-memory conversation
  → NaturalAgent
  → local brian_plan (Qwen base instruction model)
  → strict tool validation + optional confirmation
  → DesktopController / Apple Mail search / NSWorkspace
  → fresh accessibility observation → next action or reply
```

- `PlannerRuntime`: inference prompt, schema validation, frozen-runtime entry.
- `Sources/BrianCore/NaturalAgent.swift`: bounded planning loop and tool contracts.
- `Sources/BrianApp/DesktopController.swift`: observed app controls and execution checks.
- `Sources/BrianApp/MailSearchExecutor.swift`: verified Mail search workflow.
- `Sources/BrianCore/MCPRuntime.swift`: local stdio transport, timeout/cancellation.
- `Sources/BrianApp/PermissionGuideView.swift`: native draggable app setup guide.

## Validation on 2026-11-15

52 Swift tests and 15 Python validation tests pass. Real local-model checks mapped
varied email/app/document requests to tools, including a contextual follow-up
(“What about invoices from them?” → a Draper invoice search). A live run of the
previously rejected “search cathay emails for me” changed the visible Mail query
and returned independently inspected Cathay/Cathay Pacific messages.

General GUI reliability remains experimental: Calculator opened and accepted
button actions, but the arithmetic workflow stalled and a Clear action left a
pending operation despite the model claiming completion. A corrective run then
stopped on a focus change. These checks do **not** establish reliable arbitrary
task completion. Review the actual app result, especially for multi-step tasks.

Local synthetic vision smoke checks use the actual bundled weights: an accessible
Continue button chooses `press`; a custom canvas with no supported control chooses
`vision_observe`; the separate grounding pass places a click inside the drawn
Continue button. Run `scripts/smoke-local-model.py /path/to/model` with the research
Python environment. `Tests/Fixtures/NavigationDemo.swift` provides a harmless native
window with one accessible button and a custom canvas for manual end-to-end checks.
These fixtures do not measure general visual grounding accuracy.

The companion placement checks cover screen edges, negative display coordinates,
and keeping the pet clear of the command bar and small action targets. Live
vision-click delivery remains unverified: the latest native end-to-end runs
stopped on focus changes. Synthetic grounding checks are not a substitute for
successful native click delivery.

Mail searches preserve the current sort order and do not open View → Sort By.
Automatic sort verification previously left nested native menus stranded after
the search; removing that unrelated step avoids trapping Mail in menu tracking.
After a normal Mail restart, a live repeat of the reported search completed;
Mail’s File menu then opened and dismissed normally. All 45 Swift tests passed.

The companion is smaller (80-point idle artwork, 38-point working artwork).
When a task ends it displays the actual reply beside the pet in a dismissible,
scrollable speech bubble. New work hides the reply; the bar still provides a
reply button for reopening the result. Right-click the pet and choose **Read last
reply** to reopen and select its text.

### Goal completion checks

`scripts/smoke-goal-verification.py /path/to/model` exercises the actual local
weights with synthetic evidence: search-only and wrong-event-date answers are
rejected, supported flight details and a simple open-app request are accepted,
and a missing PDF export keeps a multi-step request incomplete. The planner
selects a result after a search instead of stopping. `Tests/Fixtures/WorkflowDemo.swift`
provides a native two-booking list with departure dates available only after
selection, for checking the full generic observation/action/review workflow.

The final 0.5.0 bundled app also passed a fresh live fixture run: starting with
neither booking selected, it opened the first confirmation (departure 13 Nov),
continued to the second (departure 16 Nov), and returned QX200 at 14:20 for the
16 Nov request. The selected content and final reply were independently checked.
An earlier run exposed repeated premature completion; the verifier rejected it,
and the final planner now requires a recovery action before proposing completion
again. This is one controlled workflow, not a general reliability benchmark.

### Test isolation and quiet focus (0.5.1)

Release builds exclude Brian's workflow/navigation fixtures from app discovery,
observation, and control, including fixtures marked `BrianTestFixture = true` in
Info.plist. For development only, a **debug** build can opt in with
`BRIAN_ENABLE_TEST_FIXTURES=1`. Never leave a fixture session in the user-facing
app: quit the debug app, close/remove temporary fixture bundles, and relaunch
normal Brian with a fresh conversation after a test. New conversation also
clears the remembered target app. Earlier assistant replies are not evidence;
synthetic content cannot establish a real-world answer.

The focus overlay uses an unfilled one-point outline with low opacity. It no
longer tints the window or displays the black Accessibility/Vision label; the
pet and command bar carry activity status. The action marker is a small hollow
ring rather than a white disk.

The native observation collector also prioritizes result tables ahead of navigation
sidebars, compares AX element identity rather than treating hashes as unique, and
uses the owning table's selected-rows API where available. In the live Mail check,
Brian used the real Mail app, but the run still stopped when vision could not
match an unambiguous visible window. Real flight retrieval is **not yet verified**;
passing the synthetic checks does not establish that workflow's reliability.

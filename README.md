# Brian Computer Use

**Control + Option + Space → say what you want → Brian plans and acts locally.**

The app keeps a single input line and chooses the app/window automatically from
the request and current context. There is no app or backend picker. The chosen
app appears as read-only status while working. Brian runs to the bar when it
opens, becomes a small pink virtual cursor at a visible action target,
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
outputs stay out of Git. Full builds require a stable signing identity; release signing
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

62 Swift tests and 23 Python validation tests pass. Real local-model checks mapped
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


### Date-aware email retrieval (0.6.0)

The local model extracts search topics separately from the requested date. The
harness resolves `tomorrow`, `tmr`, and `tmrw` using the request's local calendar,
then generates bounded alternatives: `flight Nov 16`, `flight November 16`,
`flight 16 Nov`, ISO/numeric dates, alternate topics, and broader queries. An
explicit exact-phrase search keeps its literal text. Event dates are not treated
as the date the email arrived; a search hit is only a candidate, and the message
content must establish the requested date and details.

Each run retains every attempted query and its observed outcome. Duplicate
queries cannot execute again, and all planned/model-generated searches share a
14-query limit. A confirmed empty result advances automatically; an initial
empty observation is checked again after waiting. Repeated inspections advance
the search strategy instead of treating missing results as an Accessibility
failure requiring vision. The model can still propose new queries and inspect
promising messages. A focused candidate-selection pass presents the 4B model with
message labels and asks which relevant email to open, without the full desktop
control inventory. Large result-row previews are summarized so they do not
crowd out other result rows and selected message content.

`scripts/smoke-mail-search-plan.py /path/to/model` checks the actual local 4B
model's interpretation of the original flight request, `tmr`, a delivery request,
and a non-email request. Unit tests cover date boundaries, exact phrases, query
memory, budget enforcement, stale observations, and alternate-query execution.
These checks establish search planning behavior, not general email-retrieval
accuracy or proof that a real booking exists.


Mail message rows are opened with fresh sender/subject/mailbox/date metadata,
Accessibility bounds, an AX hit test, and a window-targeted click. The All
Mailboxes scope uses the same semantic click path because Mail's row setters
proved unreliable during live checks. The agent then reads fresh content;
a click or selection flag alone never proves the task completed. Short Unicode
input batches reduce interruption by live search suggestions while retaining
foreground/focus checks.

HTML table rows inside email bodies are exposed as readable content, not
selectable message rows. Their cell text gets the document-text budget rather
than a short control-value budget. This fixes the observed failure where the
model opened a real confirmation, then tried to select its itinerary table and
stopped with “Selection did not match the requested item.”


Date-sensitive email replies must use explicit observed event dates rather than
“next day”/“following day” chronology. For generated-summary mode, the harness rejects that reply format
before completion. Flight-search answers prioritize supported departure details
and omit unrequested arrival-day comparisons. A proposed second 4B factual pass
was not retained: it both missed incorrect claims and rejected correct details.
Earlier verifier variants also rejected correct cross-date itineraries. The final
smoke checks pass the sampled explicit-date case, but that is not evidence of
general itinerary reasoning reliability. A stronger
planner/reviewer may still be needed for reliable complex itinerary reasoning;
these harness improvements do not establish general intelligence.


For dated event lookups in Mail, the final reply is now **extractive**: the model
chooses relevant evidence, and native code displays only verbatim cited message
content containing the requested date and year. Model-written itinerary prose
is not displayed in this mode. A live run had found the right booking but added
unsupported return-time and cabin-class claims; this boundary prevents such
invented fields from reaching the user. The reviewer still checks whether the
content answers the request, and an absent qualifying excerpt keeps the task
incomplete. This trades polished summaries for traceable local results.

Citations to individual dates expand to their observed document-cell context,
so an itinerary reply includes surrounding flight details rather than a lone
date. Expansion uses native observation groups, not model-generated text.

Final 0.6.0 validation: 62 Swift tests and 23 Python tests passed, as did the
local-model search-planning and completion-review smoke checks. A live Apple
Mail run for an explicit November 16, 2026 request searched, opened a real
booking, and returned observed itinerary text containing the date, route, and
departure time. This verifies that sampled workflow, not exhaustive retrieval
of every matching message or every possible itinerary layout.


### Selected-window background mode (0.7.0)

Use the **Mac** target menu in the command bar to choose an open app window.
Brian pins that process and Accessibility window for the entire task, observes
only that window, and does not activate or raise the target app. You can use
other apps while supported Accessibility operations and PID-directed window
input run. Choose **Mac — across apps** for tasks that need several apps.

Window mode does not silently widen its scope: closing/minimizing the target
stops the task; another app becoming foreground does not. Global URL opening,
shared clipboard shortcuts, new-window shortcuts, app menus, and global vision
scrolling are unavailable in this mode. Unsupported input
asks for foreground/Mac mode instead. App-local keyboard input is allowed only
while the selected window still owns that app's focus. Keep the target open and
avoid editing that same window while Brian works. Individual apps can refuse
background input or raise their own UI; this is not a separate macOS session.
The focus highlight is suppressed when the selected app is in the background.

The native chat field has standard Edit menu equivalents: Command-A/X/C/V,
Command-Z, and Shift-Command-Z. These apply to Brian's editor, independently of
restrictions on agent-issued clipboard shortcuts in window mode.

Search dates must be grounded in the current request. Standalone search-intent extraction
excludes previous task context; explicit references such as “that day”
can reuse an earlier user-supplied date. An undated invoice search has no date
variants, and subsequent model actions cannot add an unrequested date filter.
Regression coverage includes the invoice-to-AOGB request after a dated flight
conversation, plus an actual local-model extraction smoke test.

0.7.0 validation: 67 Swift tests and 26 Python tests passed. The actual bundled
model's extraction smoke test kept the invoice-to-AOGB request undated after a
flight-date conversation. A live selected-Mail-window search completed while
Calculator accepted clicks and keyboard input. Command-A, copy, cut, paste, and
undo were exercised in the live chat field; the original invoice draft was
restored. This establishes the sampled Mail workflow, not universal background
compatibility for every macOS app or every control.


### agent-desktop preview (0.8.0)

The command bar's target menu now contains **Use agent-desktop (preview)**.
Select an app window and enable it before submitting a task. Native control
remains the startup default; changing backends during a task is disabled.

This is a hybrid, opt-in migration behind `DesktopTools`, not a replacement
planner. agent-desktop supplies bounded Accessibility snapshots and qualified
reference actions for supported clicks, row selection, value setting and
scrolling. Brian still owns the local model, goal verification, confirmations,
window boundary, and UX. Mail search, permitted app-local keys, and explicit
vision requests choose the native implementation **before** dispatch. No CLI
action is blindly retried through native control. In 0.8.1, an explicit
`not_delivered` + `safe` capability refusal can request window-scoped vision;
safe stale-reference failures can re-observe within a bounded recovery budget.
For uncertain selection/value writes, a complete fresh read of the exact ref
must prove the requested postcondition before continuing. Other uncertain
delivery, cancellation, malformed output, and transport timeouts stop the task.

The adapter matches the selected AX window to a unique process/bounds entry,
then pins the CLI window ID and process instance. Snapshots from another window
are rejected. It never passes `--headed`. Partial observations remain marked
partial; large Mail trees can still exhaust the upstream observation budget.
The first version prioritizes Mail's message pane and keeps native control
available for unsupported apps and workflows.

The CLI and macOS helper are pinned to the official **v1.3.1 Apple Silicon**
release. Run `bash scripts/fetch-agent-desktop.sh` before the usual app build to
fetch the checksum-verified archive. `build-app.sh` embeds the prepared bundle,
its Apache-2.0 license and provenance; it does not download dependencies itself.
An absent bundle produces a clear error in preview mode and does not affect
native mode. The integration uses subprocess argument arrays (no shell), sends
text values on stdin, caps responses, and imposes a process-group deadline.

Each preview run uses a private temporary `AGENT_DESKTOP_HOME`, without traces
or screenshot artifacts. Upstream snapshot/ref metadata can contain private
UI text on disk; Brian removes its run directory on normal completion, error,
or cancellation. An app crash can leave temporary metadata for OS cleanup.
No mailbox data or snapshots are included in this repository.

Validation: 71 Swift tests passed, including reference/role mapping, document
rows remaining read-only, wrong-window rejection, delivery-disposition checks,
and subprocess stdin/stderr handling. In a live background Mail run, Brian
searched for an invoice, used the bundled CLI to click a result, read its
message pane, and returned the subject. An independent fresh content read
confirmed that subject, and the window inventory reported Mail was not focused.
Calculator remained usable during the task. This establishes that sampled
hybrid workflow, not universal headless compatibility or all-native replacement.

Upstream: https://github.com/vercel-labs/agent-desktop/releases/tag/v1.3.1

### Companion and preview fixes (0.8.1)

The pet uses one opaque body silhouette, with connected animated legs. Only
specific visible targets move it: whole-window inspection, offscreen geometry,
stale queued events, and app switches cannot send it to an unrelated edge.
Preview actions obtain live ref bounds; cached bounds are never used to move
the pet. The highlight and pet respect the foreground selected window.

Mail's “Top Results” and “All Results” section headings are read-only context,
even though upstream advertises Click. Selecting the former was reproduced as
`ACTION_FAILED` / `AXSelected` / `delivery_uncertain`. It is not a message row.
Unresolved failures name the affected operation; system logs retain only action,
code, operation, and delivery metadata, not mailbox content.

Mail query replacement clears and reads back the exact Accessibility search
field before inserting text. It does not rely on background Cmd+A, which was
observed leaving part of the previous query and appending the next search.

Validation for 0.8.1: 75 Swift tests pass, including Mail section-heading
exclusion, complete/pinned postcondition verification, and live/visible target
geometry. The signed app was relaunched and its existing grants refreshed.
The live invoice regression advanced through clean query replacements and
selected message rows without the reproduced heading-selection failure.
The floating companion was visually checked for an opaque, seam-free body.
The bounded live run was stopped with the original prompt preserved before
verifying a full invoice answer. This validates these fixes, not general
invoice-retrieval accuracy.

### Reference-style virtual cursor (0.9.0)

The working companion now becomes a small pink pointer with a round Brian badge,
following the Grok Bot cursor reference supplied for this change. The arrow tip
marks the center of a fresh visible action target, rather than placing a pet
beside the entire control. The badge flips inward at display edges without
clamping or moving the tip. Cursor mode is click-through and sits above menus;
it never moves the user's physical pointer. Invalidated targets return Brian
to its compact waiting position, and completion restores the normal pet.

A brief pulse indicates an input attempt, not successful task completion.
Read-only inspection does not pulse. Reduced Motion disables pulse animation
and travel; existing explicit action confirmation and result verification remain.
The large target ring is removed, and window-inspection outlines are lighter.

Research: the supplied screenshot establishes the arrow/badge/glow treatment.
The [Grok Bot computer guide](https://docs.x.ai/grok-bot/computer-and-apps)
provides the broader watching/control context. This change applies the cursor
pattern to Brian's local desktop interaction; it does not introduce Grok's
cloud computer or claim to reproduce animation timing from a still image.

Validation: 78 Swift tests pass. New cases verify exact tip positioning and
inward badge placement on primary/negative-coordinate displays and all corners.
The actual SwiftUI cursor artwork was rendered and reviewed on light and dark
backgrounds, including the pulse and mirrored edge state.

### Automatic app choice (0.9.0)

Users describe the outcome; they do not choose an app, window mode, or backend.
The local planner receives all supported installed apps and can choose another
app with `open_app`. The harness routes `search_mail` to Apple Mail automatically,
chooses the app's focused/main or sole window, and pins its identity before any
control action. It never picks the first of several ambiguous documents.

The bundled agent-desktop adapter is selected internally when available; native
control handles its existing Mail, keyboard and vision paths. A missing bundle
uses native control before any action. Unknown or partially delivered failures
are not retried through a different backend. App changes discard stale refs and
observations. Background operation remains the default; foreground-only input
requests an explicit handoff, raises and verifies the exact intended window,
then returns to window-scoped operation. A deliberate new-window shortcut makes
the next observation identify the new active document.

The 84-test Swift suite covers automatic window choice, email/app routing,
foreground handoff classification, and a scripted planner switching apps and
verifying the requested result. Earlier manual-window/preview instructions above
are historical; the picker is removed in this version.

Live validation: after a fresh app launch with no preselected target, the invoice
request automatically chose Mail and entered its control loop. The bar exposed
only a read-only working-app label. The bounded check was stopped after routing
verification, with the user's draft preserved; it was not a full invoice-answer
evaluation.

## Local memory (0.10.0)

Brian now checkpoints tasks and retrieves verified, app-scoped procedures from
`~/.brian/memory.sqlite`. Retrieval combines FTS5 with a bundled, pinned
BAAI/bge-small-en-v1.5 embedding model. The local Qwen planner prepares English
retrieval queries while preserving original names and identifiers. Task examples
and source evidence stay out of reusable planner guidance; verified completion
can reinforce a small curated procedure library.

See [memory architecture, controls, build instructions and limits](docs/memory.md)
and the [synthetic multilingual retrieval evaluation](docs/memory-evaluation.json).

## Preserve macOS permissions across updates

The app previously used ad-hoc signing. Apple documents that this ties its designated
requirement to one specific code version, so rebuilding can invalidate an otherwise
enabled Accessibility entry. Normal full builds now require a stable signing identity
and fail before changing the existing app if none is configured.

Install an Apple Development identity (local development) or Developer ID Application
identity (direct distribution), including its private key, through your Apple developer
account/Xcode or your team's existing signing setup. Keep using the same signing lineage,
bundle identifier and app location across builds. No valid identity was installed on
this Mac when this change was made; no certificate or private key was created automatically.

```sh
security find-identity -v -p codesigning
export BRIAN_SIGNING_IDENTITY='EXACT CERTIFICATE NAME OR SHA1 FROM THE LIST'
bash scripts/build-app.sh --runtime-bundle "$PWD/dist/planner-runtime/mac-control"
```

`--signing-identity` is also supported. Switching from the current ad-hoc build to stable
signing requires a final one-time permission refresh. Subsequent compatible signed
updates should retain access; this has not yet been verified locally because the
certificate setup is outstanding. This is identity signing, not a complete notarized
distribution pipeline. The existing runtime keeps its bundled dependency signatures.

`--shell-only` retains ad-hoc signing for UI/CI builds. Explicit `--ad-hoc` allows a full
disposable development build, with the known permission-reset consequence. Neither is
the normal update path for an app with granted permissions.

Reference: [Apple TN3127: code-signing requirements](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements).

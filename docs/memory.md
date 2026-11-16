# Local memory (0.10.0)

Brian stores memory in `~/.brian/memory.sqlite`, created on the first planner task.
No memory is sent to a server. The database is mode 0600; a newly created `.brian`
directory is mode 0700. It is ordinary local SQLite, not an encrypted vault.

## Records and boundaries

- `preferences`: explicit user settings; exact key lookup by task category.
- `tasks`: exact task ID, original request, English retrieval query, goal, attempted
  actions, pending action, bounded textual observations, search progress, and status.
  Checkpoints are inspectable after restart; automatic replay/resumption is deliberately
  not implemented. A crash or cancellation can leave the last checkpoint marked running;
  that status is not evidence that work completed.
- `memories`: verified procedure/recovery lessons, app/task applicability, original
  wording, exact terms, source task ID, successful reuse count, and 90-day expiry.
  Procedures and lessons share a table with a `kind` column.
- `vectors`: rebuildable per-memory index, pinned model/revision and content hash.
- `memory_fts` and `retrievals`: keyword index and retrieval audit (query, selected IDs,
  app, actual retrieval mode). No screenshot bytes are stored or embedded.

The original request is never replaced by an English translation. Names, identities,
organizations, identifiers, filenames and exact UI labels remain in source records.
The planner requests exact substrings from Qwen and validates them against the request;
Latin identifiers and quoted labels are additionally preserved deterministically.
Qwen may still transliterate a name in its English prose: the original is appended to
the semantic query and remains available, unchanged, for keyword matching.

Task records and source evidence are **not** searched as reusable memory. Neither prior
recipients nor dates can enter planner context through a retrieved example: only generic
procedure summaries are returned. Dates and action parameters still come from the current
request and current observations. Assessment receives fresh evidence, never memory as proof.
Current conversation follow-up handling is a separate existing mechanism.

## Retrieval

1. The existing local Qwen3.5-4B generates an English procedure-search query and category
   from the current request alone, without historical conversation.
2. Exact preferences and current-task checkpoints use direct lookup.
3. Reusable candidates must match user and app, be verified, and not expired. Task category
   further filters candidates; an unspecified/general category permits matching-app procedures.
4. FTS5 uses the original wording, English query and task category. BGE embeds the English
   query plus task category, and only generic English memory summaries (not original episodes).
5. Reciprocal-rank fusion combines the two ranked lists, returning at most four summaries.
   A cosine floor of 0.50 is an initial relevance heuristic, **not** a correctness probability.
   Up to 500 eligible recent records are searched; brute-force vector similarity suits this
   small initial library. No vector extension or external database is needed.
6. Cached retrieval is refreshed if app or external database version changes. Missing/broken
   embeddings fall back to FTS5 and record that mode. Memory errors do not fail computer actions.

Model: [BAAI/bge-small-en-v1.5](https://huggingface.co/BAAI/bge-small-en-v1.5), revision
`5c38ec7c405ec4b44b94cc5a9bb96e735b38267a`, ONNX Runtime 1.23.2 CPU, 384-dimensional
normalized CLS vectors. Queries use the model's retrieval instruction; passages do not.
The bundled weights/tokenizer are verified against their manifest checksums. Runtime model
loading is local-only; downloads occur only in the explicit build preparation step.

## What learns automatically

The first version is deliberately conservative. Only the harness's accepted completion can
reinforce one of four curated, parameter-free English procedures: inspecting email content,
varying stalled email searches, re-reading edited documents, and verified vision recovery.
The relevant actions must have occurred in the same app. Repeated completed tasks increment
success counts; duplicate completion events do not. Unsupported failures remain in task
records, not generalized into potentially false instructions. No model-written lessons or
arbitrary instructions from emails/screens are automatically promoted.

This is a working memory foundation, not open-ended self-training. It cannot establish that
Qwen's completion judgment is semantically correct in every case. Adding a wider reviewed
procedure library and measuring real task success are follow-up work. No weight updates occur.

## Inspect and manage

From the repository, Python's standard library is sufficient:

```sh
python3 PlannerRuntime/memory.py show
python3 PlannerRuntime/memory.py preference email_app com.apple.mail
python3 PlannerRuntime/memory.py forget MEMORY_ID
python3 PlannerRuntime/memory.py clear
```

The bundled runtime exposes the same commands through `mac-control memory ...`.
`show` includes original task text and observed source excerpts: treat exports as personal data.
`forget` removes that reusable memory and its vector/index entry; task audit records remain.
`clear` removes all this user's preferences, tasks, memories and retrieval records. It does not
purge external backups. There is no memory management chat command or settings UI yet.

## Build and validate

Install `PlannerRuntime/requirements-memory.txt` into `.runtime-build/embedding-deps` using
Python 3.12 pip, matching the existing research runtime, without changing that environment.
For this Mac, whose available pip runs under Python 3.9, wheel-only installation was:

```sh
python3 -m pip install --timeout 120 --ignore-requires-python \
  --target .runtime-build/embedding-deps --platform macosx_14_0_arm64 \
  --python-version 3.12 --implementation cp --abi cp312 --only-binary=:all: \
  --no-deps -r PlannerRuntime/requirements-memory.txt
```

The target runtime supplies numpy, protobuf and packaging. `--ignore-requires-python` above
is only for the installer interpreter; the downloaded wheels execute under Python 3.12.
`scripts/build-planner-runtime.sh` downloads the pinned model if missing and bundles both
weights and dependencies. `scripts/prepare-embedding.py OUTPUT` can prepare it explicitly.

Run unit/regression tests with `python3 -m unittest discover -s PlannerRuntime -p 'test_*.py'`
and `swift test`. `scripts/evaluate-memory.py` accepts `--planner-model`, `--embedding-model`
and `--output`; it uses real Qwen/BGE with a temporary synthetic database and never reads email.
Make the isolated embedding dependencies available through `PYTHONPATH` for this script.

[Recorded evaluation](memory-evaluation.json): eight synthetic requests across English,
Chinese, Japanese, Spanish, French and German retrieved the appropriate app procedure with
FTS5 and hybrid retrieval; original terms were retained and old date/recipient details excluded.
One additional lexical-gap query, “Locate correspondence,” had zero FTS5 hits and one hybrid hit.
The corpus is tiny and tests were used during development; this is a smoke/regression evaluation,
not a general accuracy benchmark. It does not validate multilingual Mac-control task completion.
The first run exposed invoice misclassification and name transliteration; the final prompt,
exact-term validation and category-assisted retrieval address the observed cases.

The frozen executable supports `memory-self-test`, which checks bundled BGE inference,
SQLite/FTS and hybrid retrieval against temporary synthetic data without opening any app.

Final build validation: 88 Swift tests and 41 Python tests passed. The packaged
`memory-self-test` passed with real BGE/FTS5 hybrid retrieval. A separate frozen MCP
smoke test generated an English query using Qwen, persisted a checkpoint, and ended
with `needs_input` without creating a reusable memory. Brian 0.10.0 built and passed
code-signature verification. No real email task was executed for this change.

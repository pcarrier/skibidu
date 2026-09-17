# skibidu

A **Chibi Scheme** program that asks TypeSafe's **Jev** model to construct a program from an empty AST, then revises it until every subtree has an explicit approval in context and all acceptance tests pass. The default target is a tiny arithmetic interpreter: `(calc expression)` evaluates integers and binary `+` / `*` expressions, including arbitrary nesting. Jev builds the dispatch and recursion; Chibi supplies integer arithmetic. Generated code cannot use `eval`.

There is no initial implementation template. Jev chooses every import, definition, helper, list, identifier, and literal. `targets/arithmetic.scm` contains a prose specification, examples, and interface vocabulary only. The handwritten implementations in `tests/reference-calc.scm` and `tests/reference-program.scm` are exclusively test fixtures; the live generator never reads them or supplies them to Jev. The original R7RS-small interpreter remains available as an optional target.

## Run

From the repository root, on Linux:

```sh
nix develop
export TYPESAFE_API_KEY='…'
make test
make generate
make demo
```

The devShell provides Chibi Scheme 0.12, curl, GNU make, coreutils, and bubblewrap. No Chicken installation or eggs are needed. Candidate acceptance execution uses Linux namespaces through bubblewrap; the shell exposes Chibi on Darwin too, but the generation/acceptance runner currently requires Linux. It checks the sandbox before making paid calls.

`make generate` is live, with no mock mode. Optional settings:

```sh
make generate ARGS='--max-passes 16 --max-calls 1200 --out generated/calc.scm'
make generate ARGS='--fresh'
chibi-scheme generate.scm --resume runs/RUN/checkpoint.scm
chibi-scheme generate.scm --help
```

Bare `make` runs the local tests. Use `make generate` for a live run; it prints the path to `runs/<run-id>/report.md` immediately. Open that file during or after execution to see the pass outcomes, decisions, edits, failures, costs, and timing.

After an interruption such as HTTP 429, rerun `make generate` with the same output path and target to resume automatically. `<output>.resume.scm` points to the latest checkpoint; it is updated atomically and removed after successful generation. `--fresh` starts again from one hole, and `--resume` selects a particular checkpoint. Each execution keeps its own report and trace, with a link to the checkpoint it resumed. Resuming preserves the AST and recovery history, reruns acceptance tests, and obtains fresh approvals; pass/call limits and usage totals restart for that execution. Older checkpoints without recovery history still load.

`TYPESAFE_MODEL` defaults to `jev-latest`; `TYPESAFE_URL` defaults to `https://api.typesafe.ai/v1/systemone`. Credentials are passed to curl through stdin, never in process arguments or traces. A failed provider request does not produce a successful artifact.

`make generate` defaults to `targets/arithmetic.scm` and writes `generated/calc.scm`. `make demo` reads the five expressions in `examples/arithmetic.scm` and prints `7`, `5`, `20`, `14`, and `21`. Run your own expressions with:

```sh
printf '%s\n' '(+ 2 (* 3 4))' | chibi-scheme run-calc.scm generated/calc.scm
```

The generated program defines just `calc`, accepting already parsed, valid data with this grammar:

```text
expression := integer | (+ expression expression) | (* expression expression)
```

`run-calc.scm` handles reading and printing. The target needs no parser, environments, macros, library system, or CLI. Acceptance checks allow only `(scheme base)` imports and reject direct `eval`, loading, and includes. The harness uses host `eval` only to look up the generated procedure; it never evaluates arithmetic expressions on the candidate's behalf.

For the original interpreter, which uses Chibi's native R7RS-small evaluator, hygienic macros, and libraries:

```sh
make generate ARGS='--target targets/r7rs-small.scm'
chibi-scheme run.scm generated/interpreter.scm examples/demo.scm
chibi-scheme run.scm generated/interpreter.scm --eval '(write (+ 20 22))'
printf '(write (+ 20 22))' | chibi-scheme run.scm generated/interpreter.scm
```

`run.scm` only loads the generated program and calls its `main` procedure. The generated AST implements input handling, reading, evaluation, output capture, error propagation, and the CLI. No imports or interpreter functions are prepended when writing the artifact.

The R7RS target keeps its original default output, `generated/interpreter.scm`. Existing checkpoints remain usable: include `--target targets/r7rs-small.scm` when resuming them. Arithmetic uses a separate default output and resume pointer.

## Construction and contextual rebaking

Jev is a typed decision model rather than a free-text code generator. Each question offers a generic one-node constructor: a list of a chosen length, a vector, a dotted pair, a symbol, a literal, or the next character of a new identifier/string/number. List children start as new holes. Common Scheme names and constants reduce spelling calls; invented names can be reused after their first occurrence. The vocabulary is not a table of solution fragments.

Descent follows generic S-expression structure, not a complete Scheme grammar. Identifier spelling filters out delimiters and invalid prefixes. Token selection and spelling offer `restart` to rebuild that node; spelling also offers `backspace`, including at the length limit. A malformed partial token in an older checkpoint can therefore be corrected on resume. Construction problems and the model's recovery choices appear in the trace and Markdown report.

Construction questions explicitly ask what to build next, identify the node's position, and explain constructors in Scheme terms. At the root, list length counts top-level forms; inside a form it counts all children, including the operator. Vocabulary groups describe the names they offer. These are syntax and vocabulary hints, not implementation fragments.

The arithmetic target additionally constrains basic syntax: top-level forms are lists beginning with `import`, `define`, or `begin`; imports use the permitted `(scheme base)` library; definition names and function-signature positions require identifiers. Syntax keywords must occupy expression-head positions rather than appear as bare expression values; quoted data remains unrestricted. It offers existing names directly to avoid needless spelling. Every node is still selected through construction; no function body or seed program is supplied. This is a limited grammar, not a full Scheme parser: binding lists and conditional clauses remain generic, and acceptance tests check the completed program. The original R7RS target keeps generic construction.

Every construction question below the root also offers `backtrack`. Jev then chooses an ancestor: `up:1` replaces the parent, `up:2` the grandparent, and so on through the root. Construction resumes there immediately, without finishing the old candidate first. Overlapping replacements merge into the outermost requested ancestor; other batched choices inside that subtree are discarded and reported. Unaffected siblings are preserved. At depths over 255, the selector offers the nearest 254 ancestors and the root; repeated backtracking can reach the others.

If construction visits the identical AST shape three times within its last 32 steps, the generator records a construction cycle and asks Jev to choose an ancestor to rebuild. Fresh hole IDs are ignored in this comparison, so backtracking cannot hide repeated shapes. This detects short `restart` and `backspace` loops without imposing a call/pass cutoff. Cycle detection is local to the current descent; checkpoints still preserve the AST and recovery history.

Prompts retain the eight most recent abandoned subtree summaries, newest first, with source previews limited to 240 characters plus a truncation marker. Backtracking, token restarts, and review replacements/deletions update that history. It is guidance about past contexts, not a permanent ban on a choice. Full edits remain in the trace, and changing recovery history invalidates previous approvals.

1. Start with **one root hole**. Its children will be the program's top-level forms.
2. Descend recursively. Complete earlier program forms, operators, and binding positions before dependent bodies. Batch independent construction questions against one shared full-AST context.
3. Execute the complete candidate in a fresh, timed Chibi sandbox. Feed acceptance failures back to Jev, including test input, expected output, actual output, and errors.
4. Ask for `keep` or `rebake` at **every node**, including tokens, empty lists, and the program root. `keep` explicitly confirms no change is wanted in that subtree in the current context.
5. Offer edits at the outermost disjoint rejected subtrees. Jev can replace, append, prepend, delete a child, or descend to a smaller edit. This ensures a rejected program structure can be repaired even when its tokens are also rejected. `retain` postpones editing and does **not** approve a rejected subtree. Newly introduced holes go through construction again.
6. Repeat testing and confirmation. A change anywhere in the AST or acceptance results invalidates **all** previous approvals. Cached approvals are reused only when the entire AST and feedback are unchanged. Passing tests alone cannot settle a run, and approvals cannot override failing tests.

Each request contains the full current AST, goal, phase, path-specific questions, and compact test feedback. Identical worker failures (such as an undefined name preventing every test from running) are grouped into one representative with an affected-case count. Feedback includes up to eight distinct failures, with long fields truncated to 700 characters and explicit grouped/omitted counts; the trace and Markdown report retain complete results. Per-input value mismatches and exceptions are not grouped. Feedback is labeled as belonging to the last completed candidate, before any ongoing edits. Reporting makes no model calls.

Independent questions share one request and its context. Character choices encode only `(append-char CHARACTER)`, avoiding up to 95 copies of the growing prefix; review descriptions are compact, and unchanged contextual approvals are reused. A local regression measures a 100-character spelling prefix's option JSON shrinking from 12,837 to 3,147 characters; this is a payload comparison, not measured token billing. The [TypeSafe API reference](https://docs.typesafe.ai/api) currently documents no prompt-cache control or cached-token usage field, so no provider caching discount is assumed. API-reported token usage remains the basis for cost reports.

There is **no default pass or model-call cutoff**: generation continues until acceptance tests pass and every subtree has contextual approval, or an error or structural limit stops execution. Set `--max-passes` and/or `--max-calls` for a resumable budget; zero means unlimited. Calls continue to incur provider charges while generation is running.

Default structural bounds: 2,048 AST nodes, depth 64, 16 children per list/vector, 128 spelling characters, 64 questions per batch. Limits stop the run with a checkpoint; they never count as model approval. Identifiers and strings can currently be spelled using printable ASCII, with ASCII character literals and generic numeric spelling. This bounds synthesis, not the resulting interpreter's Unicode support. Bounds are configurable through `--max-*` and `--batch-size`; width is capped at 96 and each question at 255 alternatives.

A fresh run can require many decisions. The larger R7RS interpreter fixture needs 358 construction calls for a 269-node program, even with every choice correct. The arithmetic target has much less behavior to implement, but fixture success is not evidence that Jev will converge. Checkpoints preserve the partial AST and hole IDs; resumed runs retest and obtain fresh approvals, and have their own usage totals.

## Reports, timing, and cost

Every generation run creates its own directory:

| File | Contents |
| --- | --- |
| `report.md` | Human-readable report, refreshed during execution, with pass overview, each model call, returned choices and confidence, edits, candidate source, acceptance failures, approval reuse/invalidation, costs, and timing. |
| `trace.jsonl` | Exhaustive event stream: exact requests/context/alternatives, responses and usage, HTTP attempts/results, AST edits, checkpoints, sandbox commands and source, test stdout/stderr/results, artifacts, and summary. |
| `checkpoint.scm` | Latest partial or complete AST, target contract, and resume state; created when construction starts. |
| `summary.scm` | Final token, cost, timing, call, retry, and completion counters, including failed runs. |

Console output shows the duration of **every completion**, including failed calls, plus tokens, estimated USD, and elapsed wall time **for each pass and at the end**. Completion durations cover the model call, including HTTP attempts, retry backoff, and response decoding. The Markdown report shows these durations alongside the choices or failure, and records individual HTTP attempt times and retry delays. The trace stores completion `duration_ms` on `response` and `completion-failed` events, and attempt `duration_ms` inside each `http-result` event's `details`.

If a pass is interrupted, its partial usage and time are printed too. Pass 1 includes construction; later passes include edits since the preceding review, tests, and confirmation. Total time also includes startup/reporting/artifact work before the final summary.

Costs use actual API-reported `input_tokens` and `output_tokens`. Defaults are **$0.042 per million input tokens and $0 per output token**, from the [TypeSafe pricing announcement](https://typesafe.ai/blog/introducing-system-one-models-and-jev), checked September 17, 2026. Override with `--input-rate` and `--output-rate`. Missing usage or failed HTTP attempts make the cost explicitly **incomplete**; zero reported tokens do not establish that the provider charged nothing. This is an estimate, not an invoice.

The report shows what Jev selected and when. The API returns typed choices and confidence, not prose reasoning; no explanation of hidden model reasoning is invented. See [TypeSafe's introduction](https://docs.typesafe.ai/introduction).

## Validation

`make test` exercises construction from a single hole, arbitrary identifiers/literals/pairs/vectors, dependency ordering, repeated contextual approvals, acceptance feedback, limits, token/cost accounting, process execution, and Markdown reports. Its test-only oracle builds both reference programs through the same one-node construction protocol, then exercises their acceptance suites and launchers. The arithmetic suite has 18 cases covering literals, both operators, nesting, negatives, zero, large integers, repeated calls, and deep recursion; regressions also verify failure feedback and rejection of `eval` shortcuts. A local curl fixture tests HTTP 429 retries, completion timing, automatic restart, and checkpoint cleanup, including seven seconds of retry backoff. All tests run without API requests or charges. Test reports are prominently labeled **test fixture**, never live Jev output.

Tests print their trace/report paths immediately, then stage updates and construction progress every two seconds. Reports collect every event, coalesce rapid refreshes to twice per second, and flush immediately at pass boundaries, failures, and completion.

Regressions from a live arithmetic run cover rejected parents being offered edits, descent to smaller repairs, automatic recovery from repeated token restarts/backspaces, and grouping duplicate load failures. Fixture tests verify these mechanics; they do not prove the model will choose a working implementation.

The 47 runtime acceptance cases cover definitions across calls, tail calls, hygienic macros, continuations, values, records, promises, ports, Unicode reader escapes, rational/big integers, bytevectors, libraries and renamed imports/exports, guest eval, cyclic equality, error propagation, cleanup, and CLI input modes. They are regression coverage, not a proof of full R7RS conformance. Language implementation comes from [Chibi Scheme](https://synthcode.com/scheme/chibi/).

Candidates run with a deadline, an empty environment, no network namespace access, a read-only Nix store, and a writable temporary directory. The API key and repository are not exposed to candidate code. The normal `run.scm` and `run-calc.scm` launchers execute programs with the caller's ordinary permissions.

Live provider requests have succeeded, but a complete Jev-generated interpreter has not yet passed acceptance. Local fixture tests demonstrate the generator mechanics and Chibi integration; they do not establish that Jev will converge.

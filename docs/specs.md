# Spec Design

> Why these specs exist, how they're organized, and what it means for each one to pass.

## Philosophy

Every spec answers one question: **why should I trust this?**

Trust comes from evidence, and different claims need different kinds of evidence. "The loop terminates" is a mathematical claim — it needs a proof. "The parser handles all verify types" is a behavioral claim — it needs tests. "The code is well-structured" is a judgment call — it needs review.

qed's verification spectrum maps directly to these:

| Claim type            | Evidence           | Verification |
| --------------------- | ------------------ | ------------ |
| Mathematical property | Formal proof       | `proof`      |
| Observable behavior   | Deterministic test | `command`    |
| Design quality        | Expert judgment    | `agent`      |

The specs use the strongest verification type that fits each claim. Proofs where the property is provable, tests where behavior is observable, agent review where judgment is needed.

## No overlap between specs

Each spec owns a distinct concern. The build spec is the foundation — it verifies that everything compiles, tests pass, and proofs are complete. Other specs add criteria _beyond_ what build covers: formal proofs, structural assertions, and design reviews. No criterion appears in two specs.

## Layers

Specs are organized in layers. Each layer builds on the ones below it.

### 1. Build integrity (`build.spec.json`)

The foundation. Everything compiles, tests pass, no incomplete proofs. If this fails, nothing else matters. This is the only spec in JSON — it's simple, has no multi-line strings, and is the canonical example of a verify-mode spec.

### 2. State machine correctness (`state-machine.spec.toml`)

Fourteen formal proofs verify the state machine's mathematical properties, organized by what they guarantee:

- **Safety:** ready always advances, terminal states are absorbing, no skipped verification, iteration count bounded by maxIterations, integrity violations always produce terminal states and never produce passed
- **Invariants:** complete lifecycle ordering (5-way transition characterization), transition function is deterministic, iteration count is monotonically non-decreasing, state lifecycle phase never decreases
- **Liveness:** the loop terminates within maxIterations, every state-changing transition either terminates or strictly increases the progress measure
- **Correctness:** stuck detection fires iff repeated failures reach the threshold, ready state is never revisited

Building-block lemmas (fuel measures, stuck detection directions, specific transition paths) live in the proof files but are not spec criteria — they exist to support these results, not as independent guarantees. An agent review checks design quality (exhaustive matches, purity, edge cases).

### 3. Verify mode correctness (`verify-mode.spec.toml`)

Two formal proofs verify the type-level separation between modes: verify mode cannot carry a WorkerConfig or LoopConfig, and is independent of the state machine. Structural assertions check the schema and documentation.

### 4. Parser correctness (`parser.spec.toml`)

Six formal proofs verify parser correctness: schedule parsing accepts exactly the three valid strings and rejects everything else (`parseSchedule_iff`), the serializer↔parser roundtrip recovers the original spec exactly, TOML duplicate key rejection, and three TOML→JSON pipeline properties (totality, success implies valid parse, error propagation — currently skipped pending TSK-173). Building-block proofs (per-type roundtrips, array creation) live in the proof files. Agent reviews check the JSON and TOML parsers for data loss, correct defaults, and spec compliance.

### 5. Worker loop correctness (`worker-loop.spec.toml`)

Five formal proofs verify the worker loop execution engine: the loop drives the proven state machine exclusively (`step = transition`), empty failures leave the base prompt unchanged, non-empty failures extend (not replace) the base prompt, and shellQuote wraps correctly. An agent review checks the two-tier prompt model, shell safety, and terminal state handling.

### 6. CLI and output correctness (`cli.spec.toml`)

Four formal proofs verify output correctness: the result complete partition (every result is exactly one variant, predicates agree), the pass/fail decision (allPassed iff no failures), and the JSON output contracts (verify-mode and worker-loop JSON always contain the required fields). An agent review verifies CLI dispatch logic.

### 7. Verifier correctness (`verifier.spec.toml`)

Three formal proofs verify pure functions used in verification dispatch: `targetToModule` returns the module prefix iff the target has at least two dot-separated parts, `isValidModuleName` accepts only shell-safe identifier segments, and `containsSorry` detects exactly standalone sorry occurrences. An agent review verifies the dispatch logic: exhaustive match on all VerifyType constructors, platform-aware shell execution, output truncation preserving the most recent output, and correct result mappings.

### 8. Convention adherence (`conventions.spec.toml`)

Agent reviews check naming conventions (full variable names, no abbreviations), DRY compliance (no duplicated logic, no dead code), and documentation accuracy (AGENTS.md and CONVENTIONS.md consistent with the actual codebase).

### 9. Documentation accuracy (`docs.spec.toml`)

Generated docs (schema, format reference) must be fresh. Hand-written docs (architecture, README) must be consistent with the actual codebase. Agent reviews cross-reference docs against source.

## Design principles

**Every spec runs in verify mode.** qed's own specs have no worker — they verify existing code, not generate new code. Worker loop specs are for development workflows where an agent iterates toward passing criteria.

**No overlap.** Each criterion appears in exactly one spec. Build handles compilation and tests. Other specs handle proofs, structural checks, and reviews.

**Strongest verification available.** If a property is provable, prove it. Don't settle for a test when a proof is possible, even if the proof is trivial.

**Self-referential where possible.** qed verifies itself using its own verification types. The state machine spec uses `proof` criteria to check theorems about the state machine.

# Spec Design

> Why these specs exist, how they're organized, and what it means for each one to pass.

## Philosophy

Every spec answers one question: **why should I trust this?**

Trust comes from evidence, and different claims need different kinds of evidence. "The loop terminates" is a mathematical claim — it needs a proof. "The parser handles all verify types" is a behavioral claim — it needs tests. "The code is well-structured" is a judgment call — it needs review.

qed's verification spectrum maps directly to these:

| Claim type | Evidence | Verification |
|-----------|----------|-------------|
| Mathematical property | Formal proof | `proof` |
| Observable behavior | Deterministic test | `command` |
| Design quality | Expert judgment | `agent` |

The specs use the strongest verification type that fits each claim. Proofs where the property is provable, tests where behavior is observable, agent review where judgment is needed.

## No overlap between specs

Each spec owns a distinct concern. The build spec is the foundation — it verifies that everything compiles, tests pass, and proofs are complete. Other specs add criteria *beyond* what build covers: formal proofs, structural assertions, and design reviews. No criterion appears in two specs.

## Layers

Specs are organized in layers. Each layer builds on the ones below it.

### 1. Build integrity (`build.spec.json`)

The foundation. Everything compiles, tests pass, no incomplete proofs. If this fails, nothing else matters. This is the only spec in JSON — it's simple, has no multi-line strings, and is the canonical example of a verify-mode spec.

### 2. State machine correctness (`state-machine.spec.toml`)

Ten formal proofs verify the state machine's mathematical properties, organized by what they guarantee:

- **Safety:** terminal states are absorbing, no skipped verification, worker runs before verification
- **Liveness:** the loop terminates within maxIterations
- **Correctness:** iteration count is monotonic, stuck detection fires iff repeated
- **Invariants:** transition determinism, ready transience, phase monotonicity, iteration bound

An agent review checks design quality (exhaustive matches, purity, edge cases).

### 3. Verify mode correctness (`verify-mode.spec.toml`)

Two formal proofs verify the type-level separation between modes: verify mode cannot carry a WorkerConfig or LoopConfig, and verify mode is independent of the state machine. Structural assertions check the schema and documentation.

### 4. Parser correctness (`parser.spec.toml`)

An agent review checks that the parser faithfully maps JSON to the Spec type — no data loss, correct defaults, clear error messages. Build and test coverage is owned by the build spec.

### 5. CLI and verifier correctness (`cli.spec.toml`)

Agent reviews verify the CLI dispatch logic and verifier safety: correct argument parsing, error handling with `--json`, exit codes, and that the verifier safely sandboxes shell commands.

### 6. Documentation accuracy (`docs.spec.toml`)

Generated docs (schema, format reference) must be fresh. Hand-written docs (architecture, README) must be consistent with the actual codebase. Agent reviews cross-reference docs against source.

## Design principles

**Every spec runs in verify mode.** qed's own specs have no worker — they verify existing code, not generate new code. Worker loop specs are for development workflows where an agent iterates toward passing criteria.

**No overlap.** Each criterion appears in exactly one spec. Build handles compilation and tests. Other specs handle proofs, structural checks, and reviews.

**Strongest verification available.** If a property is provable, prove it. Don't settle for a test when a proof is possible, even if the proof is trivial.

**Self-referential where possible.** qed verifies itself using its own verification types. The state machine spec uses `proof` criteria to check theorems about the state machine.

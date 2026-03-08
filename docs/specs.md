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
| Design quality | Expert judgment | `agentReview` |

The specs use the strongest verification type that fits each claim. Proofs where the property is provable, tests where behavior is observable, agent review where judgment is needed.

## Layers

Specs are organized in layers. Each layer builds on the ones below it.

### 1. Build integrity (`build.spec.json`)

The foundation. Everything compiles, tests pass, no incomplete proofs. If this fails, nothing else matters.

This is the only spec in JSON — it's simple, has no multi-line strings, and is the canonical example of a verify-mode spec.

### 2. State machine correctness (`state-machine.spec.toml`)

The core of qed is a deterministic state machine. Five formal proofs verify its mathematical properties: termination, stuck detection, monotonicity, no skipped verification, and absorbing terminal states. An agent review checks design quality (exhaustive matches, purity, edge cases).

This spec uses the full verification spectrum — command (compilation), proof (properties), and agentReview (design). It's the spec that makes qed different from a shell script.

### 3. Parser correctness (`parser.spec.toml`)

The parser is the bridge between human-authored spec files and the typed `Spec` type. If the parser misparses, the wrong thing gets verified. Tests cover every verify type, both execution modes, default handling, and error paths. TOML multi-line string roundtrip tests verify that the main reason TOML support exists actually works.

### 4. Verify mode correctness (`verify-mode.spec.toml`)

Verify mode is the simpler of qed's two execution modes. The spec checks that the type system explicitly models it (not implicit via `Option`), that the schema enforces its constraints, and that documentation describes it accurately.

### 5. Documentation accuracy (`docs.spec.toml`)

Documentation that contradicts the code is worse than no documentation. This spec verifies that generated docs (schema, format reference) are fresh, and that hand-written docs (architecture, README) are consistent with the actual codebase.

## Design principles

**Every spec runs in verify mode.** qed's own specs have no worker — they verify existing code, not generate new code. Worker loop specs are for development workflows where an agent iterates toward passing criteria.

**No trivial criteria.** Each criterion must test something that could meaningfully fail. "File exists" is not useful. "Parser handles all 5 verify types" is.

**Strongest verification available.** If a property is provable, prove it. Don't settle for a test when a proof is possible.

**Self-referential where possible.** qed verifies itself using its own verification types. The state machine spec uses `proof` criteria to check theorems about the state machine. The parser spec uses `command` criteria to run parser tests.

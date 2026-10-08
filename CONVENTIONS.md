# Code Conventions

Shared conventions for all tskovlund repositories.

## How to read these

- **Rules encode intent; follow the intent.** A rule satisfied by a workaround
  is a rule broken: `any` to "use TypeScript", a docstring that restates the
  signature to "document the public API", a test that asserts a constant to
  "cover the module". When the letter and the intent conflict, do what the
  intent asks and say so in the PR
- **Nothing is maintained for its own sake.** Every line of code, test,
  documentation and configuration must earn its place. What adds no value is
  deleted, not kept current
- **Generate over hand-maintain.** Anything derivable from a source of truth
  is generated from it, with a check that fails when the copy drifts: API
  references from docstrings, release notes from commits, CI matrices from a
  versions file
- **Proper fixes over workarounds.** Solve at the root cause. When a workaround
  is unavoidable (the cause is outside our control), say so in the code and
  track it so it can go once a real fix exists

## Code

- **Explicit types.** The reader never guesses a type: full annotations in
  Python, no `var` in C#, no `auto` where the type is not obvious. Escape
  hatches (`Any`, `any`, casts) only at true boundaries such as JSON, and
  narrowed immediately
- **Full names.** `measure_index` not `m`, `exception` not `exc`, `message`
  not `msg`. Intent is read, not inferred
- **No magic constants.** Ports, protocol versions, error codes, timeouts are
  named
- **One source of truth.** Shared logic lives in one place; prefer a base
  class or a shared function over copy-paste
- **Single responsibility.** A file, class or function does one thing; an
  interface exists where it decouples something that varies
- **Comments and docstrings explain semantics**: what a value means, which
  constraints hold, why the code does what it does. They never retell what
  the signature already says
- **Idempotency.** Scripts, migrations and deployments are safe to run twice
- **Tooling enforces the mechanical rules**: import order, formatting,
  linting, type checking, no debug printing (`no-console`, Ruff `T20`).
  Warnings fail CI; a warning that stays becomes invisible

## Configuration

- **Externalize what varies by environment or that users may change**;
  hardcode what is truly constant
- **Pick the mechanism for the situation**: environment variables for secrets
  and deployment, config files for complex settings, CI variables for
  build-time values

## Errors and resilience

- **Surface problems.** Errors are visible, never swallowed
- **Validate at boundaries** (API inputs, external data); trust internal code
- **Structured logging** through the platform's logging framework, with
  consistent levels
- **Retry policies come from a library** (tenacity, Polly). A single bounded
  reconnect that a protocol calls for is fine; a homebrew retry loop with
  backoff is not

## APIs

- **Predictable and consistent**: one naming scheme, one error shape, one
  return convention across every endpoint or tool
- **Version deliberately.** Whether versioning adds value depends on the
  technology; make it a decision, not a default

## Dependencies

- **Battle-tested libraries for problems with known edge cases** (auth,
  retries, serialization); **no dependency for a few lines of our own code**
- **Vet before adding**: maintenance activity, security record, transitive
  dependency count. Ask the maintainer when unsure
- **Lockfiles committed** (`uv.lock`, `package-lock.json`, `flake.lock`)
- **Direct dependencies pinned to compatible ranges with a major upper bound**
  (`"websockets>=14.0,<15"`, `"^14.0.0"`), so Renovate produces reviewable PRs
  instead of silent breakage. GitHub Actions pinned to a commit SHA with a
  version comment
- **Renovate and CodeQL in CI** where available. No secrets in code

## Testing

- **Cover the critical paths.** A test exists to catch a specific regression:
  every behavior a user would notice failing, every error path production can
  hit, every edge case that has bitten. A coverage percentage is not a goal
- **Every test earns its place.** No trivial tests, no tests of library
  behavior, no assertions on constants. Shared logic is tested once, not per
  subclass
- **Unit tests are fast and offline**; they work on a plane
- **Integration tests exercise the real thing** (a real MuseScore, a real
  database via Testcontainers) where a mock cannot catch the failure that
  matters. They are separate and opt-in so the fast loop stays fast
- **Naming and shape**: `test_<action>_<expected outcome>`, cased per
  language; Arrange / Act / Assert
- **One gate, identical locally and in CI**: lint, format, typecheck and tests
  behind one command (`devbox run check`, `mix precommit`, whatever the repo's
  tooling provides). Dev shells (Devbox, Nix) make the tooling identical
- **Archetype minimums**: static websites get accessibility checks (axe) and
  end-to-end navigation; Lean projects get `lake test` and a no-`sorry` check;
  Nix configurations get `nix flake check --all-systems`

## Git and releases

- **Conventional commits**, enforced by the shared `commit-msg` hook:
  `feat`, `fix`, `docs`, `chore`, `refactor`, `test`, `ci`, `style`, `perf`,
  `build`, `revert`, with an optional scope
- **Branch, PR, required checks, squash merge** is the default; one small PR
  per change. A personal configuration repo may allow direct pushes to `main`;
  that is a per-repo ruleset decision, made deliberately
- **Releases are tags** (`vX.Y.Z`, semver, `0.x` until the API is stable).
  Release notes live on the GitHub release: drafted from the conventional
  commits since the previous tag, curated by hand, published once. No
  hand-maintained changelog file

## Documentation

- **Docs state what the code does not.** Rationale, constraints, how to
  operate the thing. Anything derivable is generated (see above). No counts
  or version lists that drift; describe or point at the source instead
- **Diataxis as a thinking tool**: tutorial, how-to, reference, explanation.
  Not a filing system
- **README sells, `docs/` teaches.** The README says what the project is,
  why it matters, and gets a reader running in a few commands. Details live in
  `docs/` and are linked; a small repo may need no `docs/`
- **CONTRIBUTING.md when external contributors are expected**: dev setup,
  the gate, the PR process; it links to CONVENTIONS.md rather than restating
  it
- **Author section at the bottom of every README**:
  `Name — [site](url) · [email](mailto:email)`, followed by a License section
  in licensed repos

## Repositories

- **Language conventions apply** (`src/` layout in Python, the framework's
  structure elsewhere)
- **AGENTS.md in every repo** holds the instructions for AI agents (Claude
  Code reads it directly; no CLAUDE.md symlink). Repos are de-personalized
  factsheets; kammer's AGENTS.md is the deliberate exception, an
  owner-specific operations manual
- **Shared CI via `tskovlund/.github`**: reusable workflows instead of
  duplicated configuration
- **Conventions are synced into each repo** as its CONVENTIONS.md, general
  plus the repo's language modules, so every contributor and agent sees them
  without leaving the repo

<!-- Language-specific conventions are appended per-repo by the sync workflow -->

## Lean 4

### Language

- **`autoImplicit` off** — all variables explicitly declared. Prevents
  accidental implicit arguments in theorem statements
- **Pure core, IO shell** — state machine transition functions are pure and
  total. IO lives at the edges (CLI, process spawning, file I/O)
- **No `sorry` in proofs** — `sorry` is an axiom that admits any proposition.
  CI rejects any `sorry` in proof files. Use `sorry` only during development,
  never in merged code
- **Proofs alongside code** — theorems about a module live in the same file or
  a `Proofs/` subdirectory. Keep proofs close to the definitions they reason
  about
- **`lake-manifest.json` committed** — this is the lockfile for Lake
  dependencies. Always commit it
- **No `partial` when avoidable** — `partial` functions are opaque to the
  kernel and cannot be unfolded in proofs. Use mutual recursion for termination
  through nested inductives (e.g., `List` inside an inductive type)

### Naming

- **Full variable names in signatures** — `config` not `cfg`, `context` not
  `ctx`, `iteration` not `iter`. Hypothesis bindings may be shorter when scope
  is narrow
- **`h` prefix for hypotheses** — with descriptors: `hterm` (terminality),
  `hbound` (bound), `hiter` (iteration). Plain `h` only when there is exactly
  one hypothesis in scope
- **snake_case for theorems** — descriptive: `terminal_absorbing`,
  `stuck_iff_threshold`, `loop_terminates`
- **Proof file names match module** — `FinalStates.lean` for proofs about
  final states, `Termination.lean` for termination proofs

### Proof style

- **`unfold` over `simp only [f]`** for unfolding definitions — `unfold` is
  explicit about intent and doesn't reduce further. Use `simp` for rewriting,
  not unfolding
- **Structured proofs** — prefer `cases ... with | constructor => ...` over
  tactic chains. Each case should be readable independently
- **Extract lemmas when reused** — if two theorems need the same intermediate
  result, extract it. Inline when used once
- **Mutual recursion for nested inductives** — when a type contains `List T`
  where `T` is the type itself, define functions as a mutual block
  (`toJson`/`toJsonList`) so Lean can verify structural termination

## qed Specs

Conventions for repositories using qed as their spec framework.

### Spec design

- **Specs contain top-level results only** — building-block lemmas and helper
  theorems live in proof files but are not spec criteria. A spec criterion
  should be a guarantee a stakeholder cares about, not an intermediate step
- **Use the strongest verification type available** — `proof` for mathematical
  properties, `command` for observable behavior, `agent` for design judgment.
  Don't settle for a test when a proof is possible
- **No overlap between specs** — each criterion appears in exactly one spec.
  One spec owns one concern
- **Every spec must answer: why should I trust this?** — if you can't explain
  what trust a criterion provides, it doesn't belong in the spec

### Spec format

- **`.spec.toml`** for specs with multi-line strings (agent prompts, human
  instructions). TOML's `"""..."""` and comments make these readable
- **`.spec.json`** for simple command-only specs with no multi-line content
- **Schema reference** — every spec file starts with
  `#:schema ../docs/spec.schema.json` (TOML) or `"$schema"` (JSON)

### Proof criteria

- **Target fully qualified theorem names** — e.g.,
  `Qed.Proofs.Termination.loop_terminates`
- **Description states the guarantee, not the implementation** — "The loop
  always reaches a terminal state within maxIterations transitions" not
  "loop_terminates theorem passes"
- **Group by property type** — safety (bad things don't happen), liveness
  (good things eventually happen), correctness (the right things happen)

### Agent criteria

- **Prompts are review checklists** — numbered items, each independently
  verifiable
- **Reference specific files** — "Review Qed/StateMachine.lean" not "Review
  the state machine code"
- **Ask for negative findings** — "Report any unreachable code paths, missing
  error handling, or UX issues"

# Contributing

## Prerequisites

- [Devbox](https://www.jetify.com/devbox) (provides elan via Nix)
- Or: [elan](https://github.com/leanprover/elan) directly

## Development setup

**Option 1: Devbox + direnv (recommended)**

```bash
git clone https://github.com/tskovlund/qed.git
cd qed
direnv allow        # automatically enters devbox environment
lake build          # first run downloads Lean toolchain (~500MB)
```

**Option 2: Devbox shell**

```bash
git clone https://github.com/tskovlund/qed.git
cd qed
devbox shell
lake build
```

**Option 3: elan directly**

```bash
git clone https://github.com/tskovlund/qed.git
cd qed
elan toolchain install leanprover/lean4:v4.28.0
git config core.hooksPath .githooks
lake build
```

## Running checks

```bash
devbox run build      # lake build
devbox run test       # lake test
devbox run check      # build + test (same as CI)
```

Or directly (inside devbox shell / after direnv allow):

```bash
lake build            # build — also type-checks all proofs
lake test             # run the test suite
qed                   # run the binary (.lake/build/bin on PATH via .envrc)
```

## Code style

See [CONVENTIONS.md](CONVENTIONS.md) for full standards. Key points:

- `autoImplicit` is off — declare all variables explicitly
- No `sorry` in merged code — proofs must be complete
- Pure core, IO shell — state machine logic has no side effects

## Tests

Tests live in `Tests/` and run via `lake test`. The test driver exits non-zero on failure.

Proofs are also tests — `lake build` verifies all theorems. If a proof has `sorry`, CI fails.

## Architecture decisions

- **Deterministic orchestrator** — the core loop is a pure state machine. LLMs are tools used _by_ the orchestrator, not the control plane
- **Proofs alongside code** — theorems about a module live in the same file or a `Proofs/` subdirectory
- **Typed verification dispatch** — each AC specifies its verification type at definition time, not at runtime
- **Backend-agnostic agents** — worker and verifier agent commands are configurable shell commands, defaulting to Claude CLI

## Pull requests

1. Create a feature branch from `main`
2. Make changes, run `lake build` and `lake test`
3. Ensure no `sorry` in any merged proof files
4. Push and create PR using the [template](.github/PULL_REQUEST_TEMPLATE.md)
5. Address review comments, iterate until CI passes and reviews are resolved
6. Squash and merge

### Prompt-request PRs

For AI-driven implementation: create a PR with a clear task description in the body, including acceptance criteria. An agent picks it up, implements, and pushes. The PR goes through normal review.

Requirements for prompt-request PRs:

- Title prefixed with `[prompt]`
- Body contains a clear task description
- Acceptance criteria defined (ideally as a qed spec)
- Target branch specified

## Issue templates

Use the appropriate template when creating issues:

- **Enhancement** — new features or improvements
- **Bug** — something broken
- **Research** — exploratory investigation

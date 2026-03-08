# Contributing

## Prerequisites

- [Devbox](https://www.jetify.com/devbox) (provides elan via Nix)
- Or: [elan](https://github.com/leanprover/elan) directly

## Development setup

```bash
git clone https://github.com/tskovlund/qed.git
cd qed
devbox shell          # or: direnv allow
lake build            # first run downloads Lean toolchain (~500MB)
lake test             # run tests
```

## Running checks

```bash
devbox run build      # lake build
devbox run test       # lake test
devbox run check      # build + test (same as CI)
```

## Code style

See [CONVENTIONS.md](CONVENTIONS.md) for full standards. Key points:

- `autoImplicit` is off — declare all variables explicitly
- No `sorry` in merged code — proofs must be complete
- Pure core, IO shell — state machine logic has no side effects

## Tests

Tests live in `Tests/` and run via `lake test`. The test driver exits non-zero on failure.

Proofs are also tests — `lake build` verifies all theorems. If a proof has `sorry`, CI fails.

## Pull requests

1. Create a feature branch
2. Make changes, run `lake build` and `lake test`
3. Push and create PR using the template
4. Address review comments, iterate until CI passes and reviews are resolved

### Prompt-request PRs

For AI-driven implementation: create a PR with the task description in the body. An agent picks it up, implements, and pushes. The PR goes through normal review.

## Issue templates

Use the appropriate template when creating issues:

- **Enhancement** — new features or improvements
- **Bug** — something broken
- **Research** — exploratory investigation

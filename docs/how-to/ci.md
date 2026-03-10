# How to add qed to CI

Run `qed verify` in your CI pipeline to check all specs on every push.

## GitHub Actions

```yaml
- name: Verify specs
  run: qed verify
```

This recursively finds all `.spec.json` and `.spec.toml` files in the repository and verifies them. qed exits with code 0 if all criteria pass, 1 if any fail, and 2 on configuration errors.

For JSON output (useful for downstream parsing):

```yaml
- name: Verify specs
  run: qed verify --json
```

## Controlling what runs in CI

Each criterion has a `ci` field that controls when it runs:

```toml
[[criteria]]
description = "Build passes"
verify = { type = "command", run = "make build" }
ci = "always"      # every CI run (default for automatable types)

[[criteria]]
description = "Manual sign-off"
verify = { type = "human", instruction = "Check the UI" }
ci = "manual"      # never in CI (default for human)
```

| Value | When it runs |
|-------|-------------|
| `always` | Every CI run (PRs, pushes, merge queue) |
| `trunk` | Only when the default branch changes |
| `manual` | Only via explicit `qed run` |

## Agent criteria in CI

Agent criteria (`type = "agent"`) require an LLM backend. If the agent command isn't available in CI, the criterion is skipped (not failed). To run agent criteria in CI, ensure the agent command is installed and any required API keys are available as secrets.

## Verifying a specific directory

```yaml
- name: Verify specs
  run: qed verify specs/
```

This limits verification to specs in the `specs/` directory and its subdirectories.

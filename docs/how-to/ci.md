# How to add qed to CI

Run `qed verify` in your CI pipeline to check all specs on every push.

## GitHub Actions

```yaml
- name: Verify specs
  run: qed verify --pin
```

CI mode is auto-detected — when the `CI` environment variable is set to `true` (which GitHub Actions, GitLab CI, and most CI providers do automatically), qed runs in `--auto` mode: only `schedule = "always"` criteria run. The `--pin` flag ensures each spec matches its git-committed version — results from locally modified specs are rejected.

qed recursively finds all `.spec.json` and `.spec.toml` files in the repository and verifies them. It exits with code 0 if all criteria pass, 1 if any fail, and 2 on configuration errors.

For thorough CI runs (e.g. nightly) that include agent reviews:

```yaml
- name: Verify specs (extended)
  run: qed verify --extended --pin
```

For JSON output (useful for downstream parsing):

```yaml
- name: Verify specs
  run: qed verify --pin --json
```

## Controlling what runs in CI

Each criterion has a `schedule` field that controls when it runs:

```toml
[[criteria]]
description = "Build passes"
verify = { type = "command", run = "make build" }
schedule = "always"        # every run (default for command/property/proof)

[[criteria]]
description = "Code review"
verify = { type = "agent", prompt = "Review the implementation." }
# schedule defaults to "heavy" for agent criteria

[[criteria]]
description = "Design review"
verify = { type = "human", instruction = "Check the UI" }
# schedule defaults to "manual" for human criteria
```

| Value    | When it runs                               | Excluded by            | Default for              |
| -------- | ------------------------------------------ | ---------------------- | ------------------------ |
| `always` | Every run (CI, hooks, explicit)            | —                      | command, property, proof |
| `heavy`  | Explicit invocation and `--extended`       | `--auto`               | agent                    |
| `manual` | Only via explicit invocation without flags | `--auto`, `--extended` | human                    |

## Criteria that require external tools

qed never silently skips verification — if a criterion's tool isn't available (agent binary, proof checker, property testing framework, etc.), the criterion **fails**. This applies to all verification types equally.

To exclude criteria from CI where their tools aren't installed, set `schedule = "manual"`:

```toml
[[criteria]]
description = "Termination proof"
schedule = "manual"
verify = { type = "proof", prover = "lean4", target = "Proofs.Termination.loop_terminates" }
```

This keeps the criteria in the spec but only runs them via explicit invocation without flags, not in CI or hooks. To run them in CI, ensure the required tools are installed and any API keys are available as secrets.

Alternatively, use `skip` to disable a criterion entirely (in all environments) with a documented reason:

```toml
[[criteria]]
description = "Exchange rate refresh"
skip = "flaky, investigating #42"
verify = { type = "command", run = "pytest tests/test_refresh.py" }
```

Skipped criteria show `[SKIP]` in output and do not affect the overall pass/fail result.

## Verifying a specific directory

```yaml
- name: Verify specs
  run: qed verify specs/
```

This limits verification to specs in the `specs/` directory and its subdirectories.

## Ensuring manual criteria get validated

Human criteria default to `schedule = "manual"`, which means they never run in automated contexts. This is intentional — they require interactive input. Agent criteria default to `schedule = "heavy"` — excluded from default CI but includable with `--extended`.

To run everything, including manual criteria:

```sh
qed verify specs/
```

No flags means no filtering — all criteria run regardless of schedule.

**Recommended practices:**

- **Use `--pin` in CI** to ensure specs match their committed version. Without it, a modified-but-uncommitted spec could pass verification against the wrong definition.
- **Use `--extended` for nightly CI** to include agent reviews. This catches issues that deterministic checks miss.
- **Before merging structural PRs**, run `qed verify` without flags to validate all criteria including human sign-offs.
- **Override the default** if a criterion should run more frequently. Set `schedule = "always"` explicitly to include it in every CI run.

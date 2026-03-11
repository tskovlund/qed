# How to use human verification

Human criteria require interactive sign-off — a person reviews the result and accepts or rejects it. This is for things that can't be automated: visual checks, UX review, subjective quality assessments.

## Basic usage

```toml
[[criteria]]
description = "UI renders correctly on mobile"
verify = { type = "human", instruction = "Check that the responsive layout works on iPhone SE and Galaxy S24." }
```

When qed encounters a human criterion, it prints the instruction and waits for your response:

```
    → UI renders correctly on mobile
      Check that the responsive layout works on iPhone SE and Galaxy S24.
    Accept? [y/n]: y
```

`y`/`yes` → pass, `n`/`no` → fail. Invalid input is rejected and the prompt repeats. Case-insensitive.

## In worker loops

Human criteria in worker loop specs create a human-in-the-loop development flow: the AI worker writes code, automated criteria check correctness, and a human reviews the result.

```toml
name = "implement-dashboard"

[worker]
prompt = "Build a responsive dashboard with charts for the metrics API"

[[criteria]]
description = "Dashboard builds and tests pass"
verify = { type = "command", run = "npm run build && npm test" }

[[criteria]]
description = "Dashboard looks correct"
verify = { type = "human", instruction = "Open localhost:3000 and verify the layout, chart rendering, and responsiveness." }
```

If the human rejects, the failure feeds back to the worker for another iteration — just like any other criterion.

## In CI

Human criteria default to `schedule = "manual"`, so they are automatically excluded from `--ci` and `--local` (pre-push hooks). They only run during explicit invocation without flags. See [How to add qed to CI](ci.md#ensuring-manual-criteria-get-validated) for recommendations on validating them regularly.

## Non-interactive contexts

If stdin is not available (piped input, background process), human criteria fail with "non-interactive context". This follows qed's principle of never silently skipping verification.

To explicitly skip human criteria, use `skip`:

```toml
[[criteria]]
description = "Design review"
skip = "deferred to post-launch review"
verify = { type = "human", instruction = "Review the visual design." }
```

# How to use agent verification

Agent criteria spawn an independent LLM to review code against a prompt. The agent's verdict determines pass/fail.

## Basic usage

```toml
[[criteria]]
description = "Code follows conventions"
verify = { type = "agent", prompt = "Review src/ for consistent naming, error handling, and test coverage." }
```

The agent receives the prompt via `$QED_VERIFIER_PROMPT` and must end its response with a JSON verdict:

```json
{"pass": true}
```

or

```json
{"pass": false, "reason": "explanation"}
```

## Custom model

```toml
[[criteria]]
description = "Security review"
verify = { type = "agent", prompt = "Review for OWASP top 10 vulnerabilities.", model = "claude-opus-4-6" }
```

The default model is `claude-opus-4-6`. Override per-criterion when you need a specific model.

## Custom agent command

By default, qed uses Claude CLI. To use a different backend:

```toml
[[criteria]]
description = "Code review"

[criteria.verify]
type = "agent"
prompt = "Review the implementation for correctness."
command = "my-agent --prompt"
```

Your command receives two environment variables:
- `$QED_VERIFIER_PROMPT` — the review prompt
- `$QED_VERIFIER_SYSTEM_PROMPT` — instructions for the verdict format

The command must write to stdout. qed parses the last `` ```json `` block for the verdict.

## Graceful degradation

If the agent command isn't installed (exit code 127, "not found", etc.), the criterion is **skipped**, not failed. This means specs with agent criteria work in environments without LLM access — the agent criteria are simply skipped.

## Writing effective prompts

- **Be specific** — "Review for exhaustive match arms and error handling" beats "Review the code"
- **Reference files** — "Review `src/parser.lean` for..." focuses the agent
- **State what to check** — list the properties you care about, not just "review"
- **Keep it focused** — one concern per criterion, not a laundry list

# How to choose between JSON and TOML specs

Both formats parse into the same types. The choice is about readability.

## Use JSON for simple specs

JSON works well when your spec has only command criteria with short strings:

```json
{
  "name": "build",
  "criteria": [
    {
      "description": "Project compiles",
      "verify": { "type": "command", "run": "make build" }
    },
    {
      "description": "Tests pass",
      "verify": { "type": "command", "run": "make test" }
    }
  ]
}
```

File extension: `.spec.json`

## Use TOML for multi-line strings

TOML's `"""..."""` syntax makes agent prompts and human instructions readable:

```toml
name = "code-quality"

[[criteria]]
description = "Code follows conventions"

[criteria.verify]
type = "agent"
prompt = """
Review the codebase for:

1. Consistent naming conventions
2. Proper error handling (no swallowed exceptions)
3. Test coverage for edge cases
4. No hardcoded magic constants

Report any violations with file paths and line numbers.
"""
```

File extension: `.spec.toml`

TOML also supports comments, which is useful for documenting why criteria exist:

```toml
# This criterion catches regressions in the parser's handling of
# optional fields — a common source of bugs after schema changes.
[[criteria]]
description = "Parser roundtrip is complete"

[criteria.verify]
type = "proof"
prover = "lean4"
target = "Qed.Proofs.Roundtrip.spec_roundtrip"
```

## Schema autocomplete

Both formats support editor autocomplete via JSON Schema:

- JSON: add `"$schema": "docs/spec.schema.json"` at the top level
- TOML: add `#:schema docs/spec.schema.json` as the first line

See [spec-format.md](../spec-format.md) for the complete field reference.

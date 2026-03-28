import DocGen.Schema
import DocGen.Markdown

set_option autoImplicit false

/-! # CLI entry point for doc generation

Usage:
  lake exe docgen schema    → JSON Schema (docs/spec.schema.json)
  lake exe docgen markdown  → Markdown reference (docs/spec-format.md)
-/

def main (args : List String) : IO UInt32 := do
  match args with
  | ["schema"] =>
    IO.println DocGen.Schema.generate
    return 0
  | ["markdown"] =>
    let schema := DocGen.Schema.generate
    match DocGen.Markdown.generate schema with
    | .ok md =>
      IO.println md
      return 0
    | .error message =>
      IO.eprintln s!"ERROR: failed to generate markdown from schema: {message}"
      return 1
  | _ =>
    IO.eprintln "Usage: docgen <schema|markdown>"
    return 1

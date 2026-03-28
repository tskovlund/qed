import Lean.Data.Json
import Qed.Types
import Qed.Output

set_option autoImplicit false

namespace Qed.Error

open Lean Qed

/-- Convert a byte offset to (line, column), both 1-based.
    Iterates through the source character-by-character, tracking UTF-8 byte
    positions. Shared by TOML and JSON parse error paths. -/
def byteToLineCol (source : String) (bytePos : Nat) : Nat × Nat :=
  let rec scan (chars : List Char) (pos : Nat) (line : Nat) (column : Nat) : Nat × Nat :=
    if pos >= bytePos then (line, column)
    else match chars with
      | [] => (line, column)
      | char :: rest =>
        if char == '\n' then scan rest (pos + char.utf8Size) (line + 1) 1
        else scan rest (pos + char.utf8Size) line (column + 1)
  scan source.toList 0 1 1

/-- Get source line text, line number, and column from source string and byte offset.
    Returns (lineNumber, column, lineText). -/
def sourceContext (source : String) (bytePos : Nat) : Nat × Nat × String :=
  let (lineNumber, column) := byteToLineCol source bytePos
  let allLines := source.splitOn "\n"
  let lineText := (allLines.getD (lineNumber - 1) "").trimAsciiEnd.toString
  (lineNumber, column, lineText)

/-- Build a code frame: numbered source line + caret pointer.

    Output format:
    ```
      |
    3 | naem = "my-spec"
      |     ^
      |
    ``` -/
def codeFrame (lineNumber : Nat) (lineText : String) (column : Nat) : String :=
  let lineNumberText := toString lineNumber
  let gutterWidth := lineNumberText.length
  let gutter := String.ofList (List.replicate gutterWidth ' ')
  let padding := String.ofList (List.replicate column ' ')
  s!"{gutter} |\n{lineNumberText} | {lineText}\n{gutter} |{padding}^"

/-- Format an ErrorInfo for human-readable display (stderr).

    Full output:
    ```
    error: expected '=' after key
     --> spec.toml:3:5
      |
    3 | naem = "my-spec"
      |     ^
      |
    hint: check for typos in key names
    ```

    Minimal output (message only):
    ```
    error: file not found
    ``` -/
def formatError (error : ErrorInfo) : String :=
  let header := s!"{Output.ansiRed}error:{Output.ansiReset} {error.message}"
  let location := match error.file, error.line, error.column with
    | some file, some line, some column => s!"\n --> {file}:{line}:{column}"
    | some file, some line, none => s!"\n --> {file}:{line}"
    | some file, none, none => s!"\n --> {file}"
    | none, some line, some column => s!"\n --> line {line}, column {column}"
    | _, _, _ => ""
  let frame := match error.line, error.sourceLineText, error.column with
    | some lineNumber, some lineText, some column =>
      "\n" ++ codeFrame lineNumber lineText column
    | _, _, _ => ""
  let hintLine := match error.hint with
    | some hint => s!"\n{Output.ansiCyan}hint:{Output.ansiReset} {hint}"
    | none => ""
  header ++ location ++ frame ++ hintLine

/-- Format an ErrorInfo as a JSON object for --json mode.
    Only includes fields that are present. -/
def formatErrorJson (error : ErrorInfo) : Json :=
  let baseFields : List (String × Json) := [("error", Json.str error.message)]
  let locationFields := match error.file, error.line, error.column with
    | some file, some line, some column =>
      [("location", Json.mkObj [
        ("file", Json.str file),
        ("line", Json.num line),
        ("col", Json.num column)])]
    | some file, some line, none =>
      [("location", Json.mkObj [
        ("file", Json.str file),
        ("line", Json.num line)])]
    | some file, none, none =>
      [("location", Json.mkObj [
        ("file", Json.str file)])]
    | _, _, _ => []
  let hintFields := match error.hint with
    | some hint => [("hint", Json.str hint)]
    | none => []
  Json.mkObj (baseFields ++ locationFields ++ hintFields)

/-- Extract byte offset from Lean's Json.parse error format.
    `"offset 42: expected '}'"` → `some (42, "expected '}'")` -/
def extractJsonOffset (errorMessage : String) : Option (Nat × String) :=
  let offsetPrefix := "offset "
  if errorMessage.startsWith offsetPrefix then
    -- Split on first colon: "42: expected '}'" → ["42", " expected '}'"]
    let rest := (errorMessage.drop offsetPrefix.length).toString
    match rest.splitOn ":" with
    | [] => none
    | [_] => none
    | offsetString :: messageParts =>
      match offsetString.trimAscii.toString.toNat? with
      | some offset =>
        let message := (String.intercalate ":" messageParts).trimAscii.toString
        some (offset, message)
      | none => none
  else none

/-- Report a structured error in the appropriate output format. -/
def reportError (format : OutputFormat) (error : ErrorInfo) : IO Unit :=
  match format with
  | .jsonLines =>
    Output.emitJsonLine (Output.jsonLineEvent "error"
      [("message", Lean.Json.str error.message)])
  | .json =>
    IO.println (formatErrorJson error |>.pretty 2)
  | .text =>
    IO.eprintln (formatError error)

end Qed.Error

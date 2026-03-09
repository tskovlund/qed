namespace Qed.TomlConverter

/-- Convert a TOML string to a JSON string using Python's tomllib.

Python 3.11+ includes tomllib in the standard library — no pip
install needed. This avoids writing a TOML parser in Lean. -/
private def pythonCmd : String :=
  if System.Platform.isWindows then "python" else "python3"

def tomlToJson (tomlContent : String) : IO (Except String String) := do
  let result ← IO.Process.output
    { cmd := pythonCmd
      args := #["-c",
        "import sys, tomllib, json; data = tomllib.loads(sys.stdin.read()); print(json.dumps(data))"] }
    (input? := some tomlContent)
  if result.exitCode != 0 then
    return .error s!"TOML parse error: {result.stderr.trimAscii.toString}"
  else
    return .ok result.stdout.trimAscii.toString

end Qed.TomlConverter

import Qed.TomlParser

namespace Qed.TomlConverter

/-- Convert a TOML string to a JSON string using a pure Lean parser.
    No external dependencies required. -/
def tomlToJson (tomlContent : String) : IO (Except String String) := do
  return Qed.TomlParser.tomlToJson tomlContent

end Qed.TomlConverter

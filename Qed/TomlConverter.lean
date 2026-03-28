import Qed.TomlParser
import Qed.Types

namespace Qed.TomlConverter

/-- Convert a TOML string to a JSON string using a pure Lean parser.
    No external dependencies required. -/
def tomlToJson (tomlContent : String) : Except ErrorInfo String :=
  Qed.TomlParser.tomlToJson tomlContent

end Qed.TomlConverter

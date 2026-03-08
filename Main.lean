import Qed

def version : String := "0.1.0-dev"

def main (args : List String) : IO UInt32 := do
  match args with
  | ["version"] =>
    IO.println s!"qed {version}"
    return 0
  | ["help"] =>
    IO.println "qed — typed spec-driven development with deterministic verification"
    IO.println ""
    IO.println "Usage:"
    IO.println "  qed run <spec-file>    Run the AC loop"
    IO.println "  qed parse <spec-file>  Parse and validate a spec file"
    IO.println "  qed version            Print version"
    IO.println "  qed help               Show this help"
    return 0
  | _ =>
    IO.println s!"qed {version} — run `qed help` for usage"
    return 0

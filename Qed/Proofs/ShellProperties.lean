import Qed.Shell
import Qed.WorkerLoop

set_option autoImplicit false

namespace Qed.Proofs.ShellProperties

open Qed

/-! # Shell command construction properties

`Shell.buildShellCommand` is the shell-injection surface: it splices
caller-supplied environment variable values into a string that is handed to
`/bin/sh -c`. These theorems pin down that every value passes through
`shellQuote`, and that the command itself is always the trailing segment.

`WorkerLoopProperties` proves `shellQuote_wraps`/`shellQuote_empty` against
`WorkerLoop.shellQuote`, which is a re-export shim. `shellQuote_shim_eq`
below ties that shim to the real definition so the coverage cannot drift
apart silently. -/

/-- The `WorkerLoop.shellQuote` re-export is exactly `Shell.shellQuote`. -/
theorem shellQuote_shim_eq (s : String) :
    WorkerLoop.shellQuote s = Shell.shellQuote s := rfl

/-- With no environment variables, the command is passed through untouched —
    no wrapping, no prefix, nothing for a shell to reinterpret. -/
theorem buildShellCommand_empty_env (command : String) :
    Shell.buildShellCommand [] command = command := rfl

/-- A single environment variable expands to exactly one `export` with a
    shell-quoted value, followed by the unmodified command. -/
theorem buildShellCommand_single (name value command : String) :
    Shell.buildShellCommand [(name, value)] command =
      "export " ++ name ++ "=" ++ Shell.shellQuote value ++ "; " ++ command := rfl

/-- Every non-empty environment list puts the command last, after a `"; "`
    separator — the command is never spliced into the middle of an export. -/
theorem buildShellCommand_command_last (entry : String × String)
    (rest : List (String × String)) (command : String) :
    ∃ exports, Shell.buildShellCommand (entry :: rest) command =
      exports ++ "; " ++ command :=
  ⟨_, rfl⟩

/-- Two environment variables still quote both values and keep the command
    last. Generalising this to an arbitrary-length list needs induction over
    `String.intercalate`'s accumulator, whose `go` helper Lean does not expose
    as an accessible constant — see the follow-up note in
    `docs/proven-properties.md`. -/
theorem buildShellCommand_pair (firstName firstValue secondName secondValue command : String) :
    Shell.buildShellCommand [(firstName, firstValue), (secondName, secondValue)] command =
      "export " ++ firstName ++ "=" ++ Shell.shellQuote firstValue ++ "; " ++
      "export " ++ secondName ++ "=" ++ Shell.shellQuote secondValue ++ "; " ++ command := by
  -- `String.intercalate` joins left-associatively; restate in that shape
  -- (definitionally true) and let `append_assoc` normalise both sides.
  have joined : Shell.buildShellCommand
      [(firstName, firstValue), (secondName, secondValue)] command =
      (("export " ++ firstName ++ "=" ++ Shell.shellQuote firstValue) ++ "; " ++
       ("export " ++ secondName ++ "=" ++ Shell.shellQuote secondValue)) ++ "; " ++ command := rfl
  rw [joined]
  simp only [String.append_assoc]

end Qed.Proofs.ShellProperties

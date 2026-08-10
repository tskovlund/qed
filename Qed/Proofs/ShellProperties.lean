import Qed.Shell

set_option autoImplicit false

namespace Qed.Proofs.ShellProperties

open Qed

/-! # Shell quoting and command construction

`Shell.buildShellCommand` splices caller-supplied environment values into a
string handed to `/bin/sh -c`, with `Shell.shellQuote` as the only barrier. -/

/-- Decodes the body of a POSIX single-quoted word, up to its closing quote.
    `none` is a quote that would end the word early and expose the rest of the
    value to the shell — the shape `shellQuote` must never produce. -/
def readBody : List Char → Option (List Char)
  | [] => none
  | ['\''] => some []
  | '\'' :: '\\' :: '\'' :: '\'' :: rest => ('\'' :: ·) <$> readBody rest
  | '\'' :: _ => none
  | c :: rest => (c :: ·) <$> readBody rest

/-- Decodes one complete single-quoted shell word. -/
def readWord : List Char → Option (List Char)
  | '\'' :: rest => readBody rest
  | _ => none

theorem readBody_escapeQuotes (chars : List Char) :
    readBody (Shell.escapeQuotes chars ++ ['\'']) = some chars := by
  induction chars with
  | nil => rfl
  | cons c rest ih =>
    by_cases hquote : c = '\''
    · subst hquote; simp [Shell.escapeQuotes, readBody, ih]
    · simp [Shell.escapeQuotes, readBody, hquote, ih]

private theorem quote_toList : ("'" : String).toList = ['\''] := rfl

theorem shellQuote_toList (s : String) :
    (Shell.shellQuote s).toList = '\'' :: (Shell.escapeQuotes s.toList ++ ['\'']) := by
  simp [Shell.shellQuote, quote_toList]

/-- **Main safety theorem:** every string quotes to exactly one shell word that
    decodes back to it. No input can close the quote early, so nothing a caller
    supplies is ever read as syntax. -/
theorem shellQuote_is_one_word (s : String) :
    readWord (Shell.shellQuote s).toList = some s.toList := by
  rw [shellQuote_toList]
  simp [readWord, readBody_escapeQuotes]

theorem shellQuote_empty : Shell.shellQuote "" = "''" := rfl

/-- Values reach the shell only through `shellQuote`. -/
theorem buildShellCommand_single (name value command : String) :
    Shell.buildShellCommand [(name, value)] command =
      "export " ++ name ++ "=" ++ Shell.shellQuote value ++ "; " ++ command := rfl

/-- The command is always the trailing segment, never spliced into an export. -/
theorem buildShellCommand_command_last (entry : String × String)
    (rest : List (String × String)) (command : String) :
    ∃ exports, Shell.buildShellCommand (entry :: rest) command =
      exports ++ "; " ++ command :=
  ⟨_, rfl⟩

end Qed.Proofs.ShellProperties

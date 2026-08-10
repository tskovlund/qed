set_option autoImplicit false

namespace Qed.Ignore

/-- Path to the ignore file (relative to project root). -/
def ignoreFileName : String := ".qedignore"

/-- Scan the body of a bracket expression, after any leading `!`.
    Returns whether `character` is in the set, and the pattern remaining after
    the closing `]`. `none` when there is no closing `]`. -/
def scanBracket (negate : Bool) (character : Char) :
    List Char → Bool → Option (Bool × List Char)
  | [], _ => none
  | ']' :: tail, matched => some (if negate then !matched else matched, tail)
  | low :: '-' :: high :: tail, matched =>
    if high == ']' then
      let hit := character == low || character == '-'
      some (if negate then !(matched || hit) else matched || hit, tail)
    else
      scanBracket negate character tail
        (matched || (low ≤ character && character ≤ high))
  | c :: tail, matched => scanBracket negate character tail (matched || c == character)

/-- Match a single character against a bracket expression like `[abc]`,
    `[!abc]`, or `[a-z]`. -/
def matchBracket (patternChars : List Char) (character : Char) :
    Option (Bool × List Char) :=
  match patternChars with
  | '!' :: tail => scanBracket true character tail false
  | chars => scanBracket false character chars false

/-- A bracket expression consumes at least its closing `]`, so what remains is
    strictly shorter. This is what makes `matchGlob` terminate. -/
theorem scanBracket_shrinks {negate : Bool} {character : Char}
    {chars : List Char} {matched result : Bool} {rest : List Char}
    (h : scanBracket negate character chars matched = some (result, rest)) :
    rest.length < chars.length := by
  fun_induction scanBracket negate character chars matched <;> simp_all <;> omega

theorem matchBracket_shrinks {chars : List Char} {character : Char}
    {result : Bool} {rest : List Char}
    (h : matchBracket chars character = some (result, rest)) :
    rest.length < chars.length := by
  unfold matchBracket at h
  split at h
  · exact Nat.lt_succ_of_lt (scanBracket_shrinks h)
  · exact scanBracket_shrinks h

-- The `h` binder below is used only by `decreasing_by`, which the
-- unused-variable linter does not scan.
set_option linter.unusedVariables false in
/-- Match a pattern against a name, character by character.
    `*` consumes any run of characters, including `/`; `?` consumes exactly one
    character that is not `/`; `[…]` consumes one character from the class. -/
def matchGlob : List Char → List Char → Bool
  | [], str => str.isEmpty
  | '*' :: patRest, [] => matchGlob patRest []
  | '*' :: patRest, c :: strRest =>
    matchGlob patRest (c :: strRest) || matchGlob ('*' :: patRest) strRest
  | _ :: _, [] => false
  | '?' :: patRest, c :: strRest => c != '/' && matchGlob patRest strRest
  | '[' :: patRest, c :: strRest =>
    match h : matchBracket patRest c with
    | some (true, remaining) => matchGlob remaining strRest
    | _ => false
  | p :: patRest, c :: strRest => p == c && matchGlob patRest strRest
termination_by pat str => pat.length + str.length
decreasing_by
  all_goals simp_all
  all_goals try omega
  all_goals (have := matchBracket_shrinks h; omega)

/-- Match a name against a glob pattern (fnmatch-style).
    Supports: `*` (any sequence, separators included), `?` (any single
    character except `/`), `[abc]` (character class), `[!abc]` (negated class),
    `[a-z]` (range). -/
def fnmatch (pattern : String) (name : String) : Bool :=
  matchGlob pattern.toList name.toList

/-- Parse a .qedignore file into a list of patterns.
    Format: one pattern per line, `#` for comments, blank lines skipped. -/
def parseIgnoreFile (contents : String) : List String :=
  contents.splitOn "\n"
    |>.map (·.trimAsciiEnd.toString)
    |>.filter fun line => !line.isEmpty && !line.startsWith "#"

/-- Read ignore patterns from a .qedignore file in the given directory.
    Returns an empty list when no .qedignore file exists — no defaults. -/
def readIgnorePatterns (directory : System.FilePath) : IO (List String) := do
  let path := directory / ignoreFileName
  if ← path.pathExists then
    let contents ← IO.FS.readFile path
    return parseIgnoreFile contents
  else
    return []

/-- Whether a name should be ignored according to the given patterns.
    Patterns are processed in order. A `!` prefix negates (un-ignores).
    A name is ignored if the last matching pattern is not negated. -/
def shouldIgnore (patterns : List String) (name : String) : Bool :=
  let rec go (remaining : List String) (ignored : Bool) : Bool :=
    match remaining with
    | [] => ignored
    | pattern :: rest =>
      if pattern.startsWith "!" then
        let negated := (pattern.drop 1).toString
        if fnmatch negated name then go rest false
        else go rest ignored
      else
        if fnmatch pattern name then go rest true
        else go rest ignored
  go patterns false

end Qed.Ignore

namespace Qed.Ignore

/-- Path to the ignore file (relative to project root). -/
def ignoreFileName : String := ".qedignore"

/-- Match a single character against a bracket expression like `[abc]` or `[!abc]`.
    Returns `(matched, remainingPattern)` where remainingPattern is after the `]`.
    Returns `none` if the bracket expression is malformed (no closing `]`). -/
private def matchBracket (patternChars : List Char) (character : Char)
    : Option (Bool × List Char) :=
  let (negate, rest) := match patternChars with
    | '!' :: tail => (true, tail)
    | chars => (false, chars)
  let rec go (remaining : List Char) (matched : Bool) : Option (Bool × List Char) :=
    match remaining with
    | [] => none
    | ']' :: tail =>
      let result := if negate then !matched else matched
      some (result, tail)
    | low :: '-' :: high :: tail =>
      if high == ']' then
        let hit := character == low || character == '-'
        let result := if negate then !(matched || hit) else (matched || hit)
        some (result, tail)
      else
        go tail (matched || (low ≤ character && character ≤ high))
    | c :: tail =>
      go tail (matched || c == character)
  go rest false

/-- Inner loop for fnmatch. Backtracking on `*` means structural recursion
    cannot be proved — each backtrack resets `pat` to a saved position while
    advancing `str` by one, so termination is O(p×n) but not structurally
    decreasing. Marked partial since this is runtime-only code. -/
private partial def fnmatchGo (pat : List Char) (str : List Char)
    (starPat : Option (List Char)) (starStr : Option (List Char)) : Bool :=
  match pat, str with
  | [], [] => true
  | [], _ =>
    match starPat, starStr with
    | some sp, some ss =>
      match ss with
      | [] => false
      | _ :: rest => fnmatchGo sp rest (some sp) (some rest)
    | _, _ => false
  | '*' :: patRest, _ =>
    fnmatchGo patRest str (some patRest) (some str)
  | '?' :: patRest, c :: strRest =>
    if c == '/' then
      match starPat, starStr with
      | some sp, some ss =>
        match ss with
        | [] => false
        | _ :: rest => fnmatchGo sp rest (some sp) (some rest)
      | _, _ => false
    else
      fnmatchGo patRest strRest starPat starStr
  | '[' :: patRest, c :: strRest =>
    match matchBracket patRest c with
    | some (true, remaining) => fnmatchGo remaining strRest starPat starStr
    | _ =>
      match starPat, starStr with
      | some sp, some ss =>
        match ss with
        | [] => false
        | _ :: rest => fnmatchGo sp rest (some sp) (some rest)
      | _, _ => false
  | p :: patRest, c :: strRest =>
    if p == c then
      fnmatchGo patRest strRest starPat starStr
    else
      match starPat, starStr with
      | some sp, some ss =>
        match ss with
        | [] => false
        | _ :: rest => fnmatchGo sp rest (some sp) (some rest)
      | _, _ => false
  | _ :: _, [] =>
    match starPat, starStr with
    | some sp, some ss =>
      match ss with
      | [] => false
      | _ :: rest => fnmatchGo sp rest (some sp) (some rest)
    | _, _ => false

/-- Match a name against a glob pattern (fnmatch-style).
    Supports: `*` (any sequence), `?` (any single char),
    `[abc]` (character class), `[!abc]` (negated class), `[a-z]` (range).
    Uses the two-pointer backtracking algorithm (iterative, O(p×n) worst case). -/
def fnmatch (pattern : String) (name : String) : Bool :=
  fnmatchGo pattern.toList name.toList none none

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

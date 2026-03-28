import Qed.Types
import Qed.Integrity
import Qed.Verifier
import Qed.Shell
import Lean.Data.Json

set_option autoImplicit false

namespace Qed.ContractLock

open Qed Lean

-- ═══════════════════════════════════════════════════════════════════
-- Lock file types
-- ═══════════════════════════════════════════════════════════════════

/-- A single locked artifact: a file path and its SHA-256 hash. -/
structure LockedArtifact where
  path : String
  hash : String
  deriving Repr, BEq

/-- Lock entry for a single criterion within a spec. -/
structure CriterionLock where
  description : String
  artifacts : List LockedArtifact
  deriving Repr, BEq

/-- Lock entry for an entire spec file. -/
structure SpecLock where
  specPath : String
  criteria : List CriterionLock
  deriving Repr, BEq

/-- The lock file structure. -/
structure LockFile where
  version : Nat := 1
  specs : List SpecLock
  deriving Repr, BEq

/-- Lock file path (relative to project root). -/
def lockFilePath : System.FilePath := "qed.lock"

-- ═══════════════════════════════════════════════════════════════════
-- Glob expansion
-- ═══════════════════════════════════════════════════════════════════

/-- Whether a glob pattern contains only safe characters for shell expansion.
    Allows: alphanumeric, *, ?, /, ., _, -, [, ]
    Rejects: $, `, ;, &, |, (, ), {, }, <, >, space, etc. -/
def isValidGlobPattern (pattern : String) : Bool :=
  !pattern.isEmpty && pattern.all fun c =>
    c.isAlpha || c.isDigit || c == '*' || c == '?' || c == '/' ||
    c == '.' || c == '_' || c == '-' || c == '[' || c == ']'

/-- Expand a glob pattern to a list of file paths.
    Uses bash globstar for `**` support. Returns empty list for no matches. -/
def expandGlob (pattern : String) : IO (Except ErrorInfo (List String)) := do
  if !isValidGlobPattern pattern then
    return .error { message := s!"invalid glob pattern: '{pattern}' (contains unsafe characters)" }
  -- Use bash with globstar and nullglob for reliable ** expansion.
  -- Pattern is validated above to contain only glob-safe characters.
  -- Note: the pattern sits inside single quotes in the bash -c argument,
  -- which is itself inside Shell.runShellCommand's /bin/sh -c wrapper.
  -- isValidGlobPattern rejects quotes and all shell metacharacters,
  -- so the double-shell nesting is safe.
  let command := s!"bash -c 'shopt -s globstar nullglob; for f in {pattern}; do [ -f \"$f\" ] && printf \"%s\\n\" \"$f\"; done'"
  let (exitCode, stdout, _) ← Shell.runShellCommand command
  if exitCode == 0 then
    let files := stdout.splitOn "\n" |>.filter (!·.isEmpty) |>.map fun path =>
      -- Normalize: strip leading ./ if present
      if path.startsWith "./" then (path.drop 2).toString else path
    return .ok files
  else
    return .ok []

/-- Expand multiple glob patterns, deduplicating results. -/
def expandGlobs (patterns : List String) : IO (Except ErrorInfo (List String)) := do
  let mut allFiles : List String := []
  for pattern in patterns do
    match ← expandGlob pattern with
    | .error errorInfo => return .error errorInfo
    | .ok files =>
      for file in files do
        if !allFiles.contains file then
          allFiles := allFiles ++ [file]
  return .ok allFiles

-- ═══════════════════════════════════════════════════════════════════
-- Theorem statement extraction
-- ═══════════════════════════════════════════════════════════════════

/-- Extract the short name from a fully qualified theorem name.
    E.g., `Qed.Proofs.Foo.bar` → `bar`. -/
def shortTheoremName (qualifiedName : String) : String :=
  match qualifiedName.splitOn "." |>.getLast? with
  | some name => name
  | none => qualifiedName

/-- Find `:=` at bracket depth 0 in a line. Returns the text before the `:=`,
    or `none` if no top-level `:=` exists. Tracks `()`, `{}`, and `[]` nesting
    so that `:=` inside parameter defaults (e.g., `(h : x := 0)`) is ignored. -/
private def findTopLevelAssignment (line : String) : Option String :=
  let rec go (chars : List Char) (depth : Nat) (before : String) : Option String :=
    match chars with
    | [] => none
    | c :: rest =>
      if c == '(' || c == '{' || c == '[' then
        go rest (depth + 1) (before.push c)
      else if c == ')' || c == '}' || c == ']' then
        go rest (if depth > 0 then depth - 1 else 0) (before.push c)
      else if c == ':' then
        match rest with
        | '=' :: _ =>
          if depth == 0 then some before
          else go rest depth (before.push c)
        | _ => go rest depth (before.push c)
      else
        go rest depth (before.push c)
  go line.toList 0 ""

/-- Extract a theorem statement from Lean source text.
    Finds the declaration of `theoremName` (short or qualified) and extracts
    the text from `theorem` to `:=` (exclusive). This captures the full
    signature including parameters and return type.

    Returns `none` if the theorem is not found. -/
def extractTheoremStatement (source : String) (qualifiedName : String) : Option String :=
  let shortName := shortTheoremName qualifiedName
  let lines := source.splitOn "\n"
  -- Find the line containing the theorem declaration
  let startIdx := lines.findIdx? fun line =>
    let trimmed := line.trimAsciiStart.toString
    -- Match both short and fully qualified forms, with various visibility modifiers
    trimmed.startsWith s!"theorem {shortName}" ||
    trimmed.startsWith s!"private theorem {shortName}" ||
    trimmed.startsWith s!"protected theorem {shortName}" ||
    trimmed.startsWith s!"theorem {qualifiedName}" ||
    trimmed.startsWith s!"private theorem {qualifiedName}" ||
    trimmed.startsWith s!"protected theorem {qualifiedName}"
  match startIdx with
  | none => none
  | some start =>
    -- Collect lines from start until `:=` or `where` (both mark end of statement).
    -- `:=` is only matched at bracket depth 0 to handle parameter defaults
    -- like `(h : x := 0)` correctly.
    let remaining := lines.drop start
    let rec collectLines (lns : List String) (accumulated : String) : Option String :=
      match lns with
      | [] => none
      | line :: rest =>
        -- Check for `where` clause (also terminates the statement)
        let trimmed := line.trimAsciiStart.toString
        if trimmed == "where" || trimmed.startsWith "where " then
          some accumulated.trimAsciiEnd.toString
        else
          match findTopLevelAssignment line with
          | some beforeEq =>
            some (accumulated ++ beforeEq.trimAsciiEnd.toString).trimAsciiEnd.toString
          | none =>
            collectLines rest (accumulated ++ line ++ "\n")
    collectLines remaining ""

/-- Extract a theorem statement from a source file and compute its hash. -/
def hashTheoremStatement (target : String) : IO (Except ErrorInfo LockedArtifact) := do
  match Verifier.targetToModule target with
  | none => return .error { message := s!"invalid target: '{target}' (expected fully qualified name)" }
  | some module =>
    let sourcePath := Verifier.moduleToPath module
    if !(← System.FilePath.pathExists sourcePath) then
      return .error { message := s!"source file not found: {sourcePath}" }
    let source ← IO.FS.readFile sourcePath
    match extractTheoremStatement source target with
    | none => return .error { message := s!"theorem '{target}' not found in {sourcePath}" }
    | some statement =>
      let hash ← Integrity.hashContents statement
      -- Use a synthetic path that identifies this as a theorem statement
      return .ok { path := s!"theorem:{target}", hash }

-- ═══════════════════════════════════════════════════════════════════
-- Lock generation
-- ═══════════════════════════════════════════════════════════════════

/-- Generate lock entries for a single criterion. -/
def lockCriterion (criterion : AcceptanceCriterion) : IO (Except ErrorInfo CriterionLock) := do
  match criterion.verify with
  | .command _ _ lock | .property _ _ lock =>
    match lock with
    | none => return .ok { description := criterion.description, artifacts := [] }
    | some patterns =>
      match ← expandGlobs patterns with
      | .error errorInfo => return .error errorInfo
      | .ok files =>
        if files.isEmpty then
          return .error { message := s!"lock patterns matched no files for criterion '{criterion.description}'", hint := some "check patterns or use --no-lock to skip" }
        let mut artifacts : List LockedArtifact := []
        for file in files do
          let hash ← Integrity.hashFile file
          artifacts := artifacts ++ [{ path := file, hash }]
        return .ok { description := criterion.description, artifacts }
  | .proof _ target =>
    match ← hashTheoremStatement target with
    | .error errorInfo => return .error errorInfo
    | .ok artifact =>
      return .ok { description := criterion.description, artifacts := [artifact] }
  | .agent _ _ _ _ | .human _ =>
    -- Agent and human criteria have no lockable artifacts
    return .ok { description := criterion.description, artifacts := [] }

/-- Generate lock entries for a spec. Returns only criteria that have artifacts. -/
def lockSpec (specPath : String) (spec : Spec) : IO (Except ErrorInfo SpecLock) := do
  let mut criteriaLocks : List CriterionLock := []
  for criterion in spec.criteria do
    match ← lockCriterion criterion with
    | .error errorInfo => return .error { errorInfo with message := s!"spec '{specPath}': {errorInfo.message}" }
    | .ok lock =>
      if !lock.artifacts.isEmpty then
        criteriaLocks := criteriaLocks ++ [lock]
  return .ok { specPath, criteria := criteriaLocks }

/-- Generate a complete lock file from a list of (path, spec) pairs. -/
def generateLockFile (specs : List (String × Spec)) : IO (Except ErrorInfo LockFile) := do
  let mut specLocks : List SpecLock := []
  for (path, spec) in specs do
    match ← lockSpec path spec with
    | .error errorInfo => return .error errorInfo
    | .ok lock =>
      if !lock.criteria.isEmpty then
        specLocks := specLocks ++ [lock]
  return .ok { version := 1, specs := specLocks }

-- ═══════════════════════════════════════════════════════════════════
-- Lock verification
-- ═══════════════════════════════════════════════════════════════════

/-- Verify a single locked artifact. Returns an error message if the hash changed. -/
def verifyArtifact (artifact : LockedArtifact) : IO (Option String) := do
  if artifact.path.startsWith "theorem:" then
    -- Theorem statement: re-extract and re-hash
    let target := (artifact.path.drop "theorem:".length).toString
    match ← hashTheoremStatement target with
    | .error errorInfo => return some s!"cannot verify theorem lock: {errorInfo.message}"
    | .ok current =>
      if current.hash != artifact.hash then
        return some s!"theorem statement changed: {target}"
      else
        return none
  else
    -- File: re-hash
    if !(← System.FilePath.pathExists artifact.path) then
      return some s!"locked file deleted: {artifact.path}"
    let currentHash ← Integrity.hashFile artifact.path
    if currentHash != artifact.hash then
      return some s!"locked file modified: {artifact.path}"
    else
      return none

/-- Verify all locks for a specific spec. Returns a list of violations. -/
def verifySpecLocks (specLock : SpecLock) : IO (List String) := do
  let mut violations : List String := []
  for criterionLock in specLock.criteria do
    for artifact in criterionLock.artifacts do
      match ← verifyArtifact artifact with
      | some violation =>
        violations := violations ++ [s!"{criterionLock.description}: {violation}"]
      | none => pure ()
  return violations

/-- Verify all locks in a lock file. Returns a list of all violations. -/
def verifyAllLocks (lockFile : LockFile) : IO (List String) := do
  let mut allViolations : List String := []
  for specLock in lockFile.specs do
    let violations ← verifySpecLocks specLock
    allViolations := allViolations ++ violations
  return allViolations

/-- Verify locks for a specific spec path. Returns violations or empty list. -/
def verifyLocksForSpec (lockFile : LockFile) (specPath : String) : IO (List String) := do
  match lockFile.specs.find? (·.specPath == specPath) with
  | none => return []  -- No locks for this spec
  | some specLock => verifySpecLocks specLock

-- ═══════════════════════════════════════════════════════════════════
-- Lock file serialization (JSON)
-- ═══════════════════════════════════════════════════════════════════

/-- Serialize a LockedArtifact to JSON. -/
def artifactToJson (artifact : LockedArtifact) : Json :=
  Json.mkObj [("path", Json.str artifact.path), ("hash", Json.str artifact.hash)]

/-- Serialize a CriterionLock to JSON. -/
def criterionLockToJson (lock : CriterionLock) : Json :=
  Json.mkObj [
    ("description", Json.str lock.description),
    ("artifacts", Json.arr (lock.artifacts.map artifactToJson).toArray)]

/-- Serialize a SpecLock to JSON. -/
def specLockToJson (lock : SpecLock) : Json :=
  Json.mkObj [
    ("specPath", Json.str lock.specPath),
    ("criteria", Json.arr (lock.criteria.map criterionLockToJson).toArray)]

/-- Serialize a LockFile to JSON. -/
def lockFileToJson (lockFile : LockFile) : Json :=
  Json.mkObj [
    ("version", Json.num lockFile.version),
    ("specs", Json.arr (lockFile.specs.map specLockToJson).toArray)]

/-- Serialize a LockFile to a JSON string. -/
def serializeLockFile (lockFile : LockFile) : String :=
  (lockFileToJson lockFile).pretty 2

-- ═══════════════════════════════════════════════════════════════════
-- Lock file parsing (JSON)
-- ═══════════════════════════════════════════════════════════════════

/-- Parse a LockedArtifact from JSON. -/
def parseArtifact (json : Json) : Except ErrorInfo LockedArtifact := do
  let path ← match json.getObjValAs? String "path" with
    | .ok value => .ok value
    | .error _ => .error { message := "artifact missing 'path'" }
  let hash ← match json.getObjValAs? String "hash" with
    | .ok value => .ok value
    | .error _ => .error { message := "artifact missing 'hash'" }
  .ok { path, hash }

/-- Parse a CriterionLock from JSON. -/
def parseCriterionLock (json : Json) : Except ErrorInfo CriterionLock := do
  let description ← match json.getObjValAs? String "description" with
    | .ok value => .ok value
    | .error _ => .error { message := "criterion lock missing 'description'" }
  let artifactsArr ← match json.getObjVal? "artifacts" with
    | .ok (Json.arr items) => .ok items
    | _ => .error { message := "criterion lock missing 'artifacts' array" }
  let artifacts ← artifactsArr.toList.mapM parseArtifact
  .ok { description, artifacts }

/-- Parse a SpecLock from JSON. -/
def parseSpecLock (json : Json) : Except ErrorInfo SpecLock := do
  let specPath ← match json.getObjValAs? String "specPath" with
    | .ok value => .ok value
    | .error _ => .error { message := "spec lock missing 'specPath'" }
  let criteriaArr ← match json.getObjVal? "criteria" with
    | .ok (Json.arr items) => .ok items
    | _ => .error { message := "spec lock missing 'criteria' array" }
  let criteria ← criteriaArr.toList.mapM parseCriterionLock
  .ok { specPath, criteria }

/-- Parse a LockFile from a JSON string. -/
def parseLockFile (input : String) : Except ErrorInfo LockFile := do
  let json ← (Json.parse input).mapError fun error => ({ message := error } : ErrorInfo)
  let version ← match json.getObjValAs? Nat "version" with
    | .ok value => .ok value
    | .error _ => .error { message := "lock file missing 'version'" }
  if version != 1 then
    .error { message := s!"unsupported lock file version: {version} (expected 1)" }
  let specsArr ← match json.getObjVal? "specs" with
    | .ok (Json.arr items) => .ok items
    | _ => .error { message := "lock file missing 'specs' array" }
  let specs ← specsArr.toList.mapM parseSpecLock
  .ok { version, specs }

-- ═══════════════════════════════════════════════════════════════════
-- Lock file I/O
-- ═══════════════════════════════════════════════════════════════════

/-- Read and parse the lock file. Returns `none` if the file doesn't exist. -/
def readLockFile : IO (Option LockFile) := do
  if !(← lockFilePath.pathExists) then
    return none
  let contents ← IO.FS.readFile lockFilePath
  match parseLockFile contents with
  | .ok lockFile => return some lockFile
  | .error errorInfo => throw (IO.userError s!"failed to parse {lockFilePath}: {errorInfo.message}")

/-- Write the lock file to disk. -/
def writeLockFile (lockFile : LockFile) : IO Unit := do
  IO.FS.writeFile lockFilePath (serializeLockFile lockFile ++ "\n")

end Qed.ContractLock

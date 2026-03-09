import Qed.TomlParser

open Qed.TomlParser

/-- Helper: parse TOML and return JSON string or panic. -/
private def parseOrFail (toml : String) : IO String := do
  match tomlToJson toml with
  | .ok json => return json
  | .error e => throw (IO.userError s!"unexpected parse error: {e}")

/-- Helper: parse TOML and expect failure. -/
private def expectParseError (toml : String) : IO Bool := do
  match tomlToJson toml with
  | .ok _ => return false
  | .error _ => return true

def testParseBareKeyValuePair : IO Bool := do
  -- Arrange
  let toml := "name = \"hello\"\n"
  -- Act
  let json ← parseOrFail toml
  -- Assert
  return json.contains "\"name\": \"hello\""

def testParseIntegerValue : IO Bool := do
  -- Arrange
  let toml := "count = 42\n"
  -- Act
  let json ← parseOrFail toml
  -- Assert
  return json.contains "\"count\": 42"

def testParseNegativeInteger : IO Bool := do
  -- Arrange
  let toml := "offset = -7\n"
  -- Act
  let json ← parseOrFail toml
  -- Assert
  return json.contains "\"offset\": -7"

def testParseBooleanValues : IO Bool := do
  -- Arrange
  let toml := "enabled = true\ndisabled = false\n"
  -- Act
  let json ← parseOrFail toml
  -- Assert
  return json.contains "\"enabled\": true" && json.contains "\"disabled\": false"

def testParseQuotedKey : IO Bool := do
  -- Arrange
  let toml := "\"quoted key\" = \"value\"\n"
  -- Act
  let json ← parseOrFail toml
  -- Assert
  return json.contains "\"quoted key\": \"value\""

def testParseDottedKey : IO Bool := do
  -- Arrange
  let toml := "server.host = \"localhost\"\n"
  -- Act
  let json ← parseOrFail toml
  -- Assert
  return json.contains "\"server\"" && json.contains "\"host\": \"localhost\""

def testParseTableHeader : IO Bool := do
  -- Arrange
  let toml := "[server]\nhost = \"localhost\"\nport = 8080\n"
  -- Act
  let json ← parseOrFail toml
  -- Assert
  return json.contains "\"server\"" && json.contains "\"host\": \"localhost\"" &&
    json.contains "\"port\": 8080"

def testParseArrayOfTables : IO Bool := do
  -- Arrange
  let toml := "[[items]]\nname = \"a\"\n\n[[items]]\nname = \"b\"\n"
  -- Act
  let json ← parseOrFail toml
  -- Assert
  return json.contains "\"items\"" && json.contains "\"name\": \"a\"" &&
    json.contains "\"name\": \"b\""

def testParseArrayOfTablesWithSubTable : IO Bool := do
  -- Arrange — this is the key pattern used in qed specs
  let toml := "[[criteria]]\ndescription = \"test\"\n\n[criteria.verify]\ntype = \"command\"\nrun = \"make\"\n"
  -- Act
  let json ← parseOrFail toml
  -- Assert
  return json.contains "\"description\": \"test\"" &&
    json.contains "\"type\": \"command\"" &&
    json.contains "\"run\": \"make\""

def testParseMultiLineString : IO Bool := do
  -- Arrange
  let toml := "text = \"\"\"\nline one\nline two\n\"\"\"\n"
  -- Act
  let json ← parseOrFail toml
  -- Assert
  return json.contains "line one" && json.contains "line two"

def testParseMultiLineStringSkipsFirstNewline : IO Bool := do
  -- Arrange — TOML spec: first newline after opening """ is trimmed
  let toml := "text = \"\"\"\nhello\"\"\"\n"
  -- Act
  let json ← parseOrFail toml
  -- Assert
  return json.contains "\"text\": \"hello\""

def testParseEscapeSequences : IO Bool := do
  -- Arrange
  let toml := "text = \"hello\\nworld\\t!\"\n"
  -- Act
  let json ← parseOrFail toml
  -- Assert
  return json.contains "hello" && json.contains "world"

def testParseComments : IO Bool := do
  -- Arrange
  let toml := "# this is a comment\nname = \"test\" # inline comment\n"
  -- Act
  let json ← parseOrFail toml
  -- Assert
  return json.contains "\"name\": \"test\""

def testParseMultipleArrayEntries : IO Bool := do
  -- Arrange — multiple [[criteria]] with [criteria.verify] sub-tables
  let toml := "[[criteria]]\ndescription = \"first\"\n\n[criteria.verify]\ntype = \"command\"\nrun = \"echo a\"\n\n[[criteria]]\ndescription = \"second\"\n\n[criteria.verify]\ntype = \"proof\"\nprover = \"lean4\"\ntarget = \"Foo.bar\"\n"
  -- Act
  let json ← parseOrFail toml
  -- Assert
  return json.contains "\"first\"" && json.contains "\"second\"" &&
    json.contains "\"command\"" && json.contains "\"proof\""

def testParseNonAsciiInMultiLineString : IO Bool := do
  -- Arrange — em dash is 3 bytes, tests byte vs char indexing
  let toml := "text = \"\"\"\npure \u2014 no side effects\n\"\"\"\n"
  -- Act
  let json ← parseOrFail toml
  -- Assert
  return json.contains "pure" && json.contains "no side effects"

def testParseErrorOnUnterminatedString : IO Bool := do
  -- Arrange
  let toml := "name = \"unterminated\n"
  -- Act / Assert
  expectParseError toml

def testParseErrorOnInvalidTableHeader : IO Bool := do
  -- Arrange
  let toml := "[[[bad]]]\n"
  -- Act / Assert
  expectParseError toml

def testParseIntegerWithUnderscores : IO Bool := do
  -- Arrange — TOML allows underscores in integers for readability
  let toml := "big = 1_000_000\n"
  -- Act
  let json ← parseOrFail toml
  -- Assert
  return json.contains "\"big\": 1000000"

def testParseEmptyDocument : IO Bool := do
  -- Arrange
  let toml := ""
  -- Act
  let json ← parseOrFail toml
  -- Assert
  return json.contains "{" && json.contains "}"

def tomlParserTests : List (String × IO Bool) := [
  ("testParseBareKeyValuePair", testParseBareKeyValuePair),
  ("testParseIntegerValue", testParseIntegerValue),
  ("testParseNegativeInteger", testParseNegativeInteger),
  ("testParseBooleanValues", testParseBooleanValues),
  ("testParseQuotedKey", testParseQuotedKey),
  ("testParseDottedKey", testParseDottedKey),
  ("testParseTableHeader", testParseTableHeader),
  ("testParseArrayOfTables", testParseArrayOfTables),
  ("testParseArrayOfTablesWithSubTable", testParseArrayOfTablesWithSubTable),
  ("testParseMultiLineString", testParseMultiLineString),
  ("testParseMultiLineStringSkipsFirstNewline", testParseMultiLineStringSkipsFirstNewline),
  ("testParseEscapeSequences", testParseEscapeSequences),
  ("testParseComments", testParseComments),
  ("testParseMultipleArrayEntries", testParseMultipleArrayEntries),
  ("testParseNonAsciiInMultiLineString", testParseNonAsciiInMultiLineString),
  ("testParseErrorOnUnterminatedString", testParseErrorOnUnterminatedString),
  ("testParseErrorOnInvalidTableHeader", testParseErrorOnInvalidTableHeader),
  ("testParseIntegerWithUnderscores", testParseIntegerWithUnderscores),
  ("testParseEmptyDocument", testParseEmptyDocument)
]

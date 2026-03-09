import Lean.Data.Json

set_option autoImplicit false

namespace Qed.TomlParser

open Lean

/-- Skip spaces and tabs from position, return new position. -/
partial def skipWs (s : String) (i : Nat) : Nat :=
  if i < s.utf8ByteSize then
    let c := String.Pos.Raw.get s ⟨i⟩
    if c == ' ' || c == '\t' then skipWs s (i + 1) else i
  else i

/-- Skip whitespace including newlines. -/
partial def skipWsNl (s : String) (i : Nat) : Nat :=
  if i < s.utf8ByteSize then
    let c := String.Pos.Raw.get s ⟨i⟩
    if c == ' ' || c == '\t' || c == '\n' || c == '\r' then skipWsNl s (i + 1) else i
  else i

/-- Skip from # to end of line. -/
partial def skipComment (s : String) (i : Nat) : Nat :=
  if i < s.utf8ByteSize && String.Pos.Raw.get s ⟨i⟩ == '#' then
    let rec go (j : Nat) : Nat :=
      if j < s.utf8ByteSize then
        if String.Pos.Raw.get s ⟨j⟩ == '\n' then j + 1 else go (j + 1)
      else j
    go i
  else i

/-- Skip all blank space: whitespace, newlines, and comments. -/
partial def skipBlank (s : String) (i : Nat) : Nat :=
  let j := skipComment s (skipWsNl s i)
  if j == i then i else skipBlank s j

/-- Parse a bare key (alphanumeric, dash, underscore). -/
partial def parseBareKey (s : String) (i : Nat) : Except String (String × Nat) :=
  let rec go (j : Nat) (acc : String) : Except String (String × Nat) :=
    if j < s.utf8ByteSize then
      let c := String.Pos.Raw.get s ⟨j⟩
      if c.isAlphanum || c == '-' || c == '_' then go (j + 1) (acc.push c)
      else if acc.isEmpty then .error s!"expected key at byte {j}"
      else .ok (acc, j)
    else if acc.isEmpty then .error "unexpected end of input, expected key"
    else .ok (acc, j)
  go i ""

/-- Parse a basic (double-quoted) string with escapes and multi-line support. -/
partial def parseString (s : String) (i : Nat) : Except String (String × Nat) :=
  if i >= s.utf8ByteSize || String.Pos.Raw.get s ⟨i⟩ != '"' then .error "expected '\"'"
  else
    -- Check for multi-line """
    let isMulti := i + 2 < s.utf8ByteSize && String.Pos.Raw.get s ⟨i + 1⟩ == '"' && String.Pos.Raw.get s ⟨i + 2⟩ == '"'
    if isMulti then
      -- Skip opening """ and optional first newline
      let start := i + 3
      let start := if start < s.utf8ByteSize && String.Pos.Raw.get s ⟨start⟩ == '\n' then start + 1
        else if start < s.utf8ByteSize && String.Pos.Raw.get s ⟨start⟩ == '\r' then
          if start + 1 < s.utf8ByteSize && String.Pos.Raw.get s ⟨start + 1⟩ == '\n' then start + 2 else start + 1
        else start
      let rec go (j : Nat) (acc : String) : Except String (String × Nat) :=
        if j >= s.utf8ByteSize then .error "unterminated multi-line string"
        else
          let c := String.Pos.Raw.get s ⟨j⟩
          if c == '"' && j + 2 < s.utf8ByteSize && String.Pos.Raw.get s ⟨j + 1⟩ == '"' && String.Pos.Raw.get s ⟨j + 2⟩ == '"' then
            .ok (acc, j + 3)
          else if c == '\\' && j + 1 < s.utf8ByteSize then
            let ec := String.Pos.Raw.get s ⟨j + 1⟩
            match ec with
            | 'n' => go (j + 2) (acc.push '\n')
            | 't' => go (j + 2) (acc.push '\t')
            | 'r' => go (j + 2) (acc.push '\r')
            | '"' => go (j + 2) (acc.push '"')
            | '\\' => go (j + 2) (acc.push '\\')
            | '\n' =>
              -- Line-ending backslash: skip whitespace
              let rec skipLws (k : Nat) : Nat :=
                if k < s.utf8ByteSize then
                  let ch := String.Pos.Raw.get s ⟨k⟩
                  if ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r' then skipLws (k + 1) else k
                else k
              go (skipLws (j + 2)) acc
            | _ => go (j + 2) (acc.push '\\' |>.push ec)
          else go (j + 1) (acc.push c)
      go start ""
    else
      -- Single-line string
      let rec goSingle (j : Nat) (acc : String) : Except String (String × Nat) :=
        if j >= s.utf8ByteSize then .error "unterminated string"
        else
          let c := String.Pos.Raw.get s ⟨j⟩
          if c == '"' then .ok (acc, j + 1)
          else if c == '\n' then .error "newline in single-line string"
          else if c == '\\' && j + 1 < s.utf8ByteSize then
            let ec := String.Pos.Raw.get s ⟨j + 1⟩
            match ec with
            | 'n' => goSingle (j + 2) (acc.push '\n')
            | 't' => goSingle (j + 2) (acc.push '\t')
            | 'r' => goSingle (j + 2) (acc.push '\r')
            | '"' => goSingle (j + 2) (acc.push '"')
            | '\\' => goSingle (j + 2) (acc.push '\\')
            | _ => goSingle (j + 2) (acc.push '\\' |>.push ec)
          else goSingle (j + 1) (acc.push c)
      goSingle (i + 1) ""

/-- Parse a key (bare or quoted). -/
def parseKey (s : String) (i : Nat) : Except String (String × Nat) :=
  if i < s.utf8ByteSize && String.Pos.Raw.get s ⟨i⟩ == '"' then parseString s i
  else parseBareKey s i

/-- Parse a dotted key like `criteria.verify`. -/
partial def parseDottedKey (s : String) (i : Nat) : Except String (List String × Nat) :=
  match parseKey s i with
  | .error e => .error e
  | .ok (first, j) =>
    let rec go (j : Nat) (acc : List String) : Except String (List String × Nat) :=
      let j := skipWs s j
      if j < s.utf8ByteSize && String.Pos.Raw.get s ⟨j⟩ == '.' then
        let j := skipWs s (j + 1)
        match parseKey s j with
        | .error e => .error e
        | .ok (key, j) => go j (acc ++ [key])
      else .ok (acc, j)
    go j [first]

/-- Parse an integer (optional sign, underscores allowed). -/
partial def parseInteger (s : String) (i : Nat) : Except String (Int × Nat) :=
  let (neg, i) := if i < s.utf8ByteSize then
    match String.Pos.Raw.get s ⟨i⟩ with
    | '+' => (false, i + 1)
    | '-' => (true, i + 1)
    | _ => (false, i)
  else (false, i)
  let rec go (j : Nat) (acc : String) : Except String (Int × Nat) :=
    if j < s.utf8ByteSize then
      let c := String.Pos.Raw.get s ⟨j⟩
      if c.isDigit then go (j + 1) (acc.push c)
      else if c == '_' then go (j + 1) acc
      else match acc.toInt? with
        | some n => .ok (if neg then -n else n, j)
        | none => .error "invalid integer"
    else match acc.toInt? with
      | some n => .ok (if neg then -n else n, j)
      | none => .error "invalid integer"
  go i ""

/-- A TOML value. -/
inductive TomlValue where
  | str (val : String)
  | int (val : Int)
  | bool (val : Bool)
  | table (pairs : List (String × TomlValue))
  | array (items : List TomlValue)

/-- Parse a value (string, integer, boolean). -/
def parseValue (s : String) (i : Nat) : Except String (TomlValue × Nat) :=
  if i >= s.utf8ByteSize then .error "unexpected end of input"
  else
    let c := String.Pos.Raw.get s ⟨i⟩
    if c == '"' then
      match parseString s i with
      | .ok (v, j) => .ok (.str v, j)
      | .error e => .error e
    else if c == 't' && i + 3 < s.utf8ByteSize &&
        String.Pos.Raw.get s ⟨i + 1⟩ == 'r' && String.Pos.Raw.get s ⟨i + 2⟩ == 'u' && String.Pos.Raw.get s ⟨i + 3⟩ == 'e' then
      .ok (.bool true, i + 4)
    else if c == 'f' && i + 4 < s.utf8ByteSize &&
        String.Pos.Raw.get s ⟨i + 1⟩ == 'a' && String.Pos.Raw.get s ⟨i + 2⟩ == 'l' && String.Pos.Raw.get s ⟨i + 3⟩ == 's' && String.Pos.Raw.get s ⟨i + 4⟩ == 'e' then
      .ok (.bool false, i + 5)
    else if c.isDigit || c == '+' || c == '-' then
      match parseInteger s i with
      | .ok (n, j) => .ok (.int n, j)
      | .error e => .error e
    else .error s!"unexpected character '{c}' at byte {i}"

/-- Skip to end of line (past optional inline comment). -/
def skipToEol (s : String) (i : Nat) : Except String Nat :=
  let i := skipComment s (skipWs s i)
  if i >= s.utf8ByteSize then .ok i
  else
    let c := String.Pos.Raw.get s ⟨i⟩
    if c == '\n' then .ok (i + 1)
    else if c == '\r' then
      if i + 1 < s.utf8ByteSize && String.Pos.Raw.get s ⟨i + 1⟩ == '\n' then .ok (i + 2) else .ok (i + 1)
    else .error s!"expected end of line at byte {i}, got '{c}'"

/-- Set a value at a dotted key path, creating intermediate tables. -/
def setNested (pairs : List (String × TomlValue)) (keys : List String) (value : TomlValue)
    : Except String (List (String × TomlValue)) :=
  match keys with
  | [] => .error "empty key path"
  | [key] => .ok (pairs ++ [(key, value)])
  | key :: rest =>
    match pairs.find? (fun (k, _) => k == key) with
    | some (_, .table inner) =>
      match setNested inner rest value with
      | .ok newInner => .ok (pairs.map fun (k, v) =>
          if k == key then (k, .table newInner) else (k, v))
      | .error e => .error e
    | some _ => .error s!"key '{key}' already exists and is not a table"
    | none =>
      match setNested [] rest value with
      | .ok newInner => .ok (pairs ++ [(key, .table newInner)])
      | .error e => .error e

/-- Append a new empty table to an array-of-tables at the given path. -/
def appendArray (pairs : List (String × TomlValue)) (keys : List String)
    : Except String (List (String × TomlValue)) :=
  match keys with
  | [] => .error "empty key path"
  | [key] =>
    match pairs.find? (fun (k, _) => k == key) with
    | some (_, .array items) =>
      .ok (pairs.map fun (k, v) =>
        if k == key then (k, .array (items ++ [.table []])) else (k, v))
    | some _ => .error s!"key '{key}' is not an array"
    | none => .ok (pairs ++ [(key, .array [.table []])])
  | key :: rest =>
    match pairs.find? (fun (k, _) => k == key) with
    | some (_, .table inner) =>
      match appendArray inner rest with
      | .ok newInner => .ok (pairs.map fun (k, v) =>
          if k == key then (k, .table newInner) else (k, v))
      | .error e => .error e
    | some _ => .error s!"key '{key}' is not a table"
    | none =>
      match appendArray [] rest with
      | .ok newInner => .ok (pairs ++ [(key, .table newInner)])
      | .error e => .error e

/-- Set a value in the last table of an array-of-tables. -/
def setInLastArray (pairs : List (String × TomlValue)) (arrayKeys : List String)
    (valueKeys : List String) (value : TomlValue)
    : Except String (List (String × TomlValue)) :=
  match arrayKeys with
  | [] => .error "empty array key path"
  | [key] =>
    match pairs.find? (fun (k, _) => k == key) with
    | some (_, .array items) =>
      match items.reverse with
      | [] => .error "array is empty"
      | .table lastPairs :: rest =>
        match setNested lastPairs valueKeys value with
        | .ok newPairs =>
          let newItems := rest.reverse ++ [.table newPairs]
          .ok (pairs.map fun (k, v) =>
            if k == key then (k, .array newItems) else (k, v))
        | .error e => .error e
      | _ :: _ => .error "last array item is not a table"
    | _ => .error s!"'{key}' is not an array of tables"
  | key :: rest =>
    match pairs.find? (fun (k, _) => k == key) with
    | some (_, .table inner) =>
      match setInLastArray inner rest valueKeys value with
      | .ok newInner => .ok (pairs.map fun (k, v) =>
          if k == key then (k, .table newInner) else (k, v))
      | .error e => .error e
    | _ => .error s!"'{key}' is not a table"

/-- Table context for key-value routing.
    - `root`: top-level
    - `tbl keys`: standalone table [keys]
    - `arr arrKeys subKeys`: inside [[arrKeys]], optionally in sub-table [arrKeys.subKeys] -/
inductive Ctx where
  | root
  | tbl (keys : List String)
  | arr (arrKeys : List String) (subKeys : List String)

/-- Parse a full TOML document. -/
partial def parseDoc (s : String) : Except String (List (String × TomlValue)) :=
  let rec go (i : Nat) (pairs : List (String × TomlValue)) (context : Ctx)
      : Except String (List (String × TomlValue)) :=
    let i := skipBlank s i
    if i >= s.utf8ByteSize then .ok pairs
    else if String.Pos.Raw.get s ⟨i⟩ == '[' then
      if i + 1 < s.utf8ByteSize && String.Pos.Raw.get s ⟨i + 1⟩ == '[' then
        -- [[array.of.tables]]
        let j := skipWs s (i + 2)
        match parseDottedKey s j with
        | .error e => .error e
        | .ok (keys, j) =>
          let j := skipWs s j
          if j + 1 < s.utf8ByteSize && String.Pos.Raw.get s ⟨j⟩ == ']' && String.Pos.Raw.get s ⟨j + 1⟩ == ']' then
            match skipToEol s (j + 2) with
            | .error e => .error e
            | .ok j =>
              match appendArray pairs keys with
              | .error e => .error e
              | .ok p => go j p (.arr keys [])
          else .error s!"expected ']]' at byte {j}"
      else
        -- [table.header]
        let j := skipWs s (i + 1)
        match parseDottedKey s j with
        | .error e => .error e
        | .ok (keys, j) =>
          let j := skipWs s j
          if j < s.utf8ByteSize && String.Pos.Raw.get s ⟨j⟩ == ']' then
            match skipToEol s (j + 1) with
            | .error e => .error e
            | .ok j =>
              -- Check if this table is a sub-table of the current array context.
              -- e.g., [criteria.verify] after [[criteria]] means we're setting
              -- into the last entry of the criteria array.
              match context with
              | .arr arrKeys _ =>
                if keys.length > arrKeys.length &&
                   keys.take arrKeys.length == arrKeys then
                  -- Sub-table of current array entry
                  let subKeys := keys.drop arrKeys.length
                  go j pairs (.arr arrKeys subKeys)
                else
                  match setNested pairs keys (.table []) with
                  | .error _ => go j pairs (.tbl keys)
                  | .ok p => go j p (.tbl keys)
              | _ =>
                match setNested pairs keys (.table []) with
                | .error _ => go j pairs (.tbl keys)
                | .ok p => go j p (.tbl keys)
          else .error s!"expected ']' at byte {j}"
    else
      -- key = value
      match parseDottedKey s i with
      | .error e => .error e
      | .ok (keys, j) =>
        let j := skipWs s j
        if j < s.utf8ByteSize && String.Pos.Raw.get s ⟨j⟩ == '=' then
          let j := skipWs s (j + 1)
          match parseValue s j with
          | .error e => .error e
          | .ok (value, j) =>
            match skipToEol s j with
            | .error e => .error e
            | .ok j =>
              let result := match context with
                | .root => setNested pairs keys value
                | .tbl tableKeys => setNested pairs (tableKeys ++ keys) value
                | .arr arrayKeys subKeys => setInLastArray pairs arrayKeys (subKeys ++ keys) value
              match result with
              | .error e => .error e
              | .ok p => go j p context
        else .error s!"expected '=' at byte {j}"
  go 0 [] .root

/-- Convert a TomlValue to Lean.Json. -/
partial def toJson : TomlValue → Json
  | .str v => Json.str v
  | .int v => Json.num v
  | .bool v => Json.bool v
  | .table pairs => Json.mkObj (pairs.map fun (k, v) => (k, toJson v))
  | .array items => Json.arr (items.map toJson).toArray

/-- Parse TOML and return JSON string. Pure Lean — no external dependencies. -/
def tomlToJson (tomlContent : String) : Except String String :=
  match parseDoc tomlContent with
  | .ok pairs => .ok (toJson (.table pairs) |>.pretty)
  | .error e => .error s!"TOML parse error: {e}"

end Qed.TomlParser

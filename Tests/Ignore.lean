import Qed

open Qed.Ignore

-- fnmatch: exact match

def testFnmatchExactMatch : IO Bool := do
  -- Arrange / Act / Assert
  return fnmatch "archive" "archive" && !fnmatch "archive" "wip"

-- fnmatch: * wildcard

def testFnmatchStarSuffix : IO Bool := do
  -- Arrange / Act / Assert
  return fnmatch "*.bak" "file.bak" && fnmatch "*.bak" ".bak" &&
    !fnmatch "*.bak" "file.txt"

def testFnmatchStarPrefix : IO Bool := do
  -- Arrange / Act / Assert
  return fnmatch "temp*" "temporary" && fnmatch "temp*" "temp" &&
    !fnmatch "temp*" "atemp"

def testFnmatchStarMiddle : IO Bool := do
  -- Arrange / Act / Assert
  return fnmatch "pre*suf" "presuf" && fnmatch "pre*suf" "pre-middle-suf" &&
    !fnmatch "pre*suf" "pre" && !fnmatch "pre*suf" "suf"

def testFnmatchStarContains : IO Bool := do
  -- Arrange / Act / Assert
  return fnmatch "*test*" "mytest1" && fnmatch "*test*" "test" &&
    !fnmatch "*test*" "tes"

def testFnmatchMultipleStars : IO Bool := do
  -- Arrange / Act / Assert
  return fnmatch "*a*b*" "xaybz" && fnmatch "*a*b*" "ab" &&
    !fnmatch "*a*b*" "ba"

-- fnmatch: ? wildcard

def testFnmatchQuestion : IO Bool := do
  -- Arrange / Act / Assert
  return fnmatch "?.txt" "a.txt" && !fnmatch "?.txt" "ab.txt" &&
    !fnmatch "?.txt" ".txt"

-- fnmatch: bracket expressions

def testFnmatchBracketClass : IO Bool := do
  -- Arrange / Act / Assert
  return fnmatch "[abc]" "a" && fnmatch "[abc]" "c" && !fnmatch "[abc]" "d"

def testFnmatchBracketRange : IO Bool := do
  -- Arrange / Act / Assert
  return fnmatch "[a-z]" "m" && fnmatch "[a-z]" "a" && fnmatch "[a-z]" "z" &&
    !fnmatch "[a-z]" "A" && !fnmatch "[a-z]" "0"

def testFnmatchBracketNegated : IO Bool := do
  -- Arrange / Act / Assert
  return fnmatch "[!0-9]" "a" && !fnmatch "[!0-9]" "5"

-- fnmatch: combined wildcards

def testFnmatchCombined : IO Bool := do
  -- Arrange / Act / Assert
  return fnmatch "*.spec.[jt]son" "build.spec.json" &&
    fnmatch "*.spec.[jt]son" "build.spec.tson" &&
    !fnmatch "*.spec.[jt]son" "build.spec.bson"

-- shouldIgnore

def testShouldIgnoreBasic : IO Bool := do
  -- Arrange / Act / Assert
  return shouldIgnore ["archive", "wip"] "archive" &&
    shouldIgnore ["archive", "wip"] "wip" &&
    !shouldIgnore ["archive", "wip"] "src"

def testShouldIgnoreNegation : IO Bool := do
  -- Arrange / Act / Assert
  return !shouldIgnore ["*.log", "!important.log"] "important.log" &&
    shouldIgnore ["*.log", "!important.log"] "debug.log"

def testShouldIgnoreLastMatchWins : IO Bool := do
  -- Arrange / Act / Assert
  return shouldIgnore ["*", "!keep", "keep"] "keep" &&
    !shouldIgnore ["*", "!keep"] "keep" &&
    shouldIgnore ["*", "!keep"] "other"

-- parseIgnoreFile

def testParseIgnoreFileSkipsCommentsAndBlanks : IO Bool := do
  -- Arrange / Act
  let patterns := parseIgnoreFile "# comment\narchive\n\nwip\n# another\n"
  -- Assert
  return patterns == ["archive", "wip"]

def ignoreTests : List (String × IO Bool) := [
  ("testFnmatchExactMatch", testFnmatchExactMatch),
  ("testFnmatchStarSuffix", testFnmatchStarSuffix),
  ("testFnmatchStarPrefix", testFnmatchStarPrefix),
  ("testFnmatchStarMiddle", testFnmatchStarMiddle),
  ("testFnmatchStarContains", testFnmatchStarContains),
  ("testFnmatchMultipleStars", testFnmatchMultipleStars),
  ("testFnmatchQuestion", testFnmatchQuestion),
  ("testFnmatchBracketClass", testFnmatchBracketClass),
  ("testFnmatchBracketRange", testFnmatchBracketRange),
  ("testFnmatchBracketNegated", testFnmatchBracketNegated),
  ("testFnmatchCombined", testFnmatchCombined),
  ("testShouldIgnoreBasic", testShouldIgnoreBasic),
  ("testShouldIgnoreNegation", testShouldIgnoreNegation),
  ("testShouldIgnoreLastMatchWins", testShouldIgnoreLastMatchWins),
  ("testParseIgnoreFileSkipsCommentsAndBlanks", testParseIgnoreFileSkipsCommentsAndBlanks)
]

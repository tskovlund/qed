import Tests.Types
import Tests.Parser
import Tests.TomlParser
import Tests.Integration
import Tests.Verifier
import Tests.ContractLock
import Tests.Cli

/-- Run a named test, print result, return whether it passed. -/
def runTest (name : String) (test : IO Bool) : IO Bool := do
  let passed ← test
  if passed then
    IO.println s!"PASS: {name}"
  else
    IO.eprintln s!"FAIL: {name}"
  return passed

def main : IO UInt32 := do
  let tests : List (String × IO Bool) :=
    typeTests ++ parserTests ++ tomlParserTests ++ integrationTests ++ verifierTests ++ contractLockTests ++ cliTests

  let mut failedCount : Nat := 0
  for (name, test) in tests do
    let passed ← runTest name test
    if !passed then
      failedCount := failedCount + 1

  IO.println ""
  if failedCount > 0 then
    IO.eprintln s!"{failedCount} test(s) failed"
    return 1
  else
    IO.println s!"All {tests.length} tests passed"
    return 0

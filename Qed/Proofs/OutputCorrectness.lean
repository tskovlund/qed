import Qed.Types
import Qed.Output

set_option autoImplicit false

namespace Qed.Proofs.OutputCorrectness

open Qed Qed.Output

-- 1. allPassed iff no failures

/-- `allPassed` returns true if and only if no result in the list is `.fail`.
This is the correctness theorem for the pass/fail decision — the single most
important output of the system. -/
theorem allPassed_iff_no_failures (results : List (String × VerificationResult)) :
    allPassed results = true ↔
      ∀ (pair : String × VerificationResult), pair ∈ results → pair.2.isFailed = false := by
  unfold allPassed
  simp [List.all_eq_true]

-- 2. resultsToJson always contains required fields

/-- The JSON output always contains the "spec", "passed", and "criteria" fields.
This is the output contract — consumers of qed's JSON can rely on these fields
being present regardless of input. -/
theorem resultsToJson_has_required_fields (specName : String)
    (results : List (String × VerificationResult)) :
    ∃ (specVal passedVal criteriaVal : Lean.Json),
      resultsToJson specName results = Lean.Json.mkObj [
        ("spec", specVal),
        ("passed", passedVal),
        ("criteria", criteriaVal)
      ] := by
  unfold resultsToJson
  exact ⟨_, _, _, rfl⟩

-- 3. workerResultsToJson always contains required fields

/-- The worker loop JSON output always contains "spec", "state", "passed", and
"criteria" fields. This extends the verify-mode contract with the additional
"state" field used by worker loop output. -/
theorem workerResultsToJson_has_required_fields (specName : String)
    (stateDescription : String)
    (results : List (String × VerificationResult)) :
    ∃ (specVal stateVal passedVal criteriaVal : Lean.Json),
      workerResultsToJson specName stateDescription results = Lean.Json.mkObj [
        ("spec", specVal),
        ("state", stateVal),
        ("passed", passedVal),
        ("criteria", criteriaVal)
      ] := by
  unfold workerResultsToJson
  exact ⟨_, _, _, _, rfl⟩

-- 4. allExecutionsPassed iff no failures (mirrors allPassed for CriterionExecution)

/-- `allExecutionsPassed` returns true if and only if no execution in the list
has a failed underlying result. This is the enriched-output equivalent of
`allPassed_iff_no_failures`. -/
theorem allExecutionsPassed_iff_no_failures
    (executions : List (String × CriterionExecution)) :
    allExecutionsPassed executions = true ↔
      ∀ (pair : String × CriterionExecution), pair ∈ executions →
        pair.2.isFailed = false := by
  unfold allExecutionsPassed CriterionExecution.isFailed
  simp [List.all_eq_true]

-- 5. executionsToJson always contains required fields

/-- The enriched JSON output always contains "spec", "passed", and "criteria"
fields. Mirrors `resultsToJson_has_required_fields` for the production path. -/
theorem executionsToJson_has_required_fields (specName : String)
    (executions : List (String × CriterionExecution)) :
    ∃ (specVal passedVal criteriaVal : Lean.Json),
      executionsToJson specName executions = Lean.Json.mkObj [
        ("spec", specVal),
        ("passed", passedVal),
        ("criteria", criteriaVal)
      ] := by
  unfold executionsToJson
  exact ⟨_, _, _, rfl⟩

-- 6. workerExecutionsToJson always contains required fields

/-- The enriched worker loop JSON always contains "spec", "state", "passed",
and "criteria" fields. Mirrors `workerResultsToJson_has_required_fields`. -/
theorem workerExecutionsToJson_has_required_fields (specName : String)
    (stateDescription : String)
    (executions : List (String × CriterionExecution)) :
    ∃ (specVal stateVal passedVal criteriaVal : Lean.Json),
      workerExecutionsToJson specName stateDescription executions = Lean.Json.mkObj [
        ("spec", specVal),
        ("state", stateVal),
        ("passed", passedVal),
        ("criteria", criteriaVal)
      ] := by
  unfold workerExecutionsToJson
  exact ⟨_, _, _, _, rfl⟩

end Qed.Proofs.OutputCorrectness

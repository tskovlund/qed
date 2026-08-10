import Qed.Types
import Qed.ContractLock

set_option autoImplicit false

namespace Qed.Proofs.LockRoundtrip

open Qed Qed.ContractLock Lean

/-! # Lock file writer–reader roundtrip

The reader inverts the writer at every level of `qed.lock`, so a renamed or
dropped field breaks the build instead of silently corrupting the lock.

Field lookups are stated as `rfl`-provable lemmas because `simp` cannot reduce
the `Std.TreeMap` backing `Json` objects on known keys, while kernel reduction
can. Mirrors `Roundtrip.lean`. -/

-- ═══════════════════════════════════════════════════════════════════
-- Level 1: LockedArtifact
-- ═══════════════════════════════════════════════════════════════════

/-- parseArtifact inverts artifactToJson. -/
theorem artifact_roundtrip (artifact : LockedArtifact) :
    parseArtifact (artifactToJson artifact) = .ok artifact := by
  cases artifact with
  | mk path hash => rfl

/-- Element-wise artifact roundtrip lifts to list-level mapM roundtrip. -/
theorem artifacts_list_roundtrip (artifacts : List LockedArtifact) :
    (artifacts.map artifactToJson).mapM parseArtifact = Except.ok artifacts := by
  induction artifacts with
  | nil => rfl
  | cons _ _ ih =>
    simp only [List.map, List.mapM_cons, artifact_roundtrip, bind, Except.bind]
    rw [ih]; rfl

-- ═══════════════════════════════════════════════════════════════════
-- Level 2: CriterionLock
-- ═══════════════════════════════════════════════════════════════════

private theorem clj_description (description : String) (artifacts : List LockedArtifact) :
    (criterionLockToJson { description, artifacts }).getObjValAs? String "description" =
      .ok description := by rfl

private theorem clj_artifacts (description : String) (artifacts : List LockedArtifact) :
    (criterionLockToJson { description, artifacts }).getObjVal? "artifacts" =
      .ok (Json.arr (artifacts.map artifactToJson).toArray) := by rfl

/-- parseCriterionLock inverts criterionLockToJson. -/
theorem criterionLock_roundtrip (lock : CriterionLock) :
    parseCriterionLock (criterionLockToJson lock) = .ok lock := by
  cases lock with
  | mk description artifacts =>
    unfold parseCriterionLock
    simp only [clj_description, clj_artifacts, bind, Except.bind,
      artifacts_list_roundtrip]

/-- Element-wise criterion-lock roundtrip lifts to list-level mapM roundtrip. -/
theorem criterionLocks_list_roundtrip (locks : List CriterionLock) :
    (locks.map criterionLockToJson).mapM parseCriterionLock = Except.ok locks := by
  induction locks with
  | nil => rfl
  | cons _ _ ih =>
    simp only [List.map, List.mapM_cons, criterionLock_roundtrip, bind, Except.bind]
    rw [ih]; rfl

-- ═══════════════════════════════════════════════════════════════════
-- Level 3: SpecLock
-- ═══════════════════════════════════════════════════════════════════

private theorem slj_specPath (specPath : String) (criteria : List CriterionLock) :
    (specLockToJson { specPath, criteria }).getObjValAs? String "specPath" =
      .ok specPath := by rfl

private theorem slj_criteria (specPath : String) (criteria : List CriterionLock) :
    (specLockToJson { specPath, criteria }).getObjVal? "criteria" =
      .ok (Json.arr (criteria.map criterionLockToJson).toArray) := by rfl

/-- parseSpecLock inverts specLockToJson. -/
theorem specLock_roundtrip (lock : SpecLock) :
    parseSpecLock (specLockToJson lock) = .ok lock := by
  cases lock with
  | mk specPath criteria =>
    unfold parseSpecLock
    simp only [slj_specPath, slj_criteria, bind, Except.bind,
      criterionLocks_list_roundtrip]

/-- Element-wise spec-lock roundtrip lifts to list-level mapM roundtrip. -/
theorem specLocks_list_roundtrip (locks : List SpecLock) :
    (locks.map specLockToJson).mapM parseSpecLock = Except.ok locks := by
  induction locks with
  | nil => rfl
  | cons _ _ ih =>
    simp only [List.map, List.mapM_cons, specLock_roundtrip, bind, Except.bind]
    rw [ih]; rfl

-- ═══════════════════════════════════════════════════════════════════
-- Level 4: LockFile
-- ═══════════════════════════════════════════════════════════════════

private theorem lfj_version (version : Nat) (specs : List SpecLock) :
    (lockFileToJson { version, specs }).getObjValAs? Nat "version" = .ok version := by rfl

private theorem lfj_specs (version : Nat) (specs : List SpecLock) :
    (lockFileToJson { version, specs }).getObjVal? "specs" =
      .ok (Json.arr (specs.map specLockToJson).toArray) := by rfl

/-- **Main roundtrip theorem:** parsing a serialized lock file recovers it
exactly, provided it carries the supported format version. -/
theorem lockFile_roundtrip (lockFile : LockFile)
    (hversion : lockFile.version = supportedLockFileVersion) :
    parseLockFileFromJson (lockFileToJson lockFile) = .ok lockFile := by
  cases lockFile with
  | mk version specs =>
    subst hversion
    unfold parseLockFileFromJson
    simp only [lfj_version, lfj_specs, bind, Except.bind,
      specLocks_list_roundtrip]
    rfl

/-- `generateLockFile` always stamps the supported version, so the roundtrip
holds unconditionally for lock files qed writes. -/
theorem generated_lockFile_roundtrip (specs : List SpecLock) :
    parseLockFileFromJson (lockFileToJson { specs }) = .ok { specs } :=
  lockFile_roundtrip { specs } rfl

end Qed.Proofs.LockRoundtrip

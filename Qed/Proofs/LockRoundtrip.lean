import Qed.Types
import Qed.ContractLock

set_option autoImplicit false

namespace Qed.Proofs.LockRoundtrip

open Qed Qed.ContractLock Lean

/-! # Lock file serializer–parser roundtrip proofs

The main result: `parseLockFileFromJson (lockFileToJson lockFile) = .ok lockFile`
for lock files carrying the supported format version. This guarantees that
`ContractLock`'s writer and reader agree on every field — a future rename or
dropped field breaks the proof at compile time.

## Strategy

Mirrors `Roundtrip.lean`. Lean 4.28.0 backs JSON objects with `Std.TreeMap`;
`simp` cannot reduce `TreeMap.get?` on known keys but `rfl` (kernel reduction)
can. So each level states its field lookups as `rfl`-provable lemmas, then
`simp only` uses those lemmas to reduce the parser:

1. `LockedArtifact` — path/hash, closes by `rfl` outright
2. `CriterionLock` — description + artifact array
3. `SpecLock` — spec path + criterion array
4. `LockFile` — version + spec array

Each array level needs a `mapM`/`map` induction lemma to lift the element-wise
roundtrip to lists.

## Scope

These theorems cover the `LockFile ↔ Json` layer. The outer string layer
(`serializeLockFile` = `Json.pretty`, `parseLockFile` = `Json.parse` + this)
is covered by `testLockFileRoundtrip` rather than a proof, since it rests on
`Json.parse ∘ Json.pretty = id` — a property of Lean's JSON library, not of
qed. This is the same boundary the spec roundtrip draws at
`specToJson`/`parseFromJson`. -/

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

/-- **Main roundtrip theorem:** parsing the serialized JSON of a lock file
recovers the lock file exactly, provided it carries the supported format
version. `generateLockFile` always stamps `supportedLockFileVersion`, and
`parseLockFileFromJson` rejects every other version, so this covers every lock
file qed produces. -/
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

/-- Every lock file qed generates satisfies the version hypothesis, so the
roundtrip holds unconditionally for freshly built lock files. -/
theorem generated_lockFile_roundtrip (specs : List SpecLock) :
    parseLockFileFromJson (lockFileToJson { specs }) = .ok { specs } :=
  lockFile_roundtrip { specs } rfl

end Qed.Proofs.LockRoundtrip

import Qed.Types

namespace Qed.Backend

/-- Identifier for a spec in a backend. -/
structure SpecId where
  value : String
  deriving Repr, BEq, Hashable

/-- Result of reporting loop state back to a backend. -/
inductive ReportResult where
  | ok
  | error (message : String)
  deriving Repr, BEq

/-- Interface for spec backends.

A backend is anything that can provide specs and receive results:
file system (JSON/YAML), Linear, Jira, GitHub Issues, databases, etc.

Implementing a new backend requires defining an instance of this class
for your backend type. -/
class Backend (β : Type) where
  /-- Human-readable name of this backend (e.g., "filesystem", "linear"). -/
  name : β → String
  /-- Fetch a spec by its identifier. -/
  fetchSpec : β → SpecId → IO (Except String Spec)
  /-- Report the final loop state back to the backend. -/
  reportResult : β → SpecId → LoopState → IO ReportResult
  /-- List all available spec identifiers. -/
  listSpecs : β → IO (Except String (List SpecId))

end Qed.Backend

import Qed.Types

set_option autoImplicit false

namespace Qed.Proofs.VerifyMode

open Qed

/-- The `SpecMode.verify` constructor cannot carry a `WorkerConfig`.
Any spec in verify mode has no worker configuration accessible from its mode.
This is a type-level fact: `SpecMode.verify` has no fields. -/
theorem verify_has_no_worker (spec : Spec) (h : spec.mode = .verify) :
    ∀ (worker : WorkerConfig) (loopConfig : LoopConfig),
      spec.mode ≠ .workerLoop worker loopConfig := by
  intros worker loopConfig
  rw [h]
  exact SpecMode.noConfusion

/-- Verify mode does not depend on the state machine transition function.
A spec in verify mode can be characterized without referencing `LoopState`,
`LoopConfig`, or `WorkerConfig` — the mode constructor carries no data. -/
theorem verify_independent_of_loop (mode : SpecMode) (h : mode = .verify) :
    ∀ (worker : WorkerConfig) (loopConfig : LoopConfig),
      mode ≠ .workerLoop worker loopConfig := by
  intros worker loopConfig
  rw [h]
  exact SpecMode.noConfusion

end Qed.Proofs.VerifyMode

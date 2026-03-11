import Qed

open Qed

-- isTerminal behavior tests have been replaced by the universal proof
-- isTerminal_iff in Qed/Proofs/TypeProperties.lean, which characterizes
-- exactly which states are terminal for ALL states, not just specific examples.

def typeTests : List (String × IO Bool) := []

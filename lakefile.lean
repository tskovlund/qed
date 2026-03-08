import Lake
open Lake DSL

package «qed» where
  leanOptions := #[
    ⟨`autoImplicit, false⟩
  ]

require "leanprover-community" / "batteries" @ git "v4.28.0"

lean_lib «Qed» where
  roots := #[`Qed]

@[default_target]
lean_exe «qed» where
  root := `Main

@[test_driver]
lean_exe «tests» where
  root := `Tests.Main

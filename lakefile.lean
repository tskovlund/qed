import Lake
open Lake DSL

package «qed» where
  leanOptions := #[
    ⟨`autoImplicit, false⟩
  ]

lean_lib «Qed» where
  roots := #[`Qed]

@[default_target]
lean_exe «qed» where
  root := `Main

@[test_driver]
lean_exe «tests» where
  root := `Tests.Main

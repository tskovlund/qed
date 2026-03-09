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

lean_lib «TestLib» where
  roots := #[`Tests.Types, `Tests.Parser, `Tests.Integration, `Tests.Verifier, `Tests.Cli]

@[test_driver]
lean_exe «tests» where
  root := `Tests.Main

lean_lib «DocGen» where
  roots := #[`DocGen.Schema, `DocGen.Markdown]

lean_exe «docgen» where
  root := `DocGen.Main

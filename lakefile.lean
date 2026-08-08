import Lake
open Lake DSL

package «qed» where
  leanOptions := #[
    ⟨`autoImplicit, false⟩,
    ⟨`warningAsError, true⟩,
    ⟨`linter.all, true⟩,
    ⟨`linter.missingDocs, false⟩,
    ⟨`linter.unusedVariables.analyzeTactics, true⟩
  ]

require "leanprover-community" / "batteries" @ git "v4.28.0"

lean_lib «Qed» where
  roots := #[`Qed]

@[default_target]
lean_exe «qed» where
  root := `Main

lean_lib «TestLib» where
  roots := #[`Tests.Types, `Tests.Parser, `Tests.TomlParser, `Tests.Integration, `Tests.Verifier, `Tests.ContractLock, `Tests.Ignore, `Tests.TomlSerializer, `Tests.Cli]

@[test_driver]
lean_exe «tests» where
  root := `Tests.Main

lean_lib «DocGen» where
  roots := #[`DocGen.Schema, `DocGen.Markdown]

lean_exe «docgen» where
  root := `DocGen.Main

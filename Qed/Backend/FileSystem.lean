import Qed.Backend.Backend

namespace Qed.Backend

/-- File system backend configuration.

Reads specs from JSON files on disk. The simplest backend —
no external services, no authentication, works offline. -/
structure FileSystemBackend where
  /-- Base directory to search for spec files. -/
  baseDir : String := "."
  /-- File extension to match (e.g., ".spec.json"). -/
  extension : String := ".spec.json"
  deriving Repr, BEq

instance : Backend FileSystemBackend where
  name fs := s!"filesystem({fs.baseDir})"

  fetchSpec _fs specId := do
    let path := specId.value
    let contents ← IO.FS.readFile ⟨path⟩
    -- TODO: parse JSON into Spec once Parser is implemented (TSK-154)
    return .error s!"JSON parsing not yet implemented for: {contents.take 50}..."

  reportResult _fs specId state := do
    let resultPath := specId.value ++ ".result"
    IO.FS.writeFile ⟨resultPath⟩ (toString (repr state))
    return .ok

  listSpecs fs := do
    let baseDir := fs.baseDir
    let entries ← System.FilePath.readDir ⟨baseDir⟩
    let specs := entries.filter fun entry =>
      entry.fileName.endsWith fs.extension
    let ids := specs.map fun entry =>
      SpecId.mk (baseDir ++ "/" ++ entry.fileName)
    return .ok ids.toList

end Qed.Backend

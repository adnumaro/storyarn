defmodule Storyarn.Projects.Imports.ImportQueue do
  @moduledoc false

  alias Storyarn.Projects.Imports.ImportLifecycle

  defdelegate enqueue_import(scope, attempt_id, strategy), to: ImportLifecycle
  defdelegate enqueue_import(scope, attempt_id, strategy, opts), to: ImportLifecycle
  defdelegate cancel_import(scope, attempt_id), to: ImportLifecycle
  defdelegate cancel_import(scope, attempt_id, opts), to: ImportLifecycle
  defdelegate subscribe_project_imports(project), to: ImportLifecycle
  defdelegate resume_latest_active_import(scope, project), to: ImportLifecycle
  defdelegate resume_latest_active_import(scope, project, opts), to: ImportLifecycle
  defdelegate resume_import(scope, project, attempt_id), to: ImportLifecycle
  defdelegate resume_import(scope, project, attempt_id, opts), to: ImportLifecycle
  defdelegate perform_import(attempt_id), to: ImportLifecycle
  defdelegate perform_import(attempt_id, opts), to: ImportLifecycle
  defdelegate expire_stale_imports(), to: ImportLifecycle
  defdelegate expire_stale_imports(opts), to: ImportLifecycle
  defdelegate expire_stale_imports_batch(), to: ImportLifecycle
  defdelegate expire_stale_imports_batch(opts), to: ImportLifecycle
end

defmodule Storyarn.Projects.Imports do
  @moduledoc false

  alias Storyarn.Projects.Imports.Cancellation
  alias Storyarn.Projects.Imports.ImportAttemptQueries
  alias Storyarn.Projects.Imports.ImportPreparation
  alias Storyarn.Projects.Imports.ImportQueue
  alias Storyarn.Projects.Imports.ImportReview

  defdelegate parse_file(filename, binary), to: ImportPreparation
  defdelegate preview(project_id, plan), to: ImportPreparation
  defdelegate execute(project, plan, opts \\ []), to: ImportPreparation
  defdelegate prepare_import(scope, project, filename, binary), to: ImportPreparation
  defdelegate prepare_import(scope, project, filename, binary, opts), to: ImportPreparation
  defdelegate resume_storage_key(scope, project), to: ImportPreparation

  defdelegate save_import_review(scope, attempt_id, decisions), to: ImportReview
  defdelegate save_import_review(scope, attempt_id, decisions, opts), to: ImportReview

  defdelegate resolve_import_review(scope, attempt_id, acknowledged?, decisions),
    to: ImportReview

  defdelegate resolve_import_review(scope, attempt_id, acknowledged?, decisions, opts),
    to: ImportReview

  defdelegate update_import_strategy(scope, attempt_id, strategy), to: ImportReview
  defdelegate update_import_mode(scope, attempt_id, mode), to: ImportReview

  defdelegate enqueue_import(scope, attempt_id, strategy), to: ImportQueue
  defdelegate enqueue_import(scope, attempt_id, strategy, opts), to: ImportQueue
  defdelegate cancel_import(scope, attempt_id), to: Cancellation
  defdelegate cancel_import(scope, attempt_id, opts), to: Cancellation
  defdelegate subscribe_project_imports(project), to: ImportQueue
  defdelegate resume_latest_active_import(scope, project), to: ImportQueue
  defdelegate resume_latest_active_import(scope, project, opts), to: ImportQueue
  defdelegate resume_import(scope, project, attempt_id), to: ImportQueue
  defdelegate resume_import(scope, project, attempt_id, opts), to: ImportQueue
  defdelegate perform_import(attempt_id), to: ImportQueue
  defdelegate perform_import(attempt_id, opts), to: ImportQueue
  defdelegate expire_stale_imports(), to: ImportQueue
  defdelegate expire_stale_imports(opts), to: ImportQueue
  defdelegate expire_stale_imports_batch(), to: ImportQueue
  defdelegate expire_stale_imports_batch(opts), to: ImportQueue

  defdelegate get_import_attempt(scope, attempt_id), to: ImportAttemptQueries
end

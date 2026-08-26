defmodule Storyarn.Projects.Interchange do
  @moduledoc """
  Project-owned boundary for importing and exporting project content.

  `Imports` and `Exports` keep their stable module identities for workers and
  compatibility, while this module is the capability boundary consumed by the
  root `Storyarn.Projects` facade.
  """

  alias Storyarn.Projects.Exports
  alias Storyarn.Projects.Exports.ExportOptions
  alias Storyarn.Projects.Exports.SizeGuard
  alias Storyarn.Projects.Imports
  alias Storyarn.Projects.Imports.ErrorDeduplicator
  alias Storyarn.Projects.Imports.ProjectImportAttempt

  @doc false
  @spec import_error_deduplicator_child_spec() :: Supervisor.child_spec()
  def import_error_deduplicator_child_spec do
    ErrorDeduplicator.child_spec([])
  end

  defdelegate prepare_download(scope, project, opts), to: Exports
  defdelegate validate_project(project_id, opts \\ %{}), to: Exports
  defdelegate count_entities(project_id, opts), to: Exports
  defdelegate list_formats_with_metadata(), to: Exports
  defdelegate valid_export_formats(), to: Exports
  defdelegate max_sync_export_bytes(), to: SizeGuard

  def export_options(attrs), do: struct(ExportOptions, attrs)

  defdelegate resume_storage_key(scope, project), to: Imports
  defdelegate subscribe_project_imports(project), to: Imports
  defdelegate get_import_attempt(scope, attempt_id), to: Imports
  defdelegate update_import_strategy(scope, attempt_id, strategy), to: Imports
  defdelegate update_import_mode(scope, attempt_id, mode), to: Imports
  defdelegate prepare_import(scope, project, filename, binary), to: Imports
  defdelegate prepare_import(scope, project, filename, binary, opts), to: Imports
  defdelegate enqueue_import(scope, attempt_id, strategy), to: Imports
  defdelegate enqueue_import(scope, attempt_id, strategy, opts), to: Imports
  defdelegate save_import_review(scope, attempt_id, decisions), to: Imports

  defdelegate resolve_import_review(scope, attempt_id, acknowledged, decisions),
    to: Imports

  defdelegate resume_latest_active_import(scope, project), to: Imports
  defdelegate resume_latest_active_import(scope, project, opts), to: Imports
  defdelegate resume_import(scope, project, attempt_id), to: Imports
  defdelegate resume_import(scope, project, attempt_id, opts), to: Imports
  defdelegate cancel_import(scope, attempt_id), to: Imports
  defdelegate active_import_statuses(), to: ProjectImportAttempt, as: :active_statuses

  @doc false
  defdelegate perform_import(attempt_id, opts), to: Imports

  @doc false
  defdelegate expire_stale_imports_batch(), to: Imports
end

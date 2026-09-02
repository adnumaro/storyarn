defmodule Storyarn.Projects.ProjectReconstitution do
  @moduledoc """
  Internal boundary for privileged whole-Project materialization.

  The lifecycle coordinators retain authorization, transactions, lock order,
  compensation and delivery ownership. This module only routes their exact
  inputs to the existing materialization engines and returns each result
  unchanged. In particular, options are forwarded intact because they carry
  caller-owned trackers, caches and test-injection seams.

  This is an internal coordination boundary of the Projects bounded context,
  not another capability or bounded context and not an alternative public
  facade for Web or workers.
  """

  alias Storyarn.Projects.Imports.ImportPlan
  alias Storyarn.Projects.Imports.Materializer
  alias Storyarn.Projects.Versioning.ProjectRecovery
  alias Storyarn.Projects.Versioning.ProjectSnapshotRestoreExecutor

  @doc false
  def preview_import(project_id, %ImportPlan{data: data}), do: Materializer.preview(project_id, data)

  def preview_import(_project_id, data) when is_map(data), do: {:error, :import_plan_required}

  @doc false
  def preflight_import_conflicts(project_id, plan, strategy) do
    Materializer.preflight_conflicts(project_id, plan, strategy)
  end

  @doc false
  def execute_import(project, plan, opts \\ []), do: Materializer.execute(project, plan, opts)

  @doc false
  def materialize_locked_import_in_transaction(project, plan, opts \\ []) do
    Materializer.materialize_locked_project_in_transaction(project, plan, opts)
  end

  @doc false
  def materialize_template(workspace_id, snapshot_data, user_id, opts \\ []) do
    ProjectRecovery.materialize_template(workspace_id, snapshot_data, user_id, opts)
  end

  @doc false
  def validate_snapshot_import(snapshot_data), do: ProjectRecovery.validate_snapshot_import(snapshot_data)

  @doc false
  def materialize_snapshot_import(workspace_id, snapshot_data, user_id, opts \\ []) do
    ProjectRecovery.materialize_snapshot_import(workspace_id, snapshot_data, user_id, opts)
  end

  @doc false
  def execute_snapshot_restore(restore, opts), do: ProjectSnapshotRestoreExecutor.execute(restore, opts)

  @doc false
  def settle_snapshot_restore_reservation(restore, opts \\ []) do
    ProjectSnapshotRestoreExecutor.settle_bound_reservation(restore, opts)
  end
end

defmodule Storyarn.Projects.WorkspaceDataLifecycle do
  @moduledoc false

  alias Storyarn.Projects.Assets
  alias Storyarn.Projects.Versioning

  @opaque hard_delete_preparation ::
            {__MODULE__, pos_integer(), [Storyarn.Projects.Versioning.SnapshotCleanupIntent.t()]}

  @doc """
  Prepares every Project-owned record that must be fenced before its parent
  Workspace can be hard-deleted.

  The caller owns the Workspace transaction and must already hold the canonical
  Billing workspace lock. Keeping that transaction open lets the database roll
  back these cleanup handoffs if a later Workspace-owned step fails.
  """
  @spec prepare_hard_delete(pos_integer()) ::
          {:ok, hard_delete_preparation()} | {:error, term()}
  def prepare_hard_delete(workspace_id) when is_integer(workspace_id) and workspace_id > 0 do
    if Storyarn.Commercial.workspace_lock_held?(workspace_id),
      do: {:error, :multipart_cleanup_provider_namespace_capture_required},
      else: {:error, :snapshot_cleanup_workspace_lock_required}
  end

  def prepare_hard_delete(_workspace_id), do: {:error, :invalid_workspace_project_cleanup_scope}

  @spec prepare_hard_delete(pos_integer(), String.t()) ::
          {:ok, hard_delete_preparation()} | {:error, term()}
  def prepare_hard_delete(workspace_id, provider_namespace_fingerprint)
      when is_integer(workspace_id) and workspace_id > 0 and is_binary(provider_namespace_fingerprint) do
    workspace_identity = %{id: workspace_id}

    with {:ok, snapshot_cleanup_intents} <-
           Versioning.prepare_workspace_snapshot_hard_delete(
             workspace_identity,
             provider_namespace_fingerprint
           ),
         :ok <- Versioning.prepare_workspace_snapshot_import_hard_delete(workspace_identity),
         :ok <- Assets.prepare_parent_hard_delete_locked(workspace_id, :all) do
      {:ok, {__MODULE__, workspace_id, snapshot_cleanup_intents}}
    end
  end

  def prepare_hard_delete(_workspace_id, _fingerprint), do: {:error, :invalid_workspace_project_cleanup_scope}

  @doc """
  Publishes Project snapshot cleanup facts after the Workspace deletion commits.

  Asset cleanup and snapshot cleanup ownership are persisted in the caller's
  transaction. Only snapshot lifecycle notifications need this post-commit
  publication step.
  """
  @spec publish_committed_hard_delete(hard_delete_preparation()) :: :ok | {:error, term()}
  def publish_committed_hard_delete({__MODULE__, workspace_id, snapshot_cleanup_intents})
      when is_integer(workspace_id) and workspace_id > 0 and is_list(snapshot_cleanup_intents) do
    Versioning.publish_committed_snapshot_cleanup_intents(snapshot_cleanup_intents)
  end

  def publish_committed_hard_delete(_preparation), do: {:error, :invalid_workspace_project_cleanup_preparation}
end

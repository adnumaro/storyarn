defmodule Storyarn.Projects.Assets.AssetTrashLifecycle do
  @moduledoc false

  alias Storyarn.Projects.Assets.AssetOperations

  defdelegate move_asset_to_trash(project_id, asset_id, actor_id), to: AssetOperations
  defdelegate move_assets_to_trash_locked(project_id, actor_id, asset_ids, opts \\ []), to: AssetOperations

  defdelegate restore_trashed_asset(project_id, asset_id, expected_generation, actor_id),
    to: AssetOperations

  defdelegate purge_trashed_asset(project_id, asset_id, expected_generation, actor_id),
    to: AssetOperations

  defdelegate purge_trashed_asset(project_id, asset_id, expected_generation, actor_id, opts),
    to: AssetOperations

  defdelegate purge_trashed_assets(project_id, candidates, actor_id), to: AssetOperations
  defdelegate prepare_parent_hard_delete_locked(workspace_id, project_scope), to: AssetOperations
  defdelegate lock_active_asset_references_for_restore(project_id, owner_ids), to: AssetOperations
end

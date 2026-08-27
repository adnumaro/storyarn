defmodule Storyarn.Projects.Assets.AssetReconstitution do
  @moduledoc """
  Exact import and snapshot-reconstitution writes for Project-owned asset records.

  These functions are not ordinary editor writes. Callers must already hold the
  enclosing Project import/restore locks required by their workflow.
  """

  alias Storyarn.Projects.Assets.AssetOperations

  defdelegate with_import_capacity(project, total_bytes, fun), to: AssetOperations
  defdelegate import_asset(project, attrs), to: AssetOperations
  defdelegate import_snapshot_asset(project, uploaded_by_id, attrs), to: AssetOperations

  defdelegate update_imported_snapshot_asset_locked(project, asset, metadata),
    to: AssetOperations

  defdelegate import_snapshot_assets_locked(project, uploaded_by_id, attrs_list),
    to: AssetOperations

  defdelegate update_imported_snapshot_assets_locked(project, updates), to: AssetOperations
  defdelegate update_imported_snapshot_assets_exact_locked(project, updates), to: AssetOperations
end

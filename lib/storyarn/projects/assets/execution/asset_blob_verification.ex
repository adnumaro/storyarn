defmodule Storyarn.Projects.Assets.AssetBlobVerification do
  @moduledoc false

  alias Storyarn.Projects.Assets.AssetOperations

  defdelegate ensure_active_asset_blobs(project_id), to: AssetOperations
  defdelegate ensure_asset_blobs(assets), to: AssetOperations
  defdelegate ensure_snapshot_asset_blobs(project_id, blob_specs), to: AssetOperations
end

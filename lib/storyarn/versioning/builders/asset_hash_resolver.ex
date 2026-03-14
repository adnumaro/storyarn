defmodule Storyarn.Versioning.Builders.AssetHashResolver do
  @moduledoc """
  Resolves asset references for versioning snapshots.

  Provides batch hash resolution for building snapshots and asset FK resolution
  for restoring snapshots. When an asset has been deleted but the snapshot
  contains its blob hash and metadata, a new asset can be recreated from the
  content-addressable blob.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Assets.{Asset, BlobStore}
  alias Storyarn.Repo

  @doc """
  Given a list of asset IDs, batch-loads their blob hashes and metadata.

  Returns `{hash_map, metadata_map}` where:
  - `hash_map` is `%{id_string => sha256_hash}`
  - `metadata_map` is `%{id_string => %{"filename" => ..., "content_type" => ..., "size" => ...}}`
  """
  @spec resolve_hashes([integer() | nil]) :: {map(), map()}
  def resolve_hashes(asset_ids) do
    asset_ids = asset_ids |> Enum.reject(&is_nil/1) |> Enum.uniq()

    if asset_ids == [] do
      {%{}, %{}}
    else
      assets =
        from(a in Asset, where: a.id in ^asset_ids)
        |> Repo.all()

      hash_map = Map.new(assets, &{to_string(&1.id), &1.blob_hash})

      metadata_map =
        Map.new(assets, fn asset ->
          {to_string(asset.id),
           %{
             "filename" => asset.filename,
             "content_type" => asset.content_type,
             "size" => asset.size,
             "url" => asset.url
           }}
        end)

      {hash_map, metadata_map}
    end
  end

  @doc """
  Resolves an asset FK during snapshot restore.

  Resolution order:
  1. Asset still exists by ID → return the ID
  2. Asset deleted but blob info in snapshot → recreate from blob → return new ID

  The `snapshot` must be the full snapshot map containing `"asset_blob_hashes"`
  and `"asset_metadata"` top-level keys.
  """
  @spec resolve_asset_fk(integer() | nil, map(), integer(), integer() | nil) :: integer() | nil
  def resolve_asset_fk(asset_id, snapshot, project_id, user_id \\ nil)
  def resolve_asset_fk(nil, _snapshot, _project_id, _user_id), do: nil

  def resolve_asset_fk(asset_id, snapshot, project_id, user_id) do
    if Repo.exists?(from(a in Asset, where: a.id == ^asset_id)) do
      asset_id
    else
      recreate_from_blob(asset_id, snapshot, project_id, user_id)
    end
  end

  defp recreate_from_blob(asset_id, snapshot, project_id, user_id) do
    id_str = to_string(asset_id)

    with blob_hash when is_binary(blob_hash) <- snapshot["asset_blob_hashes"][id_str],
         metadata when is_map(metadata) <- snapshot["asset_metadata"][id_str],
         {:ok, new_asset} <- create_from_blob(project_id, user_id, blob_hash, metadata) do
      new_asset.id
    else
      _ -> nil
    end
  end

  defp create_from_blob(project_id, user_id, blob_hash, metadata) do
    ext = BlobStore.ext_from_content_type(metadata["content_type"])
    blob_key = BlobStore.blob_key(project_id, blob_hash, ext)
    BlobStore.create_asset_from_blob(project_id, user_id, blob_hash, blob_key, metadata)
  end
end

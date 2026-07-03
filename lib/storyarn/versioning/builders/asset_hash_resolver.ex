defmodule Storyarn.Versioning.Builders.AssetHashResolver do
  @moduledoc """
  Resolves asset references for versioning snapshots.

  Provides batch hash resolution for building snapshots and asset FK resolution
  for restoring snapshots. When an asset has been deleted but the snapshot
  contains its blob hash and metadata, a new asset can be recreated from the
  content-addressable blob. Template clones can also force-copy assets into the
  destination project instead of reusing source project IDs.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Assets.Asset
  alias Storyarn.Assets.BlobStore
  alias Storyarn.Repo

  @doc """
  Given a list of asset IDs, batch-loads their blob hashes and metadata.

  Returns `{hash_map, metadata_map}` where:
  - `hash_map` is `%{id_string => sha256_hash}`
  - `metadata_map` is `%{id_string => %{"filename" => ..., "content_type" => ..., "size" => ..., "blob_key" => ...}}`
  """
  @spec resolve_hashes([integer() | nil]) :: {map(), map()}
  def resolve_hashes(asset_ids) do
    asset_ids = asset_ids |> Enum.reject(&is_nil/1) |> Enum.uniq()

    if asset_ids == [] do
      {%{}, %{}}
    else
      assets = Repo.all(from(a in Asset, where: a.id in ^asset_ids))

      hash_map = Map.new(assets, &{to_string(&1.id), &1.blob_hash})

      metadata_map =
        Map.new(assets, fn asset ->
          {to_string(asset.id),
           Map.merge(svg_sanitization_metadata(asset.metadata || %{}), %{
             "filename" => asset.filename,
             "content_type" => asset.content_type,
             "size" => asset.size,
             "key" => asset.key,
             "url" => asset.url,
             "project_id" => asset.project_id,
             "blob_key" => blob_key(asset)
           })}
        end)

      {hash_map, metadata_map}
    end
  end

  defp svg_sanitization_metadata(%{"sanitized_svg" => true}), do: %{"sanitized_svg" => true}
  defp svg_sanitization_metadata(_metadata), do: %{}

  defp blob_key(%Asset{blob_hash: blob_hash} = asset) when is_binary(blob_hash) do
    ext = BlobStore.ext_from_content_type(asset.content_type)
    BlobStore.blob_key(asset.project_id, asset.blob_hash, ext)
  end

  defp blob_key(%Asset{}), do: nil

  @doc """
  Resolves an asset FK during snapshot restore.

  Resolution modes:
  - `:reuse` (default) reuses an existing asset ID, recreating from blob only if
    the row no longer exists.
  - `:copy` always creates a new asset in the destination project from the
    snapshot blob/source storage key.
  - `:drop` returns nil.

  The `snapshot` must be the full snapshot map containing `"asset_blob_hashes"`
  and `"asset_metadata"` top-level keys.
  """
  @spec resolve_asset_fk(integer() | nil, map(), integer(), integer() | nil, keyword()) :: integer() | nil
  def resolve_asset_fk(asset_id, snapshot, project_id, user_id \\ nil, opts \\ [])
  def resolve_asset_fk(nil, _snapshot, _project_id, _user_id, _opts), do: nil

  def resolve_asset_fk(asset_id, snapshot, project_id, user_id, opts) do
    case Keyword.get(opts, :asset_mode, :reuse) do
      :drop ->
        nil

      :copy ->
        recreate_from_blob(asset_id, snapshot, project_id, user_id, opts)

      _reuse ->
        if Repo.exists?(from(a in Asset, where: a.id == ^asset_id)) do
          asset_id
        else
          recreate_from_blob(asset_id, snapshot, project_id, user_id, opts)
        end
    end
  end

  defp recreate_from_blob(asset_id, snapshot, project_id, user_id, opts) do
    id_str = to_string(asset_id)

    with blob_hash when is_binary(blob_hash) <- snapshot["asset_blob_hashes"][id_str],
         metadata when is_map(metadata) <- snapshot["asset_metadata"][id_str],
         {:ok, new_asset} <- create_from_blob(project_id, user_id, blob_hash, metadata, opts) do
      new_asset.id
    else
      _ -> nil
    end
  end

  defp create_from_blob(project_id, user_id, blob_hash, metadata, opts) do
    ext = BlobStore.ext_from_content_type(metadata["content_type"])
    source_key = source_storage_key(project_id, blob_hash, ext, metadata, opts)
    BlobStore.create_asset_from_blob(project_id, user_id, blob_hash, source_key, metadata)
  end

  defp source_storage_key(project_id, blob_hash, ext, metadata, opts) do
    case Keyword.get(opts, :asset_mode, :reuse) do
      :copy ->
        metadata["blob_key"] || metadata["key"] || BlobStore.blob_key(project_id, blob_hash, ext)

      _ ->
        metadata["blob_key"] || BlobStore.blob_key(project_id, blob_hash, ext)
    end
  end
end

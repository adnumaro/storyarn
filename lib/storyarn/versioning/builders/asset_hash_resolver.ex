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

  alias Storyarn.Assets
  alias Storyarn.Assets.Asset
  alias Storyarn.Assets.BlobStore
  alias Storyarn.Assets.Storage
  alias Storyarn.Repo
  alias Storyarn.Versioning.AssetMaterializationCache
  alias Storyarn.Versioning.Builders.AssetCopyError

  @sha256_regex ~r/\A[0-9a-f]{64}\z/
  @max_asset_size 52_428_800

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
      resolved_asset_maps(assets)
    end
  end

  @doc """
  Batch-loads hashes and metadata only when every referenced asset belongs to
  the project being snapshotted and its canonical content-addressed blob can
  be recovered with the persisted metadata.

  Entity snapshots use this strict variant so that a corrupt cross-project
  foreign key cannot become a portable reference to another project's asset.
  """
  @spec resolve_hashes_for_project!([integer() | nil], integer()) :: {map(), map()}
  def resolve_hashes_for_project!(asset_ids, project_id) do
    asset_ids =
      asset_ids
      |> Enum.reject(&is_nil/1)
      |> validate_snapshot_asset_ids!(project_id)
      |> Enum.uniq()
      |> Enum.sort()

    case asset_ids do
      [] -> {%{}, %{}}
      ids -> resolve_project_asset_maps!(ids, project_id)
    end
  end

  defp resolve_project_asset_maps!(asset_ids, project_id) do
    assets = Repo.all(from(a in Asset, where: a.id in ^asset_ids))
    assets_by_id = Map.new(assets, &{&1.id, &1})

    with :ok <- validate_assets_present(asset_ids, assets_by_id, project_id),
         :ok <- validate_asset_ownership(asset_ids, assets_by_id, project_id),
         :ok <- validate_assets_materializable(assets, project_id) do
      resolved_asset_maps(assets)
    end
  end

  defp validate_snapshot_asset_ids!(asset_ids, project_id) do
    case Enum.reject(asset_ids, &(is_integer(&1) and &1 > 0)) do
      [] ->
        asset_ids

      invalid_ids ->
        raise ArgumentError,
              "cannot snapshot invalid asset IDs #{inspect(invalid_ids)} for project #{project_id}"
    end
  end

  defp validate_assets_present(asset_ids, assets_by_id, project_id) do
    case Enum.reject(asset_ids, &Map.has_key?(assets_by_id, &1)) do
      [] ->
        :ok

      missing_ids ->
        raise ArgumentError,
              "cannot snapshot missing assets #{inspect(missing_ids)} for project #{project_id}"
    end
  end

  defp validate_asset_ownership(asset_ids, assets_by_id, project_id) do
    foreign_ids =
      Enum.reject(asset_ids, fn asset_id ->
        match?(%Asset{project_id: ^project_id}, assets_by_id[asset_id])
      end)

    case foreign_ids do
      [] ->
        :ok

      ids ->
        raise ArgumentError,
              "cannot snapshot assets #{inspect(ids)} owned by another project"
    end
  end

  defp validate_assets_materializable(assets, project_id) do
    Enum.reduce_while(assets, :ok, fn asset, :ok ->
      metadata = resolved_asset_metadata(asset)

      case portable_asset_entry(asset.blob_hash, metadata, project_id) do
        {:ok, _entry} ->
          {:cont, :ok}

        {:error, reason} ->
          raise ArgumentError,
                "cannot snapshot asset #{asset.id} for project #{project_id}: #{inspect(reason)}"
      end
    end)
  end

  defp resolved_asset_maps(assets) do
    hash_map = Map.new(assets, &{to_string(&1.id), &1.blob_hash})

    metadata_map =
      Map.new(assets, fn asset ->
        {to_string(asset.id), resolved_asset_metadata(asset)}
      end)

    {hash_map, metadata_map}
  end

  defp resolved_asset_metadata(asset) do
    Map.merge(svg_sanitization_metadata(asset.metadata || %{}), %{
      "filename" => asset.filename,
      "content_type" => asset.content_type,
      "size" => asset.size,
      "key" => asset.key,
      "url" => asset.url,
      "project_id" => asset.project_id,
      "blob_key" => blob_key(asset)
    })
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

  Options:
  - `:asset_error_mode` — `:tolerant` (legacy default) returns nil on copy
    failures; `:strict` raises `AssetCopyError`.
  - `:asset_materialization_cache` — a reference created by
    `AssetMaterializationCache.new/0`. Supplying it enables portable catalog
    validation and preserves one source-to-destination identity.
  - `:asset_source_keys` — an externally verified `%{blob_hash => storage_key}`
    catalog. Snapshot-provided storage keys never populate this option. When
    present, every resolved hash must exist in the catalog.
  - `:source_project_id` — when supplied, the snapshot catalog must identify
    this project as the canonical blob owner.
  """
  @spec resolve_asset_fk(integer() | nil, map(), integer(), integer() | nil, keyword()) :: integer() | nil
  def resolve_asset_fk(asset_id, snapshot, project_id, user_id \\ nil, opts \\ [])
  def resolve_asset_fk(nil, _snapshot, _project_id, _user_id, _opts), do: nil

  def resolve_asset_fk(asset_id, snapshot, project_id, user_id, opts) do
    case asset_mode(opts) do
      :drop ->
        nil

      mode when mode in [:reuse, :copy] ->
        if portable_resolution?(opts) do
          resolve_portable_asset(
            asset_id,
            snapshot,
            project_id,
            user_id,
            mode,
            opts
          )
        else
          resolve_legacy_tolerant_asset(
            asset_id,
            snapshot,
            project_id,
            user_id,
            mode,
            opts
          )
        end
    end
  end

  defp resolve_portable_asset(asset_id, snapshot, project_id, user_id, mode, opts) do
    result =
      with {:ok, entry} <- fetch_portable_asset_entry(asset_id, snapshot, opts) do
        resolve_cached_or_materialize(
          asset_id,
          project_id,
          user_id,
          mode,
          entry,
          opts
        )
      end

    case result do
      {:ok, destination_asset_id} -> destination_asset_id
      {:error, reason} -> handle_copy_error(asset_id, reason, opts)
    end
  end

  defp resolve_cached_or_materialize(asset_id, project_id, user_id, mode, entry, opts) do
    case fetch_cached_asset(opts, project_id, asset_id, entry.fingerprint, mode) do
      {:ok, destination_asset_id} ->
        {:ok, destination_asset_id}

      :miss ->
        with {:ok, destination_asset} <-
               materialize_portable_asset(
                 asset_id,
                 project_id,
                 user_id,
                 mode,
                 entry,
                 opts
               ),
             :ok <-
               cache_materialized_asset(
                 opts,
                 project_id,
                 asset_id,
                 entry.fingerprint,
                 mode,
                 destination_asset.id
               ) do
          {:ok, destination_asset.id}
        end

      {:error, _reason} = error ->
        error
    end
  end

  defp materialize_portable_asset(_asset_id, project_id, user_id, :copy, entry, opts) do
    create_from_portable_entry(project_id, user_id, entry, opts)
  end

  defp materialize_portable_asset(asset_id, project_id, user_id, :reuse, entry, opts) do
    case owned_reusable_asset(asset_id, project_id) do
      nil ->
        create_from_portable_entry(project_id, user_id, entry, opts)

      %Asset{} = asset ->
        if reusable_asset_matches?(asset, entry) do
          {:ok, asset}
        else
          {:error, :existing_asset_fingerprint_mismatch}
        end
    end
  end

  defp resolve_legacy_tolerant_asset(asset_id, snapshot, project_id, user_id, :copy, opts) do
    recreate_from_blob(asset_id, snapshot, project_id, user_id, opts)
  end

  defp resolve_legacy_tolerant_asset(asset_id, snapshot, project_id, user_id, :reuse, opts) do
    case owned_reusable_asset(asset_id, project_id) do
      %Asset{} -> asset_id
      nil -> recreate_from_blob(asset_id, snapshot, project_id, user_id, opts)
    end
  end

  defp owned_reusable_asset(asset_id, project_id) do
    query =
      from(a in Asset,
        where: a.id == ^asset_id and a.project_id == ^project_id,
        select: a
      )

    query = if Repo.in_transaction?(), do: lock(query, "FOR UPDATE"), else: query
    Repo.one(query)
  end

  defp recreate_from_blob(asset_id, snapshot, project_id, user_id, opts) do
    id_str = to_string(asset_id)
    blob_hashes = Map.get(snapshot, "asset_blob_hashes", %{})
    asset_metadata = Map.get(snapshot, "asset_metadata", %{})

    with {:ok, blob_hash} <- fetch_blob_hash(blob_hashes, id_str),
         {:ok, metadata} <- fetch_asset_metadata(asset_metadata, id_str),
         {:ok, new_asset} <- create_from_blob(project_id, user_id, blob_hash, metadata, opts) do
      new_asset.id
    else
      {:error, reason} -> handle_copy_error(asset_id, reason, opts)
    end
  end

  defp create_from_blob(project_id, user_id, blob_hash, metadata, opts) do
    with :ok <- validate_blob_hash(blob_hash),
         :ok <- validate_asset_filename(metadata["filename"]),
         :ok <- validate_asset_content_type(metadata, opts),
         :ok <- validate_asset_size(metadata["size"]) do
      ext = BlobStore.ext_from_content_type(metadata["content_type"])
      source_key = source_storage_key(project_id, blob_hash, ext, metadata, opts)

      BlobStore.create_asset_from_blob(
        project_id,
        user_id,
        blob_hash,
        source_key,
        materialization_metadata(metadata),
        opts
      )
    end
  end

  defp create_from_portable_entry(project_id, user_id, entry, opts) do
    BlobStore.create_asset_from_blob(
      project_id,
      user_id,
      entry.blob_hash,
      entry.source_key,
      entry.metadata,
      opts
    )
  end

  defp fetch_blob_hash(blob_hashes, id) do
    case Map.get(blob_hashes, id) do
      blob_hash when is_binary(blob_hash) -> {:ok, blob_hash}
      _blob_hash -> {:error, :missing_blob_hash}
    end
  end

  defp fetch_asset_metadata(asset_metadata, id) do
    case Map.get(asset_metadata, id) do
      %{"filename" => filename, "content_type" => content_type} = metadata
      when is_binary(filename) and is_binary(content_type) ->
        {:ok, metadata}

      _metadata ->
        {:error, :missing_asset_metadata}
    end
  end

  defp fetch_portable_asset_entry(asset_id, snapshot, opts) do
    id = to_string(asset_id)
    blob_hashes = Map.get(snapshot, "asset_blob_hashes", %{})
    asset_metadata = Map.get(snapshot, "asset_metadata", %{})

    with {:ok, blob_hash} <- fetch_blob_hash(blob_hashes, id),
         {:ok, metadata} <- fetch_asset_metadata(asset_metadata, id) do
      portable_asset_entry(
        blob_hash,
        metadata,
        Keyword.get(opts, :source_project_id),
        opts
      )
    end
  end

  defp portable_asset_entry(blob_hash, metadata, expected_source_project_id, opts \\ []) do
    with :ok <- validate_blob_hash(blob_hash),
         :ok <- validate_asset_filename(metadata["filename"]),
         :ok <- validate_asset_content_type(metadata, opts),
         :ok <- validate_asset_size(metadata["size"]),
         {:ok, source_project_id} <-
           validate_source_project_id(
             metadata["project_id"],
             expected_source_project_id
           ),
         {:ok, source_key} <-
           resolve_trusted_source_key(
             opts,
             source_project_id,
             blob_hash,
             metadata["content_type"]
           ) do
      materialization_metadata = materialization_metadata(metadata)

      with :ok <- validate_source_blob(source_key, metadata["size"]) do
        {:ok,
         %{
           blob_hash: blob_hash,
           metadata: materialization_metadata,
           source_key: source_key,
           fingerprint:
             asset_fingerprint(
               blob_hash,
               source_project_id,
               materialization_metadata,
               source_key
             )
         }}
      end
    end
  end

  defp validate_blob_hash(blob_hash) when is_binary(blob_hash) do
    if Regex.match?(@sha256_regex, blob_hash),
      do: :ok,
      else: {:error, :invalid_blob_hash}
  end

  defp validate_blob_hash(_blob_hash), do: {:error, :invalid_blob_hash}

  defp validate_asset_filename(filename) when is_binary(filename) do
    if String.valid?(filename) and String.trim(filename) != "" and
         valid_sanitized_filename_segment?(Assets.sanitize_filename(filename)) do
      :ok
    else
      {:error, :invalid_asset_filename}
    end
  end

  defp validate_asset_filename(_filename), do: {:error, :invalid_asset_filename}

  defp valid_sanitized_filename_segment?(filename) do
    filename not in ["", ".", ".."] and
      not String.contains?(filename, "/") and
      Storage.canonical_key?(filename)
  end

  defp validate_asset_content_type(%{"content_type" => "image/svg+xml", "sanitized_svg" => true}, opts) do
    if Keyword.has_key?(opts, :asset_source_keys),
      do: {:error, :unsupported_portable_svg},
      else: :ok
  end

  defp validate_asset_content_type(%{"content_type" => content_type}, _opts) do
    if Asset.allowed_content_type?(content_type),
      do: :ok,
      else: {:error, :invalid_asset_content_type}
  end

  defp validate_asset_content_type(_metadata, _opts), do: {:error, :invalid_asset_content_type}

  defp validate_asset_size(size) when is_integer(size) and size > 0 and size <= @max_asset_size, do: :ok

  defp validate_asset_size(_size), do: {:error, :invalid_asset_size}

  defp validate_source_project_id(source_project_id, nil) when is_integer(source_project_id) and source_project_id > 0,
    do: {:ok, source_project_id}

  defp validate_source_project_id(source_project_id, source_project_id)
       when is_integer(source_project_id) and source_project_id > 0, do: {:ok, source_project_id}

  defp validate_source_project_id(_source_project_id, _expected_source_project_id),
    do: {:error, :invalid_asset_source_project}

  defp resolve_trusted_source_key(opts, source_project_id, blob_hash, content_type) do
    case Keyword.fetch(opts, :asset_source_keys) do
      :error ->
        {:ok, canonical_blob_key(source_project_id, blob_hash, content_type)}

      {:ok, source_keys} when is_map(source_keys) ->
        with {:ok, source_key} <- Map.fetch(source_keys, blob_hash),
             true <- Storage.canonical_key?(source_key) do
          {:ok, source_key}
        else
          :error -> {:error, :missing_asset_source_key}
          false -> {:error, :invalid_asset_source_key}
        end

      {:ok, _invalid_source_keys} ->
        {:error, :invalid_asset_source_keys}
    end
  end

  defp validate_source_blob(source_key, expected_size) do
    case Storage.stat(source_key) do
      {:ok, %{size: ^expected_size}} ->
        :ok

      {:ok, %{size: actual_size}} ->
        {:error, {:asset_blob_size_mismatch, expected_size, actual_size}}

      {:error, reason} ->
        {:error, {:asset_blob_unavailable, reason}}

      _result ->
        {:error, :invalid_asset_blob_stat}
    end
  end

  defp canonical_blob_key(project_id, blob_hash, content_type) do
    ext = BlobStore.ext_from_content_type(content_type)
    BlobStore.blob_key(project_id, blob_hash, ext)
  end

  defp materialization_metadata(metadata) do
    materialization_metadata = Map.take(metadata, ["filename", "content_type", "size"])

    if metadata["sanitized_svg"] == true,
      do: Map.put(materialization_metadata, "sanitized_svg", true),
      else: materialization_metadata
  end

  defp asset_fingerprint(blob_hash, source_project_id, metadata, source_key) do
    %{
      blob_hash: blob_hash,
      source_project_id: source_project_id,
      source_key: source_key,
      filename: metadata["filename"],
      content_type: metadata["content_type"],
      size: metadata["size"],
      sanitized_svg: metadata["sanitized_svg"] == true
    }
  end

  defp reusable_asset_matches?(asset, entry) do
    asset.blob_hash == entry.fingerprint.blob_hash and
      asset.filename == entry.fingerprint.filename and
      asset.content_type == entry.fingerprint.content_type and
      asset.size == entry.fingerprint.size and
      sanitized_svg?(asset.metadata) == entry.fingerprint.sanitized_svg
  end

  defp sanitized_svg?(%{"sanitized_svg" => true}), do: true
  defp sanitized_svg?(_metadata), do: false

  defp fetch_cached_asset(opts, project_id, asset_id, fingerprint, mode) do
    case Keyword.get(opts, :asset_materialization_cache) do
      nil ->
        :miss

      reference when is_reference(reference) ->
        AssetMaterializationCache.fetch(
          reference,
          project_id,
          asset_id,
          fingerprint,
          mode
        )

      _invalid_reference ->
        {:error, :invalid_asset_materialization_cache}
    end
  end

  defp cache_materialized_asset(opts, project_id, asset_id, fingerprint, mode, destination_asset_id) do
    case Keyword.get(opts, :asset_materialization_cache) do
      nil ->
        :ok

      reference when is_reference(reference) ->
        AssetMaterializationCache.put(
          reference,
          project_id,
          asset_id,
          fingerprint,
          mode,
          destination_asset_id
        )

      _invalid_reference ->
        {:error, :invalid_asset_materialization_cache}
    end
  end

  defp asset_mode(opts) do
    case Keyword.get(opts, :asset_mode, :reuse) do
      :drop -> :drop
      :copy -> :copy
      _reuse -> :reuse
    end
  end

  defp portable_resolution?(opts) do
    Keyword.get(opts, :asset_error_mode, :tolerant) == :strict or
      Keyword.has_key?(opts, :asset_materialization_cache)
  end

  defp handle_copy_error(asset_id, reason, opts) do
    if Keyword.get(opts, :asset_error_mode, :tolerant) == :strict do
      raise AssetCopyError, asset_id: asset_id, reason: reason
    end
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

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
  @relationship_metadata_keys ~w(original_asset_id web_asset_id variant_asset_ids)
  @internal_metadata_keys ~w(
    blob_key key project_id storage_key thumbnail_key thumbnail_path url web_url
  )

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
      assets = Repo.all(from(a in Asset, where: a.id in ^asset_ids and is_nil(a.deleted_at)))
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

  @doc false
  @spec resolve_hashes_for_project_capture([{term(), map()}], integer()) ::
          {map(), map(), [map()]}
  def resolve_hashes_for_project_capture(references, project_id) when is_list(references) and is_integer(project_id) do
    positive_ids =
      references
      |> Enum.map(&elem(&1, 0))
      |> Enum.filter(&(is_integer(&1) and &1 > 0))
      |> Enum.uniq()

    assets_by_id =
      from(asset in Asset, where: asset.id in ^positive_ids)
      |> Repo.all()
      |> Map.new(&{&1.id, &1})

    {materializable_assets, issues} =
      Enum.reduce(references, {%{}, []}, fn {asset_id, context}, {assets, issues} ->
        capture_asset_reference(asset_id, context, assets_by_id, project_id, assets, issues)
      end)

    {hash_map, metadata_map} =
      materializable_assets
      |> Map.values()
      |> Enum.sort_by(& &1.id)
      |> resolved_asset_maps(:capture)

    {hash_map, metadata_map, Enum.reverse(issues)}
  end

  def resolve_hashes_for_project_capture(_references, _project_id), do: {%{}, %{}, []}

  @doc false
  @spec capture_catalog_maps([Asset.t()]) :: {map(), map()}
  def capture_catalog_maps(assets) when is_list(assets), do: resolved_asset_maps(assets, :capture)

  defp capture_asset_reference(nil, _context, _assets_by_id, _project_id, assets, issues), do: {assets, issues}

  defp capture_asset_reference(asset_id, context, _assets_by_id, _project_id, assets, issues)
       when not (is_integer(asset_id) and asset_id > 0) do
    {assets, [capture_asset_issue(:invalid_asset_reference, context) | issues]}
  end

  defp capture_asset_reference(asset_id, context, assets_by_id, project_id, assets, issues) do
    case Map.get(assets_by_id, asset_id) do
      nil ->
        {assets, [capture_asset_issue(:missing_asset_reference, context) | issues]}

      %Asset{project_id: owner_project_id} when owner_project_id != project_id ->
        {assets, [capture_asset_issue(:cross_project_asset_reference, context) | issues]}

      %Asset{deleted_at: deleted_at} when not is_nil(deleted_at) ->
        {assets, [capture_asset_issue(:inactive_asset_reference, context) | issues]}

      %Asset{} = asset ->
        case capture_materializable_asset(asset, project_id) do
          :ok ->
            {Map.put(assets, asset.id, asset), issues}

          {:error, _reason} ->
            {assets, [capture_asset_issue(:invalid_asset_snapshot_content, context) | issues]}
        end
    end
  end

  defp capture_materializable_asset(%Asset{metadata: metadata}, _project_id) when not is_map(metadata),
    do: {:error, :invalid_asset_metadata}

  defp capture_materializable_asset(%Asset{} = asset, project_id) do
    metadata =
      Map.merge(svg_sanitization_metadata(asset.metadata), %{
        "filename" => asset.filename,
        "content_type" => asset.content_type,
        "size" => asset.size,
        "project_id" => asset.project_id,
        "persisted_metadata" => asset.metadata
      })

    case validate_portable_catalog_entry(asset.blob_hash, metadata, project_id) do
      {:ok, ^project_id} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp capture_asset_issue(code, context) do
    context
    |> Map.take([:entity_type, :entity_id, :source_field, :container_type, :container_id])
    |> Map.merge(%{code: code, severity: :warning, impact: :restore_blocked})
  end

  defp resolve_project_asset_maps!(asset_ids, project_id) do
    assets = Repo.all(from(a in Asset, where: a.id in ^asset_ids and is_nil(a.deleted_at)))
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

  defp resolved_asset_maps(assets, mode \\ :strict) do
    hash_map = Map.new(assets, &{to_string(&1.id), &1.blob_hash})

    metadata_map =
      Map.new(assets, fn asset ->
        {to_string(asset.id), resolved_asset_metadata(asset, mode)}
      end)

    {hash_map, metadata_map}
  end

  defp resolved_asset_metadata(asset, mode \\ :strict) do
    persisted_metadata = asset.metadata
    metadata = persisted_metadata || %{}

    portable_metadata =
      Map.merge(svg_sanitization_metadata(metadata), %{
        "filename" => asset.filename,
        "content_type" => asset.content_type,
        "size" => asset.size,
        "key" => asset.key,
        "url" => asset.url,
        "project_id" => asset.project_id,
        "blob_key" => blob_key(asset)
      })

    if mode == :capture do
      portable_metadata
      |> Map.merge(Map.take(metadata, @relationship_metadata_keys))
      |> Map.put("persisted_metadata", capture_persisted_metadata(persisted_metadata))
    else
      portable_metadata
    end
  end

  defp capture_persisted_metadata(metadata) when is_map(metadata), do: Map.drop(metadata, @internal_metadata_keys)

  defp capture_persisted_metadata(nil), do: nil

  defp svg_sanitization_metadata(%{"sanitized_svg" => true}), do: %{"sanitized_svg" => true}
  defp svg_sanitization_metadata(_metadata), do: %{}

  defp blob_key(%Asset{blob_hash: blob_hash, content_type: content_type} = asset)
       when is_binary(blob_hash) and is_binary(content_type) do
    ext = BlobStore.ext_from_content_type(asset.content_type)
    BlobStore.blob_key(asset.project_id, asset.blob_hash, ext)
  end

  defp blob_key(%Asset{}), do: nil

  @doc """
  Resolves an asset FK during snapshot restore.

  Resolution modes:
  - `:reuse` (default) reuses an existing asset ID only after its complete
    portable catalog entry and backing object have been verified.
  - `:copy` always creates a new asset in the destination project from the
    snapshot blob/source storage key.
  - `:drop` returns nil.

  The `snapshot` must be the full snapshot map containing `"asset_blob_hashes"`
  and `"asset_metadata"` top-level keys.

  Options:
  - `:asset_materialization_cache` — a reference created by
    `AssetMaterializationCache.new/0`. Supplying it enables portable catalog
    validation and preserves one source-to-destination identity.
  - `:pre_materialized_assets` — resolves exclusively from entries already
    loaded into the materialization cache. This path performs no storage I/O
    and never falls back to a current asset or blob copy.
  - `:asset_source_keys` — an externally verified `%{blob_hash => storage_key}`
    catalog. Snapshot-provided storage keys never populate this option. When
    present, every resolved hash must exist in the catalog.
  - `:source_project_id` — when supplied, the snapshot catalog must identify
    this project as the canonical blob owner.
  - `:expected_content_type_prefix` — when supplied, both reused and recreated
    assets must match the semantic MIME family required by the destination
    slot (for example, `"audio/"` or `"image/"`).
  - `:asset_context` — identifies the destination slot in a content-type
    mismatch error.
  """
  @spec resolve_asset_fk(integer() | nil, map(), integer(), integer() | nil, keyword()) :: integer() | nil
  def resolve_asset_fk(asset_id, snapshot, project_id, user_id \\ nil, opts \\ [])
  def resolve_asset_fk(nil, _snapshot, _project_id, _user_id, _opts), do: nil

  def resolve_asset_fk(asset_id, snapshot, project_id, user_id, opts) do
    case Keyword.get(opts, :pre_materialized_assets, false) do
      true ->
        resolve_pre_materialized_asset(asset_id, snapshot, project_id, opts)

      false ->
        case asset_mode(opts) do
          :drop ->
            nil

          mode when mode in [:reuse, :copy] ->
            resolve_portable_asset(
              asset_id,
              snapshot,
              project_id,
              user_id,
              mode,
              opts
            )
        end

      invalid ->
        raise AssetCopyError,
          asset_id: asset_id,
          reason: {:invalid_pre_materialized_assets_option, invalid}
    end
  end

  @doc """
  Loads an exact historical-to-materialized asset mapping into a cache.

  The destination rows must already belong to the target project and match the
  storage-independent snapshot fingerprint. No object is read or copied.
  """
  @spec preload_materialized_assets(map(), %{integer() => integer()}, integer(), reference()) ::
          :ok | {:error, term()}
  def preload_materialized_assets(snapshot, materialized_asset_ids, project_id, cache)
      when is_map(snapshot) and is_map(materialized_asset_ids) and is_integer(project_id) and project_id > 0 and
             is_reference(cache) do
    materialized_asset_ids
    |> Enum.sort_by(fn {source_asset_id, _destination_asset_id} -> source_asset_id end)
    |> Enum.reduce_while(:ok, fn {source_asset_id, destination_asset_id}, :ok ->
      case preload_materialized_asset(
             snapshot,
             source_asset_id,
             destination_asset_id,
             project_id,
             cache
           ) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {:asset_materialization_failed, source_asset_id, reason}}}
      end
    end)
  end

  def preload_materialized_assets(_snapshot, _materialized_asset_ids, _project_id, _cache),
    do: {:error, :invalid_pre_materialized_asset_mapping}

  @doc false
  @spec validate_pre_materialized_catalogs(map(), map(), [map()]) :: :ok | {:error, term()}
  def validate_pre_materialized_catalogs(snapshot, source_refs, assets)
      when is_map(snapshot) and is_map(source_refs) and is_list(assets) do
    assets_by_logical_id = Map.new(assets, &{&1["logical_id"], &1})

    with :ok <- validate_pre_materialized_catalog_surfaces(snapshot, source_refs, assets_by_logical_id) do
      validate_pre_materialized_asset_slots(snapshot, source_refs, assets_by_logical_id)
    end
  end

  def validate_pre_materialized_catalogs(_snapshot, _source_refs, _assets),
    do: {:error, :invalid_pre_materialized_asset_catalogs}

  defp validate_pre_materialized_catalog_surfaces(snapshot, source_refs, assets_by_logical_id) do
    Enum.reduce_while([snapshot | project_entity_snapshots(snapshot)], :ok, fn entity_snapshot, :ok ->
      case validate_pre_materialized_entity_catalog(entity_snapshot, source_refs, assets_by_logical_id) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp validate_pre_materialized_asset_slots(snapshot, source_refs, assets_by_logical_id) do
    snapshot
    |> pre_materialized_asset_slots()
    |> Enum.reduce_while(:ok, fn slot, :ok ->
      case validate_pre_materialized_asset_slot(slot, snapshot, source_refs, assets_by_logical_id) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp validate_pre_materialized_asset_slot(
         %{source_id: source_id, content_type_prefix: content_type_prefix, context: context},
         snapshot,
         source_refs,
         assets_by_logical_id
       )
       when is_integer(source_id) and source_id > 0 do
    source_ref = Integer.to_string(source_id)

    with {:ok, logical_id} <- Map.fetch(source_refs, source_ref),
         {:ok, asset} <- Map.fetch(assets_by_logical_id, logical_id),
         [_catalog | _rest] <- pre_materialized_asset_catalogs(snapshot, source_ref),
         content_type when is_binary(content_type) <- asset["content_type"],
         true <- String.starts_with?(content_type, content_type_prefix) do
      :ok
    else
      false ->
        {:error,
         {:pre_materialized_asset_content_type_mismatch, context, source_id, content_type_prefix,
          asset_content_type(source_refs, assets_by_logical_id, source_ref)}}

      :error ->
        {:error, {:pre_materialized_asset_reference_missing, context, source_id}}

      [] ->
        {:error, {:pre_materialized_asset_catalog_missing, context, source_id}}

      _invalid ->
        {:error,
         {:pre_materialized_asset_content_type_mismatch, context, source_id, content_type_prefix,
          asset_content_type(source_refs, assets_by_logical_id, source_ref)}}
    end
  end

  defp validate_pre_materialized_asset_slot(
         %{source_id: source_id, context: context},
         _snapshot,
         _source_refs,
         _assets_by_logical_id
       ) do
    {:error, {:invalid_pre_materialized_asset_reference, context, source_id}}
  end

  defp asset_content_type(source_refs, assets_by_logical_id, source_ref) do
    with {:ok, logical_id} <- Map.fetch(source_refs, source_ref),
         {:ok, asset} <- Map.fetch(assets_by_logical_id, logical_id) do
      asset["content_type"]
    else
      _missing -> nil
    end
  end

  defp pre_materialized_asset_slots(snapshot) do
    localization_asset_slots(snapshot, :project) ++
      entity_asset_slots(snapshot, "sheets", &sheet_asset_slots/1) ++
      entity_asset_slots(snapshot, "flows", &flow_asset_slots/1) ++
      entity_asset_slots(snapshot, "scenes", &scene_asset_slots/1)
  end

  defp entity_asset_slots(snapshot, collection, slot_fun) do
    snapshot
    |> list_field(collection)
    |> Enum.flat_map(fn
      %{"snapshot" => entity_snapshot} when is_map(entity_snapshot) -> slot_fun.(entity_snapshot)
      _invalid -> []
    end)
  end

  defp sheet_asset_slots(snapshot) do
    direct =
      [
        asset_slot(snapshot["avatar_asset_id"], "image/", {:sheet, :avatar}),
        asset_slot(snapshot["banner_asset_id"], "image/", {:sheet, :banner})
      ]

    avatars =
      snapshot
      |> list_field("avatars")
      |> Enum.with_index()
      |> Enum.map(fn {avatar, index} ->
        asset_slot(map_value(avatar, "asset_id"), "image/", {:sheet_avatar, index})
      end)

    gallery_images =
      snapshot
      |> list_field("blocks")
      |> Enum.with_index()
      |> Enum.flat_map(fn {block, block_index} ->
        block
        |> list_field("gallery_images")
        |> Enum.with_index()
        |> Enum.map(fn {image, image_index} ->
          asset_slot(
            map_value(image, "asset_id"),
            "image/",
            {:sheet_gallery_image, block_index, image_index}
          )
        end)
      end)

    compact_asset_slots(direct ++ avatars ++ gallery_images ++ localization_asset_slots(snapshot, :sheet))
  end

  defp flow_asset_slots(snapshot) do
    node_slots =
      snapshot
      |> list_field("nodes")
      |> Enum.with_index()
      |> Enum.flat_map(fn {node, node_index} ->
        data = map_field(node, "data")

        audio =
          asset_slot(data["audio_asset_id"], "audio/", {:flow_node_audio, node_index})

        tracks =
          node
          |> list_field("sequence_tracks")
          |> Enum.with_index()
          |> Enum.map(fn {track, track_index} ->
            asset_slot(
              map_value(track, "asset_id"),
              "audio/",
              {:flow_sequence_track, node_index, track_index}
            )
          end)

        visual_layers =
          node
          |> list_field("sequence_visual_layers")
          |> Enum.with_index()
          |> Enum.map(fn {layer, layer_index} ->
            asset_slot(
              map_value(layer, "asset_id"),
              "image/",
              {:flow_sequence_visual_layer, node_index, layer_index}
            )
          end)

        [audio | tracks ++ visual_layers]
      end)

    compact_asset_slots(node_slots ++ localization_asset_slots(snapshot, :flow))
  end

  defp scene_asset_slots(snapshot) do
    direct = [asset_slot(snapshot["background_asset_id"], "image/", {:scene, :background})]

    layer_slots =
      snapshot
      |> list_field("layers")
      |> Enum.with_index()
      |> Enum.flat_map(fn {layer, layer_index} ->
        scene_pin_slots(layer, {:scene_layer, layer_index}) ++
          scene_zone_slots(layer, {:scene_layer, layer_index})
      end)

    orphan_slots =
      scene_pin_slots(snapshot, :scene_orphan) ++ scene_zone_slots(snapshot, :scene_orphan)

    compact_asset_slots(direct ++ layer_slots ++ orphan_slots)
  end

  defp scene_pin_slots(container, context) do
    key = if context == :scene_orphan, do: "orphan_pins", else: "pins"

    container
    |> list_field(key)
    |> Enum.with_index()
    |> Enum.map(fn {pin, index} ->
      asset_slot(map_value(pin, "icon_asset_id"), "image/", {:scene_pin_icon, context, index})
    end)
  end

  defp scene_zone_slots(container, context) do
    key = if context == :scene_orphan, do: "orphan_zones", else: "zones"

    container
    |> list_field(key)
    |> Enum.with_index()
    |> Enum.map(fn {zone, index} ->
      asset_slot(map_value(zone, "label_icon_asset_id"), "image/", {:scene_zone_icon, context, index})
    end)
  end

  defp localization_asset_slots(snapshot, context) do
    snapshot
    |> localization_rows()
    |> Enum.with_index()
    |> Enum.map(fn {text, index} ->
      asset_slot(map_value(text, "vo_asset_id"), "audio/", {:localization_voice_over, context, index})
    end)
    |> compact_asset_slots()
  end

  defp localization_rows(snapshot) when is_map(snapshot) do
    case Map.get(snapshot, "localization") do
      rows when is_list(rows) -> rows
      %{"texts" => rows} when is_list(rows) -> rows
      _invalid -> []
    end
  end

  defp localization_rows(_snapshot), do: []

  defp asset_slot(nil, _content_type_prefix, _context), do: nil

  defp asset_slot(source_id, content_type_prefix, context) do
    %{source_id: source_id, content_type_prefix: content_type_prefix, context: context}
  end

  defp compact_asset_slots(slots), do: Enum.reject(slots, &is_nil/1)

  defp list_field(map, key) when is_map(map) do
    case Map.get(map, key, []) do
      value when is_list(value) -> value
      _invalid -> []
    end
  end

  defp list_field(_map, _key), do: []

  defp map_value(map, key) when is_map(map), do: Map.get(map, key)
  defp map_value(_map, _key), do: nil

  defp validate_pre_materialized_entity_catalog(entity_snapshot, source_refs, assets_by_logical_id) do
    hashes = map_field(entity_snapshot, "asset_blob_hashes")
    metadata = map_field(entity_snapshot, "asset_metadata")
    keys = hashes |> Map.keys() |> Enum.concat(Map.keys(metadata)) |> Enum.uniq()

    Enum.reduce_while(keys, :ok, fn source_id, :ok ->
      result =
        with {:ok, hash} <- Map.fetch(hashes, source_id),
             {:ok, asset_metadata} <- Map.fetch(metadata, source_id),
             {:ok, logical_id} <- Map.fetch(source_refs, source_id),
             {:ok, asset} <- Map.fetch(assets_by_logical_id, logical_id),
             true <- hash == asset["sha256"],
             true <- asset_metadata_matches_manifest?(asset_metadata, asset) do
          :ok
        else
          _mismatch -> {:error, {:pre_materialized_asset_catalog_mismatch, source_id}}
        end

      case result do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp asset_metadata_matches_manifest?(metadata, asset) when is_map(metadata) and is_map(asset) do
    metadata["filename"] == asset["filename"] and
      metadata["content_type"] == asset["content_type"] and
      metadata["size"] == asset["size_bytes"] and
      metadata["sanitized_svg"] == true == (asset["metadata"]["sanitized_svg"] == true)
  end

  defp asset_metadata_matches_manifest?(_metadata, _asset), do: false

  defp preload_materialized_asset(snapshot, source_asset_id, destination_asset_id, project_id, cache)
       when is_integer(source_asset_id) and source_asset_id > 0 and is_integer(destination_asset_id) and
              destination_asset_id > 0 do
    case pre_materialized_asset_catalogs(snapshot, to_string(source_asset_id)) do
      [] ->
        :ok

      _catalogs ->
        with {:ok, entry} <- fetch_pre_materialized_asset_entry(source_asset_id, snapshot) do
          AssetMaterializationCache.put(
            cache,
            project_id,
            source_asset_id,
            entry.fingerprint,
            :copy,
            destination_asset_id
          )
        end
    end
  end

  defp preload_materialized_asset(_snapshot, _source_asset_id, _destination_asset_id, _project_id, _cache),
    do: {:error, :invalid_pre_materialized_asset_mapping}

  defp resolve_pre_materialized_asset(asset_id, snapshot, project_id, opts) do
    result =
      with {:ok, entry} <- fetch_pre_materialized_asset_entry(asset_id, snapshot),
           :ok <- validate_expected_content_type(asset_id, entry, opts) do
        fetch_pre_materialized_asset(opts, project_id, asset_id, entry.fingerprint)
      end

    case result do
      {:ok, destination_asset_id} -> destination_asset_id
      {:error, reason} -> raise AssetCopyError, asset_id: asset_id, reason: reason
    end
  end

  defp fetch_pre_materialized_asset(opts, project_id, asset_id, fingerprint) do
    case fetch_cached_asset(opts, project_id, asset_id, fingerprint, :copy) do
      :miss -> {:error, :missing_pre_materialized_asset_mapping}
      result -> result
    end
  end

  defp resolve_portable_asset(asset_id, snapshot, project_id, user_id, mode, opts) do
    result =
      with {:ok, entry} <- fetch_portable_asset_entry(asset_id, snapshot, opts),
           :ok <- validate_expected_content_type(asset_id, entry, opts) do
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
      {:error, reason} -> raise AssetCopyError, asset_id: asset_id, reason: reason
    end
  end

  defp validate_expected_content_type(asset_id, entry, opts) do
    case Keyword.get(opts, :expected_content_type_prefix) do
      nil ->
        :ok

      prefix when is_binary(prefix) ->
        if String.starts_with?(entry.metadata["content_type"], prefix) do
          :ok
        else
          {:error,
           {:invalid_asset_content_type, Keyword.get(opts, :asset_context), asset_id, entry.metadata["content_type"]}}
        end

      invalid_prefix ->
        {:error, {:invalid_expected_content_type_prefix, invalid_prefix}}
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

  defp owned_reusable_asset(asset_id, project_id) do
    query =
      from(a in Asset,
        where:
          a.id == ^asset_id and a.project_id == ^project_id and
            is_nil(a.deleted_at),
        select: a
      )

    query = if Repo.in_transaction?(), do: lock(query, "FOR UPDATE"), else: query
    Repo.one(query)
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

  defp fetch_pre_materialized_asset_entry(asset_id, snapshot) do
    id = to_string(asset_id)
    catalogs = pre_materialized_asset_catalogs(snapshot, id)

    case catalogs do
      [] ->
        {:error, :missing_blob_hash}

      catalogs ->
        Enum.reduce_while(catalogs, {:ok, nil}, &merge_pre_materialized_asset_entry(&1, &2, id))
    end
  end

  defp merge_pre_materialized_asset_entry(catalog, {:ok, expected_entry}, id) do
    case pre_materialized_asset_entry(catalog, id) do
      {:ok, entry} when is_nil(expected_entry) ->
        {:cont, {:ok, entry}}

      {:ok, ^expected_entry} ->
        {:cont, {:ok, expected_entry}}

      {:ok, _conflicting_entry} ->
        {:halt, {:error, :conflicting_pre_materialized_asset_metadata}}

      {:error, _reason} = error ->
        {:halt, error}
    end
  end

  defp pre_materialized_asset_entry({blob_hashes, asset_metadata}, id) do
    with {:ok, blob_hash} <- fetch_blob_hash(blob_hashes, id),
         {:ok, metadata} <- fetch_asset_metadata(asset_metadata, id),
         :ok <- validate_blob_hash(blob_hash),
         :ok <- validate_asset_filename(metadata["filename"]),
         :ok <- validate_asset_content_type(metadata, []),
         :ok <- validate_asset_size(metadata["size"]) do
      materialization_metadata = materialization_metadata(metadata)

      {:ok,
       %{
         metadata: materialization_metadata,
         fingerprint: pre_materialized_fingerprint(blob_hash, materialization_metadata)
       }}
    end
  end

  defp pre_materialized_asset_catalogs(snapshot, id) do
    Enum.flat_map([snapshot | project_entity_snapshots(snapshot)], fn snapshot_surface ->
      blob_hashes = map_field(snapshot_surface, "asset_blob_hashes")
      asset_metadata = map_field(snapshot_surface, "asset_metadata")

      if Map.has_key?(blob_hashes, id) or Map.has_key?(asset_metadata, id) do
        [{blob_hashes, asset_metadata}]
      else
        []
      end
    end)
  end

  defp map_field(map, key) when is_map(map) do
    case Map.get(map, key) do
      value when is_map(value) -> value
      _value -> %{}
    end
  end

  defp map_field(_map, _key), do: %{}

  defp project_entity_snapshots(snapshot) do
    Enum.flat_map(~w(sheets flows scenes), fn collection ->
      snapshot
      |> Map.get(collection, [])
      |> Enum.flat_map(fn
        %{"snapshot" => entity_snapshot} when is_map(entity_snapshot) -> [entity_snapshot]
        _entry -> []
      end)
    end)
  end

  defp portable_asset_entry(blob_hash, metadata, expected_source_project_id, opts \\ []) do
    with {:ok, source_project_id} <-
           validate_portable_catalog_entry(
             blob_hash,
             metadata,
             expected_source_project_id,
             opts
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

  @doc """
  Validates the pure, storage-independent contract of a portable asset catalog
  entry.

  Preview and materialization share this boundary. Object existence and size
  are intentionally checked later by the materializer because they require
  storage I/O.
  """
  @spec validate_portable_catalog_entry(binary(), map(), integer() | nil, keyword()) ::
          {:ok, pos_integer()} | {:error, term()}
  def validate_portable_catalog_entry(blob_hash, metadata, expected_source_project_id, opts \\ []) do
    with :ok <- validate_blob_hash(blob_hash),
         :ok <- validate_asset_filename(metadata["filename"]),
         :ok <- validate_asset_content_type(metadata, opts),
         :ok <- validate_asset_size(metadata["size"]) do
      validate_source_project_id(
        metadata["project_id"],
        expected_source_project_id
      )
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

  defp pre_materialized_fingerprint(blob_hash, metadata) do
    %{
      blob_hash: blob_hash,
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
end

defmodule Storyarn.Versioning.SnapshotObjectFormat do
  @moduledoc """
  Defines the canonical, self-contained project snapshot object set.

  A ready snapshot owns one immutable namespace containing `manifest.json`,
  `project.json`, and one content-addressed blob for each unique verified
  SHA-256 digest. Asset catalog entries are logical records: duplicate
  filenames remain distinct while equal content shares a snapshot-owned blob.
  """

  alias Storyarn.Assets.Asset
  alias Storyarn.Assets.BlobStore
  alias Storyarn.Assets.Storage

  @format "storyarn.project_snapshot"
  @format_version 1
  @project_format_version 2
  @manifest_path "manifest.json"
  @project_path "project.json"
  @sha256_regex ~r/\A[0-9a-f]{64}\z/
  @logical_id_regex ~r/\Aasset-[0-9]{6}\z/
  @safe_profile_regex ~r/\A[a-z0-9][a-z0-9_-]{0,63}\z/
  @allowed_content_types Asset.allowed_content_types() ++ ["image/svg+xml"]
  @relationship_metadata_keys ~w(original_asset_id web_asset_id variant_asset_ids)
  @storage_metadata_keys ~w(
    blob_key key project_id storage_key thumbnail_key thumbnail_path url web_url
  )
  @unsafe_metadata_snake_key ~r/(?:\A|_)(?:id|ids|key|keys|path|paths|url|urls)\z/i
  @unsafe_metadata_camel_key ~r/(?:Id|Ids|Key|Keys|Path|Paths|Url|Urls)\z/
  @unsafe_metadata_acronym_key ~r/[a-z0-9](?:ID|IDs|URL|URLs)\z/
  @unsafe_project_storage_snake_key ~r/(?:\A|_)(?:blob|storage|thumbnail|presigned|signed|web|object|current_object)_(?:key|keys|path|paths|url|urls)\z/i
  @unsafe_project_storage_compound_key ~r/(?:blob|storage|thumbnail|presigned|signed|web|object|currentobject)(?:key|keys|path|paths|url|urls)\z/i
  @unsafe_project_url_snake_key ~r/(?:\A|_)(?:url|urls)\z/i
  @unsafe_project_url_camel_key ~r/(?:Url|Urls)\z/
  @unsafe_project_url_acronym_key ~r/[a-z0-9](?:URL|URLs)\z/
  @unsafe_project_ownership_key ~r/\Aproject_?(?:id|ids)\z/i
  @unsafe_project_generic_storage_key ~r/\A(?:key|keys|url|urls)\z/i

  @default_limits %{
    max_assets: 10_000,
    max_objects: 10_001,
    max_asset_bytes: 52_428_800,
    max_project_bytes: 128 * 1024 * 1024,
    max_manifest_bytes: 8 * 1024 * 1024,
    max_total_bytes: 500 * 1024 * 1024 * 1024,
    max_metadata_bytes: 64 * 1024,
    max_metadata_depth: 8
  }

  @type catalog_result :: %{
          assets: [map()],
          blobs: [map()],
          source_keys: %{String.t() => String.t()}
        }

  def format, do: @format
  def format_version, do: @format_version
  def manifest_path, do: @manifest_path
  def project_path, do: @project_path

  @doc false
  def hard_limits, do: @default_limits

  @doc """
  Removes current-storage durability fields from the project payload.

  Entity identifiers remain snapshot-local relationship labels and are remapped
  by recovery. Object keys, URLs, project ownership IDs, and thumbnail paths do
  not survive into the canonical payload.
  """
  @spec portable_project(map()) :: {:ok, map()} | {:error, term()}
  def portable_project(%{"format_version" => @project_format_version} = project) do
    project = scrub_storage_metadata(project)

    with :ok <- validate_json_value(project),
         :ok <- reject_storage_metadata(project) do
      {:ok, project}
    end
  end

  def portable_project(%{"format_version" => version}), do: {:error, {:unsupported_project_format, version}}

  def portable_project(_project), do: {:error, :invalid_project_object}

  @doc false
  @spec validate_project(term()) :: :ok | {:error, term()}
  def validate_project(%{"format_version" => @project_format_version} = project) do
    with :ok <- validate_json_value(project) do
      reject_storage_metadata(project)
    end
  end

  def validate_project(%{"format_version" => version}), do: {:error, {:unsupported_project_format, version}}

  def validate_project(_project), do: {:error, :invalid_project_object}

  @doc """
  Builds the logical catalog and unique blob inventory from active asset rows.

  Source storage keys are returned separately and never enter the manifest.
  """
  @spec build_catalog([Asset.t()], keyword()) :: {:ok, catalog_result()} | {:error, term()}
  def build_catalog(assets, opts \\ [])

  def build_catalog(assets, opts) when is_list(assets) do
    limits = limits(opts)

    with :ok <- validate_limits(limits),
         {:ok, project_id} <- validate_asset_collection(assets, opts),
         :ok <- validate_collection_limit(length(assets), limits.max_assets, :assets) do
      assets
      |> Enum.sort_by(&{&1.inserted_at, &1.id})
      |> logical_assets()
      |> build_catalog_entries(limits, project_id)
    end
  end

  def build_catalog(_assets, _opts), do: {:error, :invalid_asset_collection}

  @doc """
  Builds a manifest whose object inventory is independent from current storage.
  """
  @spec build_manifest(map(), [map()], [map()], keyword()) :: {:ok, map()} | {:error, term()}
  def build_manifest(project_object, assets, blobs, opts \\ []) do
    case Keyword.fetch(opts, :project_descriptor) do
      {:ok, project_descriptor} ->
        manifest = %{
          "format" => @format,
          "format_version" => @format_version,
          "project" => project_descriptor,
          "assets" => assets,
          "objects" => [project_descriptor | blobs],
          "counts" => %{
            "assets" => length(assets),
            "blobs" => length(blobs),
            "payload_objects" => length(blobs) + 1
          },
          "payload_size_bytes" => Enum.reduce([project_descriptor | blobs], 0, &(&1["size_bytes"] + &2))
        }

        with :ok <- validate_project_object(project_object),
             :ok <- validate_manifest(manifest, opts) do
          {:ok, manifest}
        end

      :error ->
        {:error, :missing_project_descriptor}
    end
  end

  @doc """
  Validates versions, paths, inventory, counts, sizes, MIME metadata, digests,
  configured limits, and unsafe metadata before an object reader trusts paths.
  """
  @spec validate_manifest(term(), keyword()) :: :ok | {:error, term()}
  def validate_manifest(manifest, opts \\ [])

  def validate_manifest(
        %{
          "format" => @format,
          "format_version" => @format_version,
          "project" => project,
          "assets" => assets,
          "objects" => objects,
          "counts" => counts,
          "payload_size_bytes" => payload_size_bytes
        },
        opts
      )
      when is_list(assets) and is_list(objects) and is_map(counts) do
    limits = limits(opts)

    with :ok <- validate_limits(limits),
         :ok <- validate_collection_limit(length(assets), limits.max_assets, :assets),
         :ok <- validate_collection_limit(length(objects), limits.max_objects, :objects),
         :ok <- validate_project_descriptor(project, limits),
         {:ok, inventory} <- validate_object_inventory(objects, limits),
         true <- inventory[@project_path] == project,
         :ok <- validate_assets(assets, inventory, limits),
         :ok <- validate_catalog_inventory(assets, inventory),
         :ok <- validate_counts(counts, assets, inventory) do
      validate_payload_size(payload_size_bytes, inventory, limits)
    else
      false -> {:error, :project_descriptor_inventory_mismatch}
      {:error, _reason} = error -> error
    end
  end

  def validate_manifest(%{"format" => @format, "format_version" => version}, _opts),
    do: {:error, {:unsupported_snapshot_object_format, version}}

  def validate_manifest(%{"format" => format}, _opts) when format != @format,
    do: {:error, {:unsupported_snapshot_object_type, format}}

  def validate_manifest(_manifest, _opts), do: {:error, :invalid_snapshot_manifest}

  @doc false
  def limits(opts \\ []) do
    configured = Application.get_env(:storyarn, __MODULE__, [])

    Map.new(@default_limits, fn {key, default} ->
      value = Keyword.get(opts, key, Keyword.get(configured, key, default))
      {key, value}
    end)
  end

  @doc false
  def blob_path(sha256, content_type) do
    extension = BlobStore.ext_from_content_type(content_type)
    "blobs/#{sha256}.#{extension}"
  end

  @doc false
  def safe_relative_path?(path) when is_binary(path) do
    path != "" and Storage.canonical_key?(path) and Path.type(path) == :relative
  end

  def safe_relative_path?(_path), do: false

  defp logical_assets(assets) do
    assets
    |> Enum.with_index(1)
    |> Enum.map(fn {asset, index} ->
      {asset, "asset-#{index |> Integer.to_string() |> String.pad_leading(6, "0")}"}
    end)
  end

  defp build_catalog_entries(logical_assets, limits, project_id) do
    logical_ids = Map.new(logical_assets, fn {%Asset{id: id}, logical_id} -> {to_string(id), logical_id} end)

    logical_assets
    |> Enum.reduce_while({:ok, [], %{}, %{}}, fn {asset, logical_id}, {:ok, entries, blobs, sources} ->
      with {:ok, entry, blob, source_key} <-
             catalog_entry(asset, logical_id, logical_ids, limits, project_id),
           {:ok, blobs} <- put_blob(blobs, blob),
           {:ok, sources} <- put_source(sources, blob["sha256"], source_key) do
        {:cont, {:ok, [entry | entries], blobs, sources}}
      else
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, entries, blobs, sources} ->
        {:ok,
         %{
           assets: Enum.reverse(entries),
           blobs: blobs |> Map.values() |> Enum.sort_by(& &1["path"]),
           source_keys: sources
         }}

      {:error, _reason} = error ->
        error
    end
  end

  defp catalog_entry(%Asset{} = asset, logical_id, logical_ids, limits, project_id) do
    metadata = asset.metadata || %{}

    with :ok <- validate_sha256(asset.blob_hash),
         :ok <- validate_filename(asset.filename),
         :ok <- validate_content_type(asset.content_type),
         :ok <- validate_size(asset.size, limits.max_asset_bytes, :asset),
         :ok <- validate_source_key(asset.key, project_id),
         {:ok, relationships} <- relationships(metadata, logical_ids),
         {:ok, intrinsic_metadata} <- intrinsic_metadata(metadata, limits) do
      path = blob_path(asset.blob_hash, asset.content_type)

      blob = %{
        "kind" => "asset_blob",
        "path" => path,
        "sha256" => asset.blob_hash,
        "size_bytes" => asset.size,
        "content_type" => asset.content_type
      }

      entry = %{
        "logical_id" => logical_id,
        "filename" => asset.filename,
        "content_type" => asset.content_type,
        "size_bytes" => asset.size,
        "sha256" => asset.blob_hash,
        "blob_path" => path,
        "metadata" => intrinsic_metadata,
        "relationships" => relationships
      }

      {:ok, entry, blob, asset.key}
    end
  end

  defp put_blob(blobs, %{"sha256" => hash} = blob) do
    case Map.fetch(blobs, hash) do
      :error -> {:ok, Map.put(blobs, hash, blob)}
      {:ok, ^blob} -> {:ok, blobs}
      {:ok, _conflict} -> {:error, {:conflicting_blob_metadata, hash}}
    end
  end

  defp put_source(sources, hash, source_key) do
    {:ok, Map.put_new(sources, hash, source_key)}
  end

  defp relationships(metadata, logical_ids) do
    with {:ok, original} <- logical_relationship(metadata["original_asset_id"], logical_ids),
         {:ok, web} <- logical_relationship(metadata["web_asset_id"], logical_ids),
         {:ok, variants} <- logical_variants(metadata["variant_asset_ids"], logical_ids) do
      {:ok, %{"original" => original, "web" => web, "variants" => variants}}
    end
  end

  defp logical_relationship(nil, _logical_ids), do: {:ok, nil}

  defp logical_relationship(value, logical_ids) when is_integer(value) or is_binary(value) do
    case Map.fetch(logical_ids, to_string(value)) do
      {:ok, logical_id} -> {:ok, logical_id}
      :error -> {:error, {:dangling_asset_relationship, value}}
    end
  end

  defp logical_relationship(value, _logical_ids), do: {:error, {:invalid_asset_relationship, value}}

  defp logical_variants(nil, _logical_ids), do: {:ok, %{}}

  defp logical_variants(variants, logical_ids) when is_map(variants) do
    Enum.reduce_while(variants, {:ok, %{}}, fn {profile, target}, {:ok, acc} ->
      with true <- is_binary(profile) and Regex.match?(@safe_profile_regex, profile),
           {:ok, logical_id} <- logical_relationship(target, logical_ids) do
        {:cont, {:ok, Map.put(acc, profile, logical_id)}}
      else
        false -> {:halt, {:error, {:unsafe_variant_profile, profile}}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp logical_variants(value, _logical_ids), do: {:error, {:invalid_variant_relationships, value}}

  defp intrinsic_metadata(metadata, limits) when is_map(metadata) do
    intrinsic = Map.drop(metadata, @relationship_metadata_keys ++ @storage_metadata_keys)

    with :ok <- validate_json_value(intrinsic),
         :ok <- validate_metadata_keys(intrinsic, limits.max_metadata_depth),
         {:ok, encoded} <- Jason.encode(intrinsic),
         :ok <- validate_size(byte_size(encoded), limits.max_metadata_bytes, :metadata) do
      {:ok, intrinsic}
    else
      {:error, %Jason.EncodeError{}} -> {:error, :invalid_asset_metadata}
      {:error, _reason} = error -> error
    end
  end

  defp intrinsic_metadata(_metadata, _limits), do: {:error, :invalid_asset_metadata}

  defp validate_assets(assets, inventory, limits) do
    assets
    |> Enum.reduce_while({:ok, MapSet.new()}, fn asset, {:ok, logical_ids} ->
      with :ok <- validate_asset_entry(asset, inventory, limits),
           false <- MapSet.member?(logical_ids, asset["logical_id"]) do
        {:cont, {:ok, MapSet.put(logical_ids, asset["logical_id"])}}
      else
        true -> {:halt, {:error, {:duplicate_asset_logical_id, asset["logical_id"]}}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, logical_ids} -> validate_catalog_relationships(assets, logical_ids)
      {:error, _reason} = error -> error
    end
  end

  defp validate_asset_entry(
         %{
           "logical_id" => logical_id,
           "filename" => filename,
           "content_type" => content_type,
           "size_bytes" => size,
           "sha256" => sha256,
           "blob_path" => blob_path,
           "metadata" => metadata,
           "relationships" => relationships
         },
         inventory,
         limits
       )
       when is_map(metadata) and is_map(relationships) do
    with true <- is_binary(logical_id) and Regex.match?(@logical_id_regex, logical_id),
         :ok <- validate_filename(filename),
         :ok <- validate_content_type(content_type),
         :ok <- validate_size(size, limits.max_asset_bytes, :asset),
         :ok <- validate_sha256(sha256),
         true <- blob_path == blob_path(sha256, content_type),
         %{"kind" => "asset_blob"} = object <- inventory[blob_path],
         true <- descriptor_matches_asset?(object, content_type, size, sha256),
         :ok <- validate_metadata_keys(metadata, limits.max_metadata_depth),
         {:ok, encoded} <- Jason.encode(metadata),
         :ok <- validate_size(byte_size(encoded), limits.max_metadata_bytes, :metadata),
         :ok <- validate_relationship_shape(relationships) do
      :ok
    else
      false -> {:error, {:invalid_asset_catalog_entry, logical_id}}
      nil -> {:error, {:missing_asset_blob_object, blob_path}}
      {:error, %Jason.EncodeError{}} -> {:error, :invalid_asset_metadata}
      {:error, _reason} = error -> error
      _object -> {:error, {:invalid_asset_blob_object, blob_path}}
    end
  end

  defp validate_asset_entry(_asset, _inventory, _limits), do: {:error, :invalid_asset_catalog_entry}

  defp descriptor_matches_asset?(object, content_type, size, sha256) do
    object["content_type"] == content_type and object["size_bytes"] == size and object["sha256"] == sha256
  end

  defp validate_relationship_shape(%{"original" => original, "web" => web, "variants" => variants})
       when is_map(variants) do
    if valid_optional_logical_id?(original) and valid_optional_logical_id?(web) and
         Enum.all?(variants, fn {profile, id} ->
           is_binary(profile) and Regex.match?(@safe_profile_regex, profile) and valid_logical_id?(id)
         end) do
      :ok
    else
      {:error, :invalid_asset_relationships}
    end
  end

  defp validate_relationship_shape(_relationships), do: {:error, :invalid_asset_relationships}

  defp validate_catalog_relationships(assets, logical_ids) do
    Enum.reduce_while(assets, :ok, fn asset, :ok ->
      relationships = asset["relationships"]
      targets = [relationships["original"], relationships["web"]] ++ Map.values(relationships["variants"])

      case Enum.find(targets, &(&1 && not MapSet.member?(logical_ids, &1))) do
        nil -> {:cont, :ok}
        target -> {:halt, {:error, {:dangling_asset_relationship, target}}}
      end
    end)
  end

  defp validate_catalog_inventory(assets, inventory) do
    catalog_paths = MapSet.new(assets, & &1["blob_path"])

    inventory_paths =
      inventory
      |> Enum.filter(fn {_path, object} -> object["kind"] == "asset_blob" end)
      |> MapSet.new(fn {path, _object} -> path end)

    if MapSet.equal?(catalog_paths, inventory_paths),
      do: :ok,
      else: {:error, :asset_blob_inventory_mismatch}
  end

  defp validate_object_inventory(objects, limits) do
    Enum.reduce_while(objects, {:ok, %{}}, fn object, {:ok, inventory} ->
      with :ok <- validate_object_descriptor(object, limits),
           false <- Map.has_key?(inventory, object["path"]) do
        {:cont, {:ok, Map.put(inventory, object["path"], object)}}
      else
        true -> {:halt, {:error, {:duplicate_object_path, object["path"]}}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp validate_object_descriptor(
         %{"kind" => kind, "path" => path, "sha256" => sha256, "size_bytes" => size, "content_type" => content_type},
         limits
       )
       when kind in ["project", "asset_blob"] do
    max_size = if kind == "project", do: limits.max_project_bytes, else: limits.max_asset_bytes

    with true <- safe_relative_path?(path),
         true <- path != @manifest_path,
         :ok <- validate_sha256(sha256),
         :ok <- validate_size(size, max_size, kind),
         :ok <- validate_content_type_for_kind(content_type, kind),
         :ok <- validate_descriptor_path(path, kind, sha256, content_type) do
      :ok
    else
      false -> {:error, {:unsafe_snapshot_object_path, path}}
      {:error, _reason} = error -> error
    end
  end

  defp validate_object_descriptor(_object, _limits), do: {:error, :invalid_snapshot_object_descriptor}

  defp validate_descriptor_path(@project_path, "project", _sha256, "application/json"), do: :ok

  defp validate_descriptor_path(path, "asset_blob", sha256, content_type) do
    if path == blob_path(sha256, content_type),
      do: :ok,
      else: {:error, {:invalid_blob_path, path}}
  end

  defp validate_descriptor_path(path, _kind, _sha256, _content_type), do: {:error, {:invalid_snapshot_object_path, path}}

  defp validate_project_descriptor(%{"kind" => "project", "path" => @project_path} = project, limits) do
    validate_object_descriptor(project, limits)
  end

  defp validate_project_descriptor(_project, _limits), do: {:error, :invalid_project_descriptor}

  defp validate_counts(counts, assets, inventory) do
    blob_count = Enum.count(inventory, fn {_path, object} -> object["kind"] == "asset_blob" end)
    project_count = Enum.count(inventory, fn {_path, object} -> object["kind"] == "project" end)

    expected = %{
      "assets" => length(assets),
      "blobs" => blob_count,
      "payload_objects" => map_size(inventory)
    }

    if counts == expected and project_count == 1,
      do: :ok,
      else: {:error, {:snapshot_object_count_mismatch, expected, counts}}
  end

  defp validate_payload_size(payload_size_bytes, inventory, limits) do
    actual = Enum.reduce(inventory, 0, fn {_path, object}, acc -> acc + object["size_bytes"] end)

    cond do
      payload_size_bytes != actual -> {:error, {:snapshot_payload_size_mismatch, actual, payload_size_bytes}}
      actual > limits.max_total_bytes -> {:error, {:snapshot_size_limit_exceeded, limits.max_total_bytes}}
      true -> :ok
    end
  end

  defp validate_project_object(%{"format_version" => @project_format_version}), do: :ok
  defp validate_project_object(_project), do: {:error, :invalid_project_object}

  defp validate_filename(filename) when is_binary(filename) do
    if filename != "" and byte_size(filename) <= 255 and String.valid?(filename) and
         not String.contains?(filename, [<<0>>, "/", "\\"]),
       do: :ok,
       else: {:error, {:unsafe_asset_filename, filename}}
  end

  defp validate_filename(filename), do: {:error, {:unsafe_asset_filename, filename}}

  defp validate_content_type(content_type) when content_type in @allowed_content_types, do: :ok
  defp validate_content_type(content_type), do: {:error, {:unsafe_asset_content_type, content_type}}

  defp validate_content_type_for_kind("application/json", "project"), do: :ok
  defp validate_content_type_for_kind(content_type, "asset_blob"), do: validate_content_type(content_type)

  defp validate_content_type_for_kind(content_type, kind),
    do: {:error, {:invalid_snapshot_object_content_type, kind, content_type}}

  defp validate_sha256(sha256) when is_binary(sha256) do
    if Regex.match?(@sha256_regex, sha256), do: :ok, else: {:error, {:invalid_sha256, sha256}}
  end

  defp validate_sha256(sha256), do: {:error, {:invalid_sha256, sha256}}

  defp validate_asset_collection([], opts) do
    case Keyword.get(opts, :project_id) do
      nil -> {:ok, nil}
      project_id when is_integer(project_id) and project_id > 0 -> {:ok, project_id}
      _invalid -> {:error, :invalid_asset_project_id}
    end
  end

  defp validate_asset_collection(assets, opts) do
    with true <- Enum.all?(assets, &match?(%Asset{}, &1)),
         :ok <- validate_asset_ids(assets) do
      expected_project_id = Keyword.get(opts, :project_id, hd(assets).project_id)

      cond do
        not (is_integer(expected_project_id) and expected_project_id > 0) ->
          {:error, :invalid_asset_project_id}

        Enum.all?(assets, &(&1.project_id == expected_project_id)) ->
          {:ok, expected_project_id}

        true ->
          actual_project_ids = assets |> Enum.map(& &1.project_id) |> Enum.uniq() |> Enum.sort()
          {:error, {:asset_project_mismatch, expected_project_id, actual_project_ids}}
      end
    else
      false -> {:error, :invalid_asset_collection}
      {:error, _reason} = error -> error
    end
  end

  defp validate_asset_ids(assets) do
    ids = Enum.map(assets, & &1.id)
    invalid_ids = Enum.reject(ids, &(is_integer(&1) and &1 > 0))

    duplicates =
      ids
      |> Enum.frequencies()
      |> Enum.filter(fn {_id, count} -> count > 1 end)
      |> Enum.map(fn {id, _count} -> id end)
      |> Enum.sort()

    cond do
      invalid_ids != [] -> {:error, {:invalid_asset_ids, invalid_ids}}
      duplicates != [] -> {:error, {:duplicate_asset_ids, duplicates}}
      true -> :ok
    end
  end

  defp validate_source_key(key, project_id) when is_binary(key) and is_integer(project_id) do
    expected_project_id = Integer.to_string(project_id)

    case String.split(key, "/", trim: false) do
      ["projects", ^expected_project_id, "assets", asset_uuid, filename] ->
        if Storage.canonical_key?(key) and match?({:ok, _uuid}, Ecto.UUID.cast(asset_uuid)) and
             filename not in ["", ".", "..", ".storyarn-copy"],
           do: :ok,
           else: {:error, {:invalid_asset_source_key, key}}

      _other ->
        {:error, {:asset_source_project_mismatch, project_id, key}}
    end
  end

  defp validate_source_key(key, _project_id), do: {:error, {:invalid_asset_source_key, key}}

  defp validate_size(size, max_size, label) when is_integer(size) and size >= 0 do
    cond do
      size == 0 and label in [:asset, "asset_blob"] -> {:error, {:invalid_size, label, size}}
      size <= max_size -> :ok
      true -> {:error, {:size_limit_exceeded, label, max_size}}
    end
  end

  defp validate_size(size, _max_size, label), do: {:error, {:invalid_size, label, size}}

  defp validate_collection_limit(count, limit, label) when is_integer(limit) and limit >= 0 do
    if count <= limit, do: :ok, else: {:error, {:collection_limit_exceeded, label, limit}}
  end

  defp validate_collection_limit(_count, limit, label), do: {:error, {:invalid_collection_limit, label, limit}}

  defp validate_metadata_keys(value, max_depth), do: validate_metadata_keys(value, 0, max_depth)

  defp validate_metadata_keys(_value, depth, max_depth) when depth > max_depth,
    do: {:error, {:asset_metadata_depth_limit_exceeded, max_depth}}

  defp validate_metadata_keys(value, depth, max_depth) when is_map(value) do
    Enum.reduce_while(value, :ok, fn {key, nested}, :ok ->
      cond do
        not is_binary(key) -> {:halt, {:error, :invalid_asset_metadata_key}}
        not String.valid?(key) -> {:halt, {:error, :invalid_asset_metadata_key}}
        unsafe_asset_metadata_key?(key) -> {:halt, {:error, {:unsafe_asset_metadata_key, key}}}
        true -> continue_metadata_validation(nested, depth + 1, max_depth)
      end
    end)
  end

  defp validate_metadata_keys(value, depth, max_depth) when is_list(value) do
    Enum.reduce_while(value, :ok, fn nested, :ok ->
      continue_metadata_validation(nested, depth + 1, max_depth)
    end)
  end

  defp validate_metadata_keys(_value, _depth, _max_depth), do: :ok

  defp continue_metadata_validation(nested, depth, max_depth) do
    case validate_metadata_keys(nested, depth, max_depth) do
      :ok -> {:cont, :ok}
      {:error, _reason} = error -> {:halt, error}
    end
  end

  @doc false
  def validate_limits(limits) when is_map(limits) do
    if limits |> Map.keys() |> Enum.sort() == @default_limits |> Map.keys() |> Enum.sort() do
      invalid =
        Enum.find(limits, fn
          {key, value} when key in [:max_assets, :max_objects] ->
            not (is_integer(value) and value >= 0 and value <= Map.fetch!(@default_limits, key))

          {key, value} ->
            not (is_integer(value) and value > 0 and value <= Map.fetch!(@default_limits, key))
        end)

      case invalid do
        nil -> :ok
        {key, value} -> {:error, {:invalid_snapshot_object_limit, key, value}}
      end
    else
      {:error, :invalid_snapshot_object_limit_keys}
    end
  end

  def validate_limits(limits), do: {:error, {:invalid_snapshot_object_limits, limits}}

  defp validate_json_value(value) do
    case Jason.encode(value) do
      {:ok, _json} -> :ok
      {:error, _reason} -> {:error, :invalid_json_value}
    end
  end

  defp scrub_storage_metadata(%_struct{} = value), do: value

  defp scrub_storage_metadata(value) when is_map(value) do
    value
    |> Enum.reject(fn {key, _nested} -> storage_metadata_key?(key) end)
    |> Map.new(fn {key, nested} -> {key, scrub_storage_metadata(nested)} end)
  end

  defp scrub_storage_metadata(value) when is_list(value), do: Enum.map(value, &scrub_storage_metadata/1)
  defp scrub_storage_metadata(value), do: value

  defp reject_storage_metadata(%_struct{}), do: {:error, :invalid_project_object}

  defp reject_storage_metadata(value) when is_map(value) do
    Enum.reduce_while(value, :ok, fn {key, nested}, :ok ->
      if storage_metadata_key?(key) do
        {:halt, {:error, {:unsafe_project_metadata_key, key}}}
      else
        continue_project_metadata_validation(nested)
      end
    end)
  end

  defp reject_storage_metadata(value) when is_list(value) do
    Enum.reduce_while(value, :ok, fn nested, :ok -> continue_project_metadata_validation(nested) end)
  end

  defp reject_storage_metadata(_value), do: :ok

  defp continue_project_metadata_validation(nested) do
    case reject_storage_metadata(nested) do
      :ok -> {:cont, :ok}
      {:error, _reason} = error -> {:halt, error}
    end
  end

  defp unsafe_asset_metadata_key?(key) do
    key in @storage_metadata_keys or
      Regex.match?(@unsafe_metadata_snake_key, key) or
      Regex.match?(@unsafe_metadata_camel_key, key) or
      Regex.match?(@unsafe_metadata_acronym_key, key)
  end

  defp storage_metadata_key?(key) when is_binary(key) do
    key in @storage_metadata_keys or
      (String.valid?(key) and
         (Regex.match?(@unsafe_project_storage_snake_key, key) or
            Regex.match?(@unsafe_project_storage_compound_key, key) or
            Regex.match?(@unsafe_project_url_snake_key, key) or
            Regex.match?(@unsafe_project_url_camel_key, key) or
            Regex.match?(@unsafe_project_url_acronym_key, key) or
            Regex.match?(@unsafe_project_ownership_key, key) or
            Regex.match?(@unsafe_project_generic_storage_key, key)))
  end

  defp storage_metadata_key?(key) when is_atom(key), do: key |> Atom.to_string() |> storage_metadata_key?()
  defp storage_metadata_key?(_key), do: false

  defp valid_optional_logical_id?(nil), do: true
  defp valid_optional_logical_id?(id), do: valid_logical_id?(id)

  defp valid_logical_id?(id) when is_binary(id), do: Regex.match?(@logical_id_regex, id)
  defp valid_logical_id?(_id), do: false
end

defmodule Storyarn.Versioning.SnapshotAssetCapture do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Assets.Asset
  alias Storyarn.Assets.BlobStore
  alias Storyarn.Assets.Storage
  alias Storyarn.Repo

  @sha256_regex ~r/\A[0-9a-f]{64}\z/
  @safe_extension_regex ~r/\A[a-z0-9][a-z0-9-]{0,31}\z/
  @max_asset_size 52_428_800
  @generic_content_type "application/octet-stream"
  @capture_content_types Asset.allowed_content_types() ++ ["image/svg+xml", @generic_content_type]

  @type materialized_inventory :: %{
          raw_assets: [Asset.t()],
          effective_assets: [Asset.t()],
          invalid_asset_ids: [pos_integer()]
        }

  @spec materialize([Asset.t()], pos_integer()) :: {:ok, materialized_inventory()} | {:error, term()}
  def materialize(assets, project_id) when is_list(assets) and is_integer(project_id) and project_id > 0 do
    with :ok <- validate_inventory(assets, project_id),
         {:ok, effective_assets, invalid_asset_ids} <- materialize_assets(assets) do
      {:ok,
       %{
         raw_assets: assets,
         effective_assets: effective_assets,
         invalid_asset_ids: invalid_asset_ids
       }}
    end
  end

  def materialize(_assets, _project_id), do: {:error, :invalid_snapshot_asset_inventory}

  @spec rematerialize(materialized_inventory()) :: :ok | {:error, term()}
  def rematerialize(%{raw_assets: raw_assets, effective_assets: effective_assets})
      when is_list(raw_assets) and is_list(effective_assets) and length(raw_assets) == length(effective_assets) do
    raw_assets
    |> Enum.zip(effective_assets)
    |> Enum.reduce_while(:ok, fn {raw_asset, expected_asset}, :ok ->
      case materialize_asset(raw_asset, expected_identity(expected_asset)) do
        {:ok, _effective_asset, _invalid?} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  def rematerialize(_inventory), do: {:error, :invalid_snapshot_asset_inventory}

  @spec ensure_blob_specs(pos_integer(), [map()]) :: {:ok, map()} | {:error, term()}
  def ensure_blob_specs(project_id, specs) when is_integer(project_id) and project_id > 0 and is_list(specs) do
    initial = %{asset_count: 0, blob_count: length(specs), repaired_blob_count: 0}

    Enum.reduce_while(specs, {:ok, initial}, fn spec, {:ok, summary} ->
      case ensure_blob_spec(project_id, spec) do
        {:ok, asset_count, repaired?} ->
          updated = %{
            summary
            | asset_count: summary.asset_count + asset_count,
              repaired_blob_count: summary.repaired_blob_count + if(repaired?, do: 1, else: 0)
          }

          {:cont, {:ok, updated}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  def ensure_blob_specs(_project_id, _specs), do: {:error, :invalid_snapshot_asset_blob_inventory}

  defp validate_inventory(assets, project_id) do
    ids = Enum.map(assets, & &1.id)

    if Enum.all?(assets, &match?(%Asset{project_id: ^project_id, id: id} when is_integer(id) and id > 0, &1)) and
         length(ids) == length(Enum.uniq(ids)) do
      :ok
    else
      {:error, :invalid_snapshot_asset_inventory}
    end
  end

  defp materialize_assets(assets) do
    case Enum.reduce_while(assets, {:ok, [], []}, &materialize_inventory_asset/2) do
      {:ok, effective_assets, invalid_ids} ->
        effective_assets
        |> Enum.reverse()
        |> normalize_shared_blob_identities(Enum.reverse(invalid_ids))

      {:error, _reason} = error ->
        error
    end
  end

  defp materialize_inventory_asset(asset, {:ok, effective_assets, invalid_ids}) do
    case materialize_asset(asset, nil) do
      {:ok, effective_asset, invalid?} ->
        invalid_ids = if invalid?, do: [asset.id | invalid_ids], else: invalid_ids
        {:cont, {:ok, [effective_asset | effective_assets], invalid_ids}}

      {:error, reason} ->
        {:halt, {:error, reason}}
    end
  end

  defp materialize_asset(%Asset{} = asset, nil) do
    case materialize_asset_from_active_sources(asset) do
      {:ok, effective_asset} ->
        {:ok, effective_asset, not raw_identity_matches?(asset, effective_asset)}

      {:error, _reason} ->
        materialize_asset_without_active_source(asset)
    end
  end

  defp materialize_asset(%Asset{} = asset, expected) when is_map(expected) do
    materialize_asset_from_candidates(asset, expected)
  end

  defp materialize_asset_from_active_sources(%Asset{} = asset) do
    materialize_asset_from_source_keys(asset, nil, active_source_candidates(asset), false)
  end

  defp materialize_asset_without_active_source(%Asset{} = asset) do
    case BlobStore.ensure_asset_blob(asset) do
      {:ok, canonical_key, _status} ->
        effective_asset = %{asset | key: canonical_key}
        {:ok, effective_asset, not raw_identity_matches?(asset, effective_asset)}

      {:error, _reason} ->
        materialize_asset_from_candidates(asset, nil)
    end
  end

  defp materialize_asset_from_candidates(%Asset{} = asset, expected) do
    asset
    |> source_candidates(expected)
    |> then(&materialize_asset_from_source_keys(asset, expected, &1, true))
    |> case do
      {:ok, effective_asset} -> {:ok, effective_asset, true}
      {:error, errors} -> {:error, classify_source_errors(errors)}
    end
  end

  defp materialize_asset_from_source_keys(%Asset{} = asset, expected, source_keys, validate_canonical_hash?) do
    Enum.reduce_while(source_keys, {:error, []}, fn source_key, {:error, errors} ->
      case effective_asset_from_source(asset, source_key, expected, validate_canonical_hash?) do
        {:ok, effective_asset} -> {:halt, {:ok, effective_asset}}
        {:error, reason} -> {:cont, {:error, [reason | errors]}}
      end
    end)
  end

  defp classify_source_errors(errors) when is_list(errors) and errors != [] do
    cond do
      Enum.all?(errors, &missing_source_error?/1) ->
        :missing_snapshot_blob_source

      Enum.all?(errors, &(missing_source_error?(&1) or corrupt_source_error?(&1))) and
          Enum.any?(errors, &corrupt_source_error?/1) ->
        :snapshot_object_checksum_mismatch

      true ->
        :snapshot_asset_bytes_unavailable
    end
  end

  defp classify_source_errors(_errors), do: :snapshot_asset_bytes_unavailable

  defp missing_source_error?(:enoent), do: true
  defp missing_source_error?(:missing_snapshot_blob_source), do: true
  defp missing_source_error?({:http_error, 404, _response}), do: true
  defp missing_source_error?(_reason), do: false

  defp corrupt_source_error?(reason)
       when reason in [
              :blob_hash_mismatch,
              :snapshot_object_checksum_mismatch,
              :snapshot_asset_canonical_hash_mismatch,
              :snapshot_asset_canonical_key_invalid,
              :snapshot_asset_identity_changed,
              :snapshot_asset_source_changed
            ], do: true

  defp corrupt_source_error?(_reason), do: false

  defp source_candidates(%Asset{} = asset, expected) do
    expected_keys =
      case expected do
        %{blob_hash: hash, content_type: content_type} ->
          [canonical_blob_key(asset.project_id, hash, content_type)]

        nil ->
          canonical_candidates(asset)
      end

    (expected_keys ++ canonical_candidates(asset) ++ active_source_candidates(asset))
    |> Enum.filter(&project_owned_key?(&1, asset.project_id))
    |> Enum.uniq()
  end

  defp active_source_candidates(%Asset{} = asset) do
    [asset.key, asset_url_key(asset)]
    |> Enum.filter(&project_owned_key?(&1, asset.project_id))
    |> Enum.uniq()
  end

  defp asset_url_key(%Asset{url: url}) when is_binary(url) do
    case Storage.key_from_url(url) do
      {:ok, key} -> key
      {:error, _reason} -> nil
    end
  end

  defp asset_url_key(%Asset{}), do: nil

  defp canonical_candidates(%Asset{blob_hash: hash} = asset) when is_binary(hash) do
    if Regex.match?(@sha256_regex, hash) do
      preferred =
        if capture_content_type?(asset.content_type, asset.metadata),
          do: [asset.content_type],
          else: []

      legacy = if legacy_content_type_candidate?(asset.content_type), do: [asset.content_type], else: []

      (preferred ++ legacy ++ @capture_content_types)
      |> Enum.uniq()
      |> Enum.map(&canonical_blob_key(asset.project_id, hash, &1))
    else
      []
    end
  end

  defp canonical_candidates(%Asset{}), do: []

  defp effective_asset_from_source(%Asset{} = asset, source_key, expected, validate_canonical_hash?) do
    with {:ok, stat} <- Storage.stat(source_key),
         {:ok, size} <- bounded_source_size(stat),
         {:ok, bytes} <- Storage.download(source_key),
         true <- byte_size(bytes) == size,
         hash = BlobStore.compute_hash(bytes),
         :ok <- validate_canonical_source_hash(source_key, asset.project_id, hash, validate_canonical_hash?),
         {:ok, content_type} <- effective_content_type(asset, stat, source_key, expected),
         :ok <- validate_expected_identity(expected, hash, size, content_type),
         extension = BlobStore.ext_from_content_type(content_type),
         {:ok, canonical_key, _created?} <-
           BlobStore.ensure_blob_with_status(asset.project_id, hash, extension, bytes, content_type) do
      {:ok,
       %{
         asset
         | blob_hash: hash,
           size: size,
           content_type: content_type,
           key: canonical_key
       }}
    else
      false -> {:error, :snapshot_asset_source_changed}
      {:error, _reason} = error -> error
    end
  end

  defp bounded_source_size(%{size: size}) when is_integer(size) and size >= 0 and size <= @max_asset_size, do: {:ok, size}

  defp bounded_source_size(_stat), do: {:error, :snapshot_asset_source_size_invalid}

  defp effective_content_type(_asset, _stat, _source_key, %{content_type: content_type}) do
    if content_type in @capture_content_types,
      do: {:ok, content_type},
      else: {:error, :snapshot_asset_content_type_invalid}
  end

  defp effective_content_type(asset, stat, source_key, nil) do
    provider_content_type = Map.get(stat, :content_type)
    path_content_type = MIME.from_path(source_key)

    content_type =
      cond do
        capture_content_type?(asset.content_type, asset.metadata) and
            provider_compatible?(provider_content_type, asset.content_type) ->
          asset.content_type

        capture_content_type?(provider_content_type, asset.metadata) ->
          provider_content_type

        capture_content_type?(path_content_type, asset.metadata) ->
          path_content_type

        true ->
          @generic_content_type
      end

    {:ok, content_type}
  end

  defp provider_compatible?(nil, _expected), do: true
  defp provider_compatible?("", _expected), do: true

  defp provider_compatible?(actual, expected), do: BlobStore.compatible_content_type?(actual, expected)

  defp capture_content_type?("image/svg+xml", %{"sanitized_svg" => true}), do: true
  defp capture_content_type?("image/svg+xml", _metadata), do: false
  defp capture_content_type?(content_type, _metadata), do: content_type in Asset.allowed_content_types()

  defp legacy_content_type_candidate?(content_type) when is_binary(content_type) do
    extension = BlobStore.ext_from_content_type(content_type)
    is_binary(extension) and Regex.match?(@safe_extension_regex, extension)
  rescue
    _exception -> false
  end

  defp legacy_content_type_candidate?(_content_type), do: false

  defp raw_identity_materializable?(%Asset{} = asset) do
    is_binary(asset.blob_hash) and Regex.match?(@sha256_regex, asset.blob_hash) and
      is_integer(asset.size) and asset.size > 0 and asset.size <= @max_asset_size and
      capture_content_type?(asset.content_type, asset.metadata) and
      canonical_asset_source_key?(asset.key, asset.project_id)
  end

  defp raw_identity_matches?(%Asset{} = raw_asset, %Asset{} = effective_asset) do
    raw_identity_materializable?(raw_asset) and raw_asset.blob_hash == effective_asset.blob_hash and
      raw_asset.size == effective_asset.size and raw_asset.content_type == effective_asset.content_type
  end

  defp canonical_asset_source_key?(key, project_id) when is_binary(key) do
    expected_project_id = Integer.to_string(project_id)

    case String.split(key, "/", trim: false) do
      ["projects", ^expected_project_id, "assets", asset_uuid, filename] ->
        Storage.canonical_key?(key) and match?({:ok, _uuid}, Ecto.UUID.cast(asset_uuid)) and
          filename not in ["", ".", "..", ".storyarn-copy"]

      _other ->
        false
    end
  end

  defp canonical_asset_source_key?(_key, _project_id), do: false

  defp project_owned_key?(key, project_id) when is_binary(key) do
    Storage.canonical_key?(key) and String.starts_with?(key, "projects/#{project_id}/")
  end

  defp project_owned_key?(_key, _project_id), do: false

  defp validate_canonical_source_hash(_source_key, _project_id, _actual_hash, false), do: :ok

  defp validate_canonical_source_hash(source_key, project_id, actual_hash, true) do
    prefix = "projects/#{project_id}/blobs/"

    if String.starts_with?(source_key, prefix) do
      filename = String.replace_prefix(source_key, prefix, "")

      case String.split(filename, ".", parts: 2) do
        [hash, _extension] when hash == actual_hash -> :ok
        [_hash, _extension] -> {:error, :snapshot_asset_canonical_hash_mismatch}
        _invalid -> {:error, :snapshot_asset_canonical_key_invalid}
      end
    else
      :ok
    end
  end

  defp validate_expected_identity(nil, _hash, _size, _content_type), do: :ok

  defp validate_expected_identity(%{blob_hash: hash, size: size, content_type: content_type}, hash, size, content_type),
    do: :ok

  defp validate_expected_identity(_expected, _hash, _size, _content_type), do: {:error, :snapshot_asset_identity_changed}

  defp expected_identity(%Asset{} = asset) do
    %{blob_hash: asset.blob_hash, size: asset.size, content_type: asset.content_type}
  end

  defp normalize_shared_blob_identities(effective_assets, invalid_ids) do
    content_type_by_hash =
      effective_assets
      |> Enum.group_by(& &1.blob_hash, & &1.content_type)
      |> Map.new(fn {hash, content_types} -> {hash, Enum.min(content_types)} end)

    {normalized_assets, invalid_ids} =
      Enum.map_reduce(effective_assets, invalid_ids, fn asset, invalid_ids ->
        content_type = Map.fetch!(content_type_by_hash, asset.blob_hash)

        if asset.content_type == content_type do
          {asset, invalid_ids}
        else
          canonical_key = canonical_blob_key(asset.project_id, asset.blob_hash, content_type)
          {%{asset | content_type: content_type, key: canonical_key}, [asset.id | invalid_ids]}
        end
      end)

    {:ok, normalized_assets, invalid_ids |> Enum.uniq() |> Enum.sort()}
  end

  defp ensure_blob_spec(project_id, %{blob_hash: blob_hash, size: size, content_type: content_type, asset_ids: asset_ids})
       when is_binary(blob_hash) and is_integer(size) and size >= 0 and is_binary(content_type) do
    ensure_blob_spec_assets(project_id, blob_hash, size, content_type, asset_ids)
  end

  defp ensure_blob_spec(_project_id, _spec), do: {:error, :invalid_snapshot_asset_blob_inventory}

  defp ensure_blob_spec_assets(project_id, blob_hash, size, content_type, asset_ids)
       when is_list(asset_ids) and asset_ids != [] do
    expected = %{blob_hash: blob_hash, size: size, content_type: content_type}
    canonical_key = canonical_blob_key(project_id, blob_hash, content_type)

    case verify_source_identity(canonical_key, project_id, expected) do
      :ok ->
        {:ok, length(asset_ids), false}

      {:error, reason} ->
        project_id
        |> snapshot_assets(asset_ids)
        |> repair_blob_spec(expected, length(asset_ids), classify_source_errors([reason]))
    end
  end

  defp ensure_blob_spec_assets(_project_id, _blob_hash, _size, _content_type, _asset_ids),
    do: {:error, :invalid_snapshot_asset_blob_inventory}

  defp snapshot_assets(project_id, asset_ids) do
    Repo.all(
      from(asset in Asset,
        where: asset.project_id == ^project_id and asset.id in ^asset_ids,
        order_by: [asc: asset.id]
      )
    )
  end

  defp repair_blob_spec(assets, expected, asset_count, initial_reason) do
    assets
    |> Enum.reduce_while({:error, [initial_reason]}, fn asset, {:error, reasons} ->
      case materialize_asset(asset, expected) do
        {:ok, _effective_asset, _invalid?} -> {:halt, {:ok, asset_count, true}}
        {:error, reason} -> {:cont, {:error, [reason | reasons]}}
      end
    end)
    |> case do
      {:ok, _asset_count, _repaired?} = success ->
        success

      {:error, reasons} ->
        {:error, classify_blob_repair_errors(expected.blob_hash, reasons)}
    end
  end

  defp classify_blob_repair_errors(blob_hash, reasons) do
    case classify_source_errors(reasons) do
      :missing_snapshot_blob_source -> {:missing_snapshot_blob_source, blob_hash}
      :snapshot_object_checksum_mismatch -> {:snapshot_object_checksum_mismatch, blob_hash}
      :snapshot_asset_bytes_unavailable -> :snapshot_asset_blob_unavailable
    end
  end

  defp verify_source_identity(source_key, project_id, expected) do
    with {:ok, stat} <- Storage.stat(source_key),
         {:ok, size} <- bounded_source_size(stat),
         true <- size == expected.size,
         {:ok, bytes} <- Storage.download(source_key),
         true <- byte_size(bytes) == size,
         hash = BlobStore.compute_hash(bytes),
         true <- hash == expected.blob_hash,
         :ok <- validate_canonical_source_hash(source_key, project_id, hash, true) do
      :ok
    else
      false -> {:error, :snapshot_asset_identity_changed}
      {:error, _reason} = error -> error
    end
  end

  defp canonical_blob_key(project_id, hash, content_type) do
    BlobStore.blob_key(project_id, hash, BlobStore.ext_from_content_type(content_type))
  end
end

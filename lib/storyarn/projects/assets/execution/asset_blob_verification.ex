defmodule Storyarn.Projects.Assets.AssetBlobVerification do
  @moduledoc """
  Verifies and repairs the canonical blobs that make Project assets durable.

  Blob verification owns no transaction or SQL write. Provider verification,
  key locking and repair remain inside `Storyarn.Projects.Assets.BlobStore`.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Projects.Assets.Asset
  alias Storyarn.Projects.Assets.BlobStore
  alias Storyarn.Projects.Assets.Queries.AssetQueries
  alias Storyarn.Repo

  @sha256_regex ~r/\A[0-9a-f]{64}\z/

  @doc """
  Ensures every unique blob referenced by an active asset has canonical
  project-scoped recovery storage.

  Existing canonical objects are fully verified. A missing or corrupt object
  is reconstructed only from an original asset object whose size, content
  type, and SHA-256 match the persisted row. Duplicate logical assets share
  one repair attempt, with equivalent originals used as verified fallbacks.
  """
  @spec ensure_active_asset_blobs(pos_integer()) ::
          {:ok,
           %{
             asset_count: non_neg_integer(),
             blob_count: non_neg_integer(),
             repaired_blob_count: non_neg_integer()
           }}
          | {:error, term()}
  def ensure_active_asset_blobs(project_id) when is_integer(project_id) and project_id > 0 do
    project_id
    |> AssetQueries.list_assets_for_export()
    |> ensure_asset_blobs()
  end

  def ensure_active_asset_blobs(_project_id), do: {:error, :invalid_project_id}

  @doc false
  @spec ensure_asset_blobs([Asset.t()]) ::
          {:ok,
           %{
             asset_count: non_neg_integer(),
             blob_count: non_neg_integer(),
             repaired_blob_count: non_neg_integer()
           }}
          | {:error, term()}
  def ensure_asset_blobs(assets) when is_list(assets) do
    if Enum.all?(assets, &match?(%Asset{}, &1)) do
      project_ids = assets |> Enum.map(& &1.project_id) |> Enum.uniq()

      if length(project_ids) <= 1,
        do: do_ensure_asset_blobs(assets, List.first(project_ids)),
        else: {:error, :invalid_asset_blob_inventory}
    else
      {:error, :invalid_asset_blob_inventory}
    end
  end

  def ensure_asset_blobs(_assets), do: {:error, :invalid_asset_blob_inventory}

  defp do_ensure_asset_blobs(assets, project_id) do
    blob_groups =
      assets
      |> Enum.group_by(&active_asset_blob_identity/1)
      |> Enum.sort_by(fn {identity, _assets} -> identity end)

    result =
      Enum.reduce_while(
        blob_groups,
        {:ok,
         %{
           asset_count: length(assets),
           blob_count: length(blob_groups),
           repaired_blob_count: 0
         }},
        fn {_identity, equivalent_assets}, {:ok, summary} ->
          case ensure_equivalent_asset_blob(equivalent_assets) do
            {:ok, _storage_key, :present} ->
              {:cont, {:ok, summary}}

            {:ok, _storage_key, :repaired} ->
              {:cont, {:ok, Map.update!(summary, :repaired_blob_count, &(&1 + 1))}}

            {:error, errors} ->
              first_asset = hd(equivalent_assets)

              {:halt,
               {:error,
                {:active_asset_blob_unavailable,
                 %{
                   asset_ids: Enum.map(equivalent_assets, & &1.id),
                   blob_hash: first_asset.blob_hash,
                   errors: errors
                 }}}}
          end
        end
      )

    report_active_asset_blob_repairs(result, project_id)
    result
  end

  @doc false
  @spec ensure_snapshot_asset_blobs(pos_integer(), [map()]) ::
          {:ok,
           %{
             asset_count: non_neg_integer(),
             blob_count: non_neg_integer(),
             repaired_blob_count: non_neg_integer()
           }}
          | {:error, term()}
  def ensure_snapshot_asset_blobs(project_id, blob_specs)
      when is_integer(project_id) and project_id > 0 and is_list(blob_specs) do
    with {:ok, specs} <- normalize_snapshot_blob_specs(blob_specs) do
      ensure_normalized_snapshot_asset_blobs(project_id, specs)
    end
  end

  def ensure_snapshot_asset_blobs(_project_id, _blob_specs), do: {:error, :invalid_snapshot_asset_blob_inventory}

  defp ensure_normalized_snapshot_asset_blobs(project_id, specs) do
    candidates = snapshot_blob_candidates(project_id, specs)

    candidates_by_identity =
      Enum.group_by(candidates, fn asset ->
        {asset.blob_hash, asset.size, asset.content_type, sanitized_svg_asset?(asset)}
      end)

    initial_summary =
      {:ok,
       %{
         asset_count: length(candidates),
         blob_count: length(specs),
         repaired_blob_count: 0
       }}

    result =
      Enum.reduce_while(specs, initial_summary, fn spec, summary ->
        ensure_snapshot_blob_spec(project_id, candidates_by_identity, spec, summary)
      end)

    report_active_asset_blob_repairs(result, project_id)
    result
  end

  defp snapshot_blob_candidates(project_id, specs) do
    captured_asset_ids = specs |> Enum.flat_map(& &1.asset_ids) |> Enum.uniq()

    Repo.all(
      from(asset in Asset,
        where: asset.project_id == ^project_id and asset.id in ^captured_asset_ids,
        order_by: [asc: asset.id]
      )
    )
  end

  defp ensure_snapshot_blob_spec(project_id, candidates_by_identity, spec, {:ok, summary}) do
    identity = {spec.blob_hash, spec.size, spec.content_type, spec.sanitized_svg}
    equivalent_assets = Map.get(candidates_by_identity, identity, [])

    project_id
    |> ensure_snapshot_blob(spec, equivalent_assets)
    |> update_snapshot_blob_summary(summary, spec)
  end

  defp update_snapshot_blob_summary({:ok, _storage_key, :present}, summary, _spec), do: {:cont, {:ok, summary}}

  defp update_snapshot_blob_summary({:ok, _storage_key, :repaired}, summary, _spec) do
    {:cont, {:ok, Map.update!(summary, :repaired_blob_count, &(&1 + 1))}}
  end

  defp update_snapshot_blob_summary({:error, errors}, _summary, spec) do
    {:halt,
     {:error,
      {:snapshot_asset_blob_unavailable,
       %{
         asset_ids: spec.asset_ids,
         blob_hash: spec.blob_hash,
         errors: errors
       }}}}
  end

  defp normalize_snapshot_blob_specs(blob_specs) do
    with {:ok, specs} <- Enum.reduce_while(blob_specs, {:ok, %{}}, &normalize_snapshot_blob_spec/2) do
      {:ok, materialize_snapshot_blob_specs(specs)}
    end
  end

  defp normalize_snapshot_blob_spec(
         %{
           blob_hash: blob_hash,
           size: size,
           content_type: content_type,
           sanitized_svg: sanitized_svg,
           asset_ids: asset_ids
         },
         {:ok, specs}
       ) do
    if valid_snapshot_blob_spec_shape?(blob_hash, size, content_type, sanitized_svg, asset_ids) do
      asset_ids = Enum.sort(asset_ids)
      identity = {blob_hash, size, content_type, sanitized_svg, asset_ids}

      validate_snapshot_blob_spec(specs, blob_hash, content_type, sanitized_svg, asset_ids, identity)
    else
      invalid_snapshot_blob_spec()
    end
  end

  defp normalize_snapshot_blob_spec(_invalid, _acc), do: invalid_snapshot_blob_spec()

  defp valid_snapshot_blob_spec_shape?(blob_hash, size, content_type, sanitized_svg, asset_ids) do
    is_binary(blob_hash) and is_integer(size) and size > 0 and is_binary(content_type) and
      content_type != "" and is_boolean(sanitized_svg) and is_list(asset_ids)
  end

  defp validate_snapshot_blob_spec(specs, blob_hash, content_type, sanitized_svg, asset_ids, identity) do
    cond do
      not Regex.match?(@sha256_regex, blob_hash) ->
        invalid_snapshot_blob_spec()

      not valid_snapshot_blob_content_type?(content_type, sanitized_svg) ->
        invalid_snapshot_blob_spec()

      not valid_captured_asset_ids?(asset_ids) ->
        invalid_snapshot_blob_spec()

      Map.has_key?(specs, blob_hash) and specs[blob_hash] != identity ->
        invalid_snapshot_blob_spec()

      true ->
        {:cont, {:ok, Map.put(specs, blob_hash, identity)}}
    end
  end

  defp valid_captured_asset_ids?(asset_ids) do
    asset_ids != [] and Enum.all?(asset_ids, &(is_integer(&1) and &1 > 0)) and
      length(asset_ids) == length(Enum.uniq(asset_ids))
  end

  defp invalid_snapshot_blob_spec, do: {:halt, {:error, :invalid_snapshot_asset_blob_inventory}}

  defp materialize_snapshot_blob_specs(specs) do
    specs
    |> Map.values()
    |> Enum.map(fn {blob_hash, size, content_type, sanitized_svg, asset_ids} ->
      %{
        blob_hash: blob_hash,
        size: size,
        content_type: content_type,
        sanitized_svg: sanitized_svg,
        asset_ids: asset_ids
      }
    end)
    |> Enum.sort_by(& &1.blob_hash)
  end

  defp ensure_snapshot_blob(project_id, spec, equivalent_assets) do
    case BlobStore.verify_asset_blob(project_id, spec.blob_hash, spec.size, spec.content_type,
           sanitized_svg: spec.sanitized_svg
         ) do
      {:ok, _storage_key, :present} = present ->
        present

      {:error, verification_reason} ->
        repair_snapshot_blob(equivalent_assets, verification_reason)
    end
  end

  defp repair_snapshot_blob(equivalent_assets, verification_reason) do
    equivalent_assets
    |> Enum.reduce_while({:error, []}, &try_snapshot_blob_candidate/2)
    |> normalize_snapshot_blob_repair(verification_reason)
  end

  defp try_snapshot_blob_candidate(asset, {:error, errors}) do
    case BlobStore.ensure_asset_blob(asset) do
      {:ok, _storage_key, _status} = success -> {:halt, success}
      {:error, reason} -> {:cont, {:error, [{asset.id, reason} | errors]}}
    end
  end

  defp normalize_snapshot_blob_repair({:error, []}, verification_reason), do: {:error, [{nil, verification_reason}]}

  defp normalize_snapshot_blob_repair({:error, errors}, _verification_reason), do: {:error, Enum.reverse(errors)}

  defp normalize_snapshot_blob_repair(success, _verification_reason), do: success

  defp sanitized_svg_asset?(%Asset{content_type: "image/svg+xml", metadata: %{"sanitized_svg" => true}}), do: true
  defp sanitized_svg_asset?(%Asset{}), do: false

  defp valid_snapshot_blob_content_type?("image/svg+xml", true), do: true

  defp valid_snapshot_blob_content_type?(content_type, false), do: Asset.allowed_content_type?(content_type)

  defp valid_snapshot_blob_content_type?(_content_type, _sanitized_svg), do: false

  defp active_asset_blob_identity(%Asset{blob_hash: blob_hash, content_type: content_type}) do
    {blob_hash, BlobStore.ext_from_content_type(content_type)}
  end

  defp ensure_equivalent_asset_blob(equivalent_assets) do
    equivalent_assets
    |> Enum.reduce_while({:error, []}, fn asset, {:error, errors} ->
      case BlobStore.ensure_asset_blob(asset) do
        {:ok, _storage_key, _status} = success -> {:halt, success}
        {:error, reason} -> {:cont, {:error, [{asset.id, reason} | errors]}}
      end
    end)
    |> case do
      {:error, errors} -> {:error, Enum.reverse(errors)}
      success -> success
    end
  end

  defp report_active_asset_blob_repairs({:ok, %{repaired_blob_count: repaired_blob_count}}, project_id)
       when repaired_blob_count > 0 do
    :telemetry.execute(
      [:storyarn, :assets, :canonical_blobs, :repaired],
      %{count: repaired_blob_count},
      %{project_id: project_id}
    )
  end

  defp report_active_asset_blob_repairs(_result, _project_id), do: :ok
end

defmodule Storyarn.Versioning.AssetMaterializationCache do
  @moduledoc """
  Process-local identity map for assets materialized from snapshots.

  A materialization scope owns a cache reference and passes it to every asset
  resolver participating in the operation. The cache guarantees that one
  source asset ID maps to exactly one destination asset ID in a target project.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Assets.Asset
  alias Storyarn.Repo

  @type mode :: :reuse | :copy
  @type fingerprint :: term()
  @type conflict_reason ::
          {:asset_materialization_conflict,
           %{
             target_project_id: integer(),
             source_asset_id: integer(),
             cached_mode: mode(),
             requested_mode: mode(),
             cached_fingerprint: fingerprint(),
             requested_fingerprint: fingerprint()
           }}
  @type stale_reason ::
          {:stale_asset_materialization,
           %{
             target_project_id: integer(),
             source_asset_id: integer(),
             destination_asset_id: integer()
           }}

  @spec new() :: reference()
  def new do
    reference = make_ref()
    Process.put(cache_key(reference), %{})
    reference
  end

  @spec fetch(reference(), integer(), integer(), fingerprint(), mode()) ::
          :miss
          | {:ok, integer()}
          | {:error,
             conflict_reason()
             | stale_reason()
             | :asset_materialization_cache_not_found}
  def fetch(reference, target_project_id, source_asset_id, fingerprint, mode)
      when is_reference(reference) and is_integer(target_project_id) and is_integer(source_asset_id) and
             mode in [:reuse, :copy] do
    with {:ok, entries} <- entries(reference) do
      case Map.get(entries, identity(target_project_id, source_asset_id)) do
        nil ->
          :miss

        %{fingerprint: ^fingerprint, mode: ^mode, destination_asset_id: destination_asset_id} ->
          validate_destination(
            target_project_id,
            source_asset_id,
            destination_asset_id,
            fingerprint
          )

        %{fingerprint: cached_fingerprint, mode: cached_mode} ->
          {:error,
           {:asset_materialization_conflict,
            %{
              target_project_id: target_project_id,
              source_asset_id: source_asset_id,
              cached_mode: cached_mode,
              requested_mode: mode,
              cached_fingerprint: cached_fingerprint,
              requested_fingerprint: fingerprint
            }}}
      end
    end
  end

  @spec put(reference(), integer(), integer(), fingerprint(), mode(), integer()) ::
          :ok
          | {:error,
             conflict_reason()
             | stale_reason()
             | :asset_materialization_cache_not_found
             | {:asset_materialization_destination_mismatch, integer(), integer()}}
  def put(reference, target_project_id, source_asset_id, fingerprint, mode, destination_asset_id)
      when is_reference(reference) and is_integer(target_project_id) and is_integer(source_asset_id) and
             mode in [:reuse, :copy] and is_integer(destination_asset_id) do
    case fetch(reference, target_project_id, source_asset_id, fingerprint, mode) do
      :miss ->
        with :ok <-
               validate_destination_for_put(
                 target_project_id,
                 destination_asset_id,
                 fingerprint
               ),
             {:ok, entries} <- entries(reference) do
          entry = %{
            fingerprint: fingerprint,
            mode: mode,
            destination_asset_id: destination_asset_id
          }

          Process.put(
            cache_key(reference),
            Map.put(entries, identity(target_project_id, source_asset_id), entry)
          )

          :ok
        end

      {:ok, ^destination_asset_id} ->
        :ok

      {:ok, cached_destination_asset_id} ->
        {:error, {:asset_materialization_destination_mismatch, cached_destination_asset_id, destination_asset_id}}

      {:error, _reason} = error ->
        error
    end
  end

  @spec discard(reference()) :: :ok
  def discard(reference) when is_reference(reference) do
    Process.delete(cache_key(reference))
    :ok
  end

  @spec discard_if_owned(reference(), boolean()) :: :ok
  def discard_if_owned(reference, true) when is_reference(reference), do: discard(reference)

  def discard_if_owned(reference, false) when is_reference(reference), do: :ok

  defp entries(reference) do
    case Process.get(cache_key(reference), :missing) do
      :missing -> {:error, :asset_materialization_cache_not_found}
      entries when is_map(entries) -> {:ok, entries}
    end
  end

  defp validate_destination(target_project_id, source_asset_id, destination_asset_id, fingerprint) do
    case destination_asset(destination_asset_id, target_project_id) do
      %Asset{} = asset ->
        if destination_matches_fingerprint?(asset, fingerprint) do
          {:ok, destination_asset_id}
        else
          stale_destination(
            target_project_id,
            source_asset_id,
            destination_asset_id
          )
        end

      nil ->
        stale_destination(
          target_project_id,
          source_asset_id,
          destination_asset_id
        )
    end
  end

  defp validate_destination_for_put(target_project_id, destination_asset_id, fingerprint) do
    case destination_asset(destination_asset_id, target_project_id) do
      %Asset{} = asset ->
        if destination_matches_fingerprint?(asset, fingerprint),
          do: :ok,
          else: {:error, {:asset_materialization_destination_mismatch, target_project_id, destination_asset_id}}

      nil ->
        {:error, {:asset_materialization_destination_mismatch, target_project_id, destination_asset_id}}
    end
  end

  defp destination_asset(destination_asset_id, target_project_id) do
    query =
      from(asset in Asset,
        where:
          asset.id == ^destination_asset_id and
            asset.project_id == ^target_project_id,
        select: asset
      )

    query = if Repo.in_transaction?(), do: lock(query, "FOR UPDATE"), else: query
    Repo.one(query)
  end

  defp destination_matches_fingerprint?(asset, fingerprint) when is_map(fingerprint) do
    asset.blob_hash == fingerprint[:blob_hash] and
      asset.filename == fingerprint[:filename] and
      asset.content_type == fingerprint[:content_type] and
      asset.size == fingerprint[:size] and
      sanitized_svg?(asset.metadata) == fingerprint[:sanitized_svg]
  end

  defp destination_matches_fingerprint?(_asset, _fingerprint), do: false

  defp sanitized_svg?(%{"sanitized_svg" => true}), do: true
  defp sanitized_svg?(_metadata), do: false

  defp stale_destination(target_project_id, source_asset_id, destination_asset_id) do
    {:error,
     {:stale_asset_materialization,
      %{
        target_project_id: target_project_id,
        source_asset_id: source_asset_id,
        destination_asset_id: destination_asset_id
      }}}
  end

  defp identity(target_project_id, source_asset_id), do: {target_project_id, source_asset_id}

  defp cache_key(reference), do: {__MODULE__, reference}
end

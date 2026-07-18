defmodule Storyarn.Versioning.AssetMaterializationScope do
  @moduledoc false

  alias Storyarn.Assets.StorageCompensation
  alias Storyarn.Versioning.AssetMaterializationCache
  alias Storyarn.Versioning.Builders.AssetCopyError

  @spec run(keyword(), (keyword() -> term())) :: term()
  def run(opts, fun) when is_list(opts) and is_function(fun, 1) do
    {cache, owns_cache?} =
      scope_reference(opts, :asset_materialization_cache, &AssetMaterializationCache.new/0)

    {copy_tracker, owns_copy_tracker?} =
      scope_reference(opts, :asset_copy_tracker, &StorageCompensation.new/0)

    scoped_opts =
      opts
      |> Keyword.put(:asset_materialization_cache, cache)
      |> Keyword.put(:asset_copy_tracker, copy_tracker)
      |> Keyword.put(:asset_error_mode, :strict)

    case invoke(fun, scoped_opts, cache, owns_cache?, copy_tracker, owns_copy_tracker?) do
      {:asset_copy_error, asset_id, reason} ->
        {:error, {:asset_materialization_failed, asset_id, reason}}

      {:scope_result, result} ->
        finalize(
          result,
          cache,
          owns_cache?,
          copy_tracker,
          owns_copy_tracker?
        )
    end
  end

  defp invoke(fun, scoped_opts, cache, owns_cache?, copy_tracker, owns_copy_tracker?) do
    {:scope_result, fun.(scoped_opts)}
  rescue
    error in AssetCopyError ->
      cleanup_owned!(cache, owns_cache?, copy_tracker, owns_copy_tracker?)
      {:asset_copy_error, error.asset_id, error.reason}

    error ->
      cleanup_owned!(cache, owns_cache?, copy_tracker, owns_copy_tracker?)
      reraise error, __STACKTRACE__
  catch
    kind, reason ->
      cleanup_owned!(cache, owns_cache?, copy_tracker, owns_copy_tracker?)
      :erlang.raise(kind, reason, __STACKTRACE__)
  end

  defp scope_reference(opts, key, create_fun) do
    case Keyword.get(opts, key) do
      reference when is_reference(reference) -> {reference, false}
      _reference -> {create_fun.(), true}
    end
  end

  defp finalize(result, cache, owns_cache?, copy_tracker, owns_copy_tracker?)
       when is_tuple(result) and tuple_size(result) > 0 and elem(result, 0) == :ok do
    discard_owned(cache, owns_cache?, copy_tracker, owns_copy_tracker?)
    result
  end

  defp finalize(result, cache, owns_cache?, copy_tracker, owns_copy_tracker?)
       when is_tuple(result) and tuple_size(result) > 0 and elem(result, 0) == :error do
    AssetMaterializationCache.discard_if_owned(cache, owns_cache?)

    case cleanup_copy_tracker(copy_tracker, owns_copy_tracker?) do
      :ok -> result
      {:error, reason} -> {:error, reason}
    end
  end

  defp cleanup_owned!(cache, owns_cache?, copy_tracker, owns_copy_tracker?) do
    AssetMaterializationCache.discard_if_owned(cache, owns_cache?)

    if owns_copy_tracker? do
      StorageCompensation.cleanup!(copy_tracker)
    end
  end

  defp discard_owned(cache, owns_cache?, copy_tracker, owns_copy_tracker?) do
    AssetMaterializationCache.discard_if_owned(cache, owns_cache?)

    if owns_copy_tracker? do
      StorageCompensation.discard(copy_tracker)
    end
  end

  defp cleanup_copy_tracker(_copy_tracker, false), do: :ok
  defp cleanup_copy_tracker(copy_tracker, true), do: StorageCompensation.cleanup(copy_tracker)
end

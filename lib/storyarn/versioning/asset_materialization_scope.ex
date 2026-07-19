defmodule Storyarn.Versioning.AssetMaterializationScope do
  @moduledoc false

  alias Storyarn.Assets.StorageCompensation
  alias Storyarn.Repo
  alias Storyarn.Versioning.AssetMaterializationCache
  alias Storyarn.Versioning.Builders.AssetCopyError

  require Logger

  @spec run(keyword(), (keyword() -> term())) :: term()
  def run(opts, fun) when is_list(opts) and is_function(fun, 1) do
    {cache, owns_cache?} =
      scope_reference(opts, :asset_materialization_cache, &AssetMaterializationCache.new/0)

    case copy_tracker_scope(opts) do
      {:ok, copy_tracker, owns_copy_tracker?} ->
        scoped_opts =
          opts
          |> Keyword.put(:asset_materialization_cache, cache)
          |> Keyword.put(:asset_copy_tracker, copy_tracker)
          |> Keyword.put(:asset_error_mode, :strict)

        case invoke(fun, scoped_opts, cache, owns_cache?, copy_tracker, owns_copy_tracker?) do
          {:asset_copy_error, asset_id, reason} ->
            {:error, {:asset_materialization_failed, asset_id, reason}}

          {:asset_copy_cleanup_error, asset_id, reason, cleanup_reason} ->
            {:error, {:asset_storage_cleanup_failed, {:asset_materialization_failed, asset_id, reason}, cleanup_reason}}

          {:scope_result, result} ->
            finalize(
              result,
              cache,
              owns_cache?,
              copy_tracker,
              owns_copy_tracker?
            )
        end

      {:error, reason} ->
        AssetMaterializationCache.discard_if_owned(cache, owns_cache?)
        {:error, reason}
    end
  end

  defp invoke(fun, scoped_opts, cache, owns_cache?, copy_tracker, owns_copy_tracker?) do
    {:scope_result, fun.(scoped_opts)}
  rescue
    error in AssetCopyError ->
      case cleanup_owned(cache, owns_cache?, copy_tracker, owns_copy_tracker?) do
        :ok ->
          {:asset_copy_error, error.asset_id, error.reason}

        {:error, cleanup_reason} ->
          {:asset_copy_cleanup_error, error.asset_id, error.reason, cleanup_reason}
      end

    error ->
      log_cleanup_failure(cleanup_owned(cache, owns_cache?, copy_tracker, owns_copy_tracker?))
      reraise error, __STACKTRACE__
  catch
    kind, reason ->
      log_cleanup_failure(cleanup_owned(cache, owns_cache?, copy_tracker, owns_copy_tracker?))
      :erlang.raise(kind, reason, __STACKTRACE__)
  end

  defp scope_reference(opts, key, create_fun) do
    case Keyword.get(opts, key) do
      reference when is_reference(reference) -> {reference, false}
      _reference -> {create_fun.(), true}
    end
  end

  defp copy_tracker_scope(opts) do
    case Keyword.get(opts, :asset_copy_tracker) do
      reference when is_reference(reference) ->
        {:ok, reference, false}

      _reference ->
        if Repo.in_transaction?(),
          do: {:error, :asset_copy_tracker_required_in_transaction},
          else: {:ok, StorageCompensation.new(), true}
    end
  end

  defp finalize(result, cache, owns_cache?, copy_tracker, owns_copy_tracker?)
       when is_tuple(result) and tuple_size(result) > 0 and elem(result, 0) == :ok do
    AssetMaterializationCache.discard_if_owned(cache, owns_cache?)

    case cleanup_successful_copy_tracker(copy_tracker, owns_copy_tracker?) do
      :ok -> result
      {:error, reason} -> {:error, {:asset_storage_cleanup_failed, result, reason}}
    end
  end

  defp finalize(result, cache, owns_cache?, copy_tracker, owns_copy_tracker?)
       when is_tuple(result) and tuple_size(result) > 0 and elem(result, 0) == :error do
    AssetMaterializationCache.discard_if_owned(cache, owns_cache?)

    case cleanup_copy_tracker(copy_tracker, owns_copy_tracker?) do
      :ok -> result
      {:error, reason} -> {:error, {:asset_storage_cleanup_failed, result, reason}}
    end
  end

  defp finalize(result, cache, owns_cache?, copy_tracker, owns_copy_tracker?) do
    invalid_result = {:error, {:invalid_asset_materialization_scope_result, result}}
    AssetMaterializationCache.discard_if_owned(cache, owns_cache?)

    case cleanup_copy_tracker(copy_tracker, owns_copy_tracker?) do
      :ok -> invalid_result
      {:error, reason} -> {:error, {:asset_storage_cleanup_failed, invalid_result, reason}}
    end
  end

  defp cleanup_owned(cache, owns_cache?, copy_tracker, owns_copy_tracker?) do
    AssetMaterializationCache.discard_if_owned(cache, owns_cache?)
    cleanup_copy_tracker(copy_tracker, owns_copy_tracker?)
  end

  defp log_cleanup_failure(:ok), do: :ok

  defp log_cleanup_failure({:error, reason}) do
    Logger.error("Asset materialization cleanup failed while preserving the original exception: #{inspect(reason)}")
  end

  defp cleanup_copy_tracker(_copy_tracker, false), do: :ok

  defp cleanup_copy_tracker(copy_tracker, true), do: StorageCompensation.cleanup_after_rollback(copy_tracker)

  defp cleanup_successful_copy_tracker(_copy_tracker, false), do: :ok

  defp cleanup_successful_copy_tracker(copy_tracker, true) do
    StorageCompensation.cleanup_unretained(copy_tracker)
  end
end

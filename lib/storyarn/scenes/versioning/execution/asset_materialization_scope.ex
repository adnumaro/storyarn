defmodule Storyarn.Scenes.Versioning.Execution.AssetMaterializationScope do
  @moduledoc false

  alias Storyarn.Scenes.Assets
  alias Storyarn.Scenes.Versioning.AssetCopyError
  alias Storyarn.Scenes.Versioning.Execution.AssetMaterializationCache

  def run(opts, fun) when is_list(opts) and is_function(fun, 1) do
    {cache, owns_cache?} = cache_scope(opts)

    try do
      opts
      |> Keyword.put(:asset_materialization_cache, cache)
      |> Assets.run_asset_materialization_scope(fn scoped_opts ->
        invoke(fun, scoped_opts)
      end)
    after
      AssetMaterializationCache.discard_if_owned(cache, owns_cache?)
    end
  end

  defp invoke(fun, scoped_opts) do
    fun.(scoped_opts)
  rescue
    error in AssetCopyError ->
      {:error, {:asset_materialization_failed, error.asset_id, error.reason}}
  end

  defp cache_scope(opts) do
    case Keyword.get(opts, :asset_materialization_cache) do
      reference when is_reference(reference) -> {reference, false}
      _reference -> {AssetMaterializationCache.new(), true}
    end
  end
end

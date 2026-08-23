defmodule Storyarn.Scenes.Versioning.AssetMaterializationScopeTest do
  use Storyarn.DataCase, async: false

  alias Storyarn.Repo
  alias Storyarn.Scenes.Versioning.AssetCopyError
  alias Storyarn.Scenes.Versioning.AssetMaterializationCache
  alias Storyarn.Scenes.Versioning.AssetMaterializationScope

  test "provides a real owner tracker and normalizes Scene copy failures" do
    parent = self()

    assert {:error, {:asset_materialization_failed, 17, :missing_blob}} =
             AssetMaterializationScope.run([], fn opts ->
               assert is_reference(opts[:asset_copy_tracker])
               assert is_reference(opts[:asset_materialization_cache])
               send(parent, {:cache, opts[:asset_materialization_cache]})
               raise AssetCopyError, asset_id: 17, reason: :missing_blob
             end)

    assert_receive {:cache, cache}

    assert {:error, :asset_materialization_cache_not_found} =
             AssetMaterializationCache.fetch(cache, 1, 1, %{}, :reuse)
  end

  test "fails closed inside a caller transaction without its owner tracker" do
    assert {:ok, {:error, :asset_copy_tracker_required_in_transaction}} =
             Repo.transaction(fn ->
               AssetMaterializationScope.run([], fn _opts ->
                 flunk("materialization callback must not run without a caller-owned tracker")
               end)
             end)
  end
end

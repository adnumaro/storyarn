defmodule Storyarn.Projects.Assets.AssetFamilyTest do
  use ExUnit.Case, async: true

  alias Storyarn.Projects.Assets.Asset
  alias Storyarn.Projects.Assets.AssetFamily

  test "traverses intrinsic family links as one undirected transitive component" do
    assets = [
      %Asset{id: 1, metadata: %{"web_asset_id" => 2}},
      %Asset{id: 2, metadata: %{"variant_asset_ids" => %{"gallery" => "3"}}},
      %Asset{id: 3, metadata: %{}},
      %Asset{id: 4, metadata: %{"original_asset_id" => 5}},
      %Asset{id: 5, metadata: nil}
    ]

    assert AssetFamily.component_ids(assets, [3]) == MapSet.new([1, 2, 3])
    assert AssetFamily.component_ids(assets, [4]) == MapSet.new([4, 5])
  end

  test "ignores malformed and out-of-inventory family references" do
    assets = [
      %Asset{id: 1, metadata: %{"web_asset_id" => 999}},
      %Asset{id: 2, metadata: %{"variant_asset_ids" => "invalid"}}
    ]

    assert AssetFamily.component_ids(assets, [1]) == MapSet.new([1])
    assert AssetFamily.component_ids(assets, [2]) == MapSet.new([2])
  end
end

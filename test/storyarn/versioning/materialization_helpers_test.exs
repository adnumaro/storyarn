defmodule Storyarn.Versioning.MaterializationHelpersTest do
  use ExUnit.Case, async: true

  alias Storyarn.Versioning.MaterializationHelpers

  describe "asset_resolution_opts/3" do
    test "pins every in-place entity restore to the destination project" do
      for entity_type <- ["flow", "scene", "sheet", "future_entity"] do
        assert MaterializationHelpers.asset_resolution_opts(
                 [
                   restore_action: {:entity_version_restore, entity_type},
                   asset_materialization_cache: :cache,
                   ignored: :value
                 ],
                 :reuse,
                 42
               ) == [
                 source_project_id: 42,
                 asset_mode: :reuse,
                 asset_materialization_cache: :cache
               ]
      end
    end

    test "keeps cross-project materializations unpinned" do
      assert MaterializationHelpers.asset_resolution_opts(
               [restore_action: {:project_snapshot_restore, "full"}],
               :copy,
               42
             ) == [asset_mode: :copy]
    end
  end
end

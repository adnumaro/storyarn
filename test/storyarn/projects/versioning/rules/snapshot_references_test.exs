defmodule Storyarn.Projects.Versioning.SnapshotReferencesTest do
  use ExUnit.Case, async: true

  alias Storyarn.Projects.Versioning.SnapshotReferences

  test "preserves Sheet then Flow then Scene precedence when several references are invalid" do
    snapshot_data = %{
      "sheets" => [
        %{
          "id" => 1,
          "snapshot" => %{
            "avatar_asset_id" => 996,
            "banner_asset_id" => 999,
            "hidden_inherited_block_ids" => [995],
            "blocks" => []
          }
        }
      ],
      "flows" => [
        %{
          "id" => 2,
          "snapshot" => %{"scene_id" => 998, "nodes" => []}
        }
      ],
      "scenes" => [
        %{
          "id" => 3,
          "snapshot" => %{"background_asset_id" => 997, "layers" => []}
        }
      ]
    }

    id_maps = %{
      sheet: %{1 => 1},
      block: %{},
      avatar: %{},
      flow: %{2 => 2},
      scene: %{3 => 3}
    }

    assert {:error, {:missing_project_snapshot_reference, {:sheet, 1, "Banner image"}, 999}} =
             SnapshotReferences.validate(snapshot_data, id_maps, MapSet.new(), %{})
  end

  test "checks Flow before Scene once every Sheet reference is valid" do
    snapshot_data = %{
      "sheets" => [],
      "flows" => [
        %{
          "id" => 2,
          "snapshot" => %{"scene_id" => 998, "nodes" => []}
        }
      ],
      "scenes" => [
        %{
          "id" => 3,
          "snapshot" => %{"background_asset_id" => 997, "layers" => []}
        }
      ]
    }

    id_maps = %{
      sheet: %{},
      block: %{},
      avatar: %{},
      flow: %{2 => 2},
      scene: %{3 => 3}
    }

    assert {:error, {:missing_project_snapshot_reference, {:flow, 2, "Flow backdrop scene"}, 998}} =
             SnapshotReferences.validate(snapshot_data, id_maps, MapSet.new(), %{})
  end

  test "preserves Flow entry order when several Flow snapshots are invalid" do
    snapshot_data = %{
      "sheets" => [],
      "flows" => [
        %{"id" => 10, "snapshot" => %{"scene_id" => 901, "nodes" => []}},
        %{"id" => 11, "snapshot" => %{"scene_id" => 902, "nodes" => []}}
      ],
      "scenes" => []
    }

    id_maps = %{
      sheet: %{},
      block: %{},
      avatar: %{},
      flow: %{10 => 10, 11 => 11},
      scene: %{}
    }

    assert {:error, {:missing_project_snapshot_reference, {:flow, 10, "Flow backdrop scene"}, 901}} =
             SnapshotReferences.validate(snapshot_data, id_maps, MapSet.new(), %{})
  end

  test "preserves the internal Flow reference order in the first invalid receipt" do
    snapshot_data = %{
      "sheets" => [],
      "flows" => [
        %{
          "id" => 20,
          "snapshot" => %{
            "scene_id" => 903,
            "nodes" => [
              %{
                "type" => "dialogue",
                "data" => %{
                  "speaker_sheet_id" => 101,
                  "location_sheet_id" => 102
                }
              }
            ]
          }
        }
      ],
      "scenes" => []
    }

    id_maps = %{
      sheet: %{},
      block: %{},
      avatar: %{},
      flow: %{20 => 20},
      scene: %{}
    }

    assert {:error, {:missing_project_snapshot_reference, {:flow, 20, "Node #1 (dialogue) — location"}, 102}} =
             SnapshotReferences.validate(snapshot_data, id_maps, MapSet.new(), %{})
  end

  test "accepts receipts from all three scanners against the supplied preflight maps" do
    mention =
      ~s(<span class="mention" data-type="sheet" data-id="1">Sheet</span>)

    snapshot_data = %{
      "sheets" => [
        %{
          "id" => 1,
          "snapshot" => %{
            "avatar_asset_id" => 9,
            "banner_asset_id" => 9,
            "hidden_inherited_block_ids" => [4],
            "blocks" => [
              %{
                "inherited_from_block_id" => 4,
                "type" => "reference",
                "value" => %{"target_type" => "flow", "target_id" => "2"}
              },
              %{
                "inherited_from_block_id" => nil,
                "type" => "rich_text",
                "value" => %{"content" => mention}
              }
            ]
          }
        }
      ],
      "flows" => [
        %{
          "id" => 2,
          "snapshot" => %{
            "scene_id" => 3,
            "nodes" => [
              %{
                "type" => "dialogue",
                "data" => %{
                  "speaker_sheet_id" => 1,
                  "avatar_id" => 5,
                  "audio_asset_id" => 9
                }
              }
            ]
          }
        }
      ],
      "scenes" => [
        %{
          "id" => 3,
          "snapshot" => %{
            "background_asset_id" => 9,
            "layers" => [
              %{
                "pins" => [%{"sheet_id" => 1, "icon_asset_id" => 9, "flow_id" => 2}],
                "zones" => [%{"target_type" => "scene", "target_id" => 3}]
              }
            ]
          }
        }
      ]
    }

    id_maps = %{
      sheet: %{1 => 101},
      block: %{4 => 104},
      avatar: %{5 => 105},
      flow: %{2 => 102},
      scene: %{3 => 103}
    }

    assert :ok =
             SnapshotReferences.validate(
               snapshot_data,
               id_maps,
               MapSet.new([9]),
               %{5 => 1}
             )
  end
end

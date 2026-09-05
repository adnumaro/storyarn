defmodule Storyarn.Flows.SequenceCompositionTest do
  use ExUnit.Case, async: true

  alias Storyarn.Flows

  test "composes all non-removed visual layers in deterministic depth and z order" do
    nodes = %{
      1 => sequence(1, nil, [layer(11, 20), layer(12, 10), layer(13, 0, false)], []),
      2 => sequence(2, 1, [layer(21, -10)], []),
      3 => %{id: 3, type: "dialogue", parent_id: 2}
    }

    assert %{visual_layers: layers} = Flows.compose_player_sequences(%{current_node_id: 3}, nodes)

    assert Enum.map(layers, &{&1.item.id, &1.sequence_id, &1.depth}) == [
             {13, 1, 0},
             {12, 1, 0},
             {11, 1, 0},
             {21, 2, 1}
           ]

    refute Enum.find(layers, &(&1.item.id == 13)).item.visible
  end

  test "orders audio within each active sequence and keeps ancestors first" do
    nodes = %{
      1 => sequence(1, nil, [], [track(13, "sfx", 2), track(11, "music", 4), track(12, "ambience", 9)]),
      2 => sequence(2, 1, [], [track(21, "music", 1)]),
      3 => %{id: 3, type: "dialogue", parent_id: 2}
    }

    assert %{audio_tracks: tracks} = Flows.compose_player_sequences(%{current_node_id: 3}, nodes)

    assert Enum.map(tracks, &{&1.item.id, &1.sequence_id, &1.depth}) == [
             {12, 1, 0},
             {11, 1, 0},
             {13, 1, 0},
             {21, 2, 1}
           ]
  end

  test "fails closed with a diagnostic for a malformed source cycle" do
    nodes = %{
      1 => 1 |> sequence(nil, [layer(11, 0)], []) |> Map.put(:composition_source_id, 2),
      2 => 2 |> sequence(nil, [layer(21, 0)], []) |> Map.put(:composition_source_id, 1),
      3 => %{id: 3, type: "dialogue", parent_id: nil, composition_source_id: 1}
    }

    composition = Flows.compose_player_sequences(%{current_node_id: 3}, nodes)

    assert composition.visual_layers == []
    assert composition.audio_tracks == []
    assert composition.diagnostics == [%{code: "composition_cycle", node_id: 1}]
  end

  test "fails closed when an explicit source is missing" do
    nodes = %{
      3 => %{id: 3, type: "dialogue", parent_id: 1, composition_source_id: 999}
    }

    assert Flows.compose_node_sequences(3, nodes) == %{
             visual_layers: [],
             audio_tracks: [],
             diagnostics: [%{code: "missing_composition_source", node_id: 999}]
           }
  end

  test "applies child visual overrides per property and replaces the preloaded asset" do
    base =
      11
      |> layer(10)
      |> Map.merge(%{
        layer_key: "hero",
        asset_id: 101,
        asset: %{id: 101, name: "calm"},
        opacity: 1.0
      })

    patch =
      21
      |> layer(999)
      |> Map.merge(%{
        layer_key: "hero",
        asset_id: 202,
        asset: %{id: 202, name: "angry"},
        opacity: 0.4,
        overridden_fields: ["asset_id", "opacity"]
      })

    nodes = %{
      1 => 1 |> sequence(nil, [base], []) |> Map.put(:composition_source_id, nil),
      2 => %{
        id: 2,
        type: "dialogue",
        composition_source_id: 1,
        sequence_visual_layers: [patch],
        sequence_tracks: []
      }
    }

    assert %{visual_layers: [resolved], diagnostics: []} = Flows.compose_node_sequences(2, nodes)
    assert resolved.item.z_index == 10
    assert resolved.item.opacity == 0.4
    assert resolved.item.asset_id == 202
    assert resolved.item.asset == %{id: 202, name: "angry"}
    assert resolved.property_sources["z_index"] == 1
    assert resolved.property_sources["opacity"] == 2
  end

  test "keeps audio identity for a volume override and changes it for an asset override" do
    base =
      11
      |> track("music", 0)
      |> Map.merge(%{
        track_key: "score",
        asset_id: 101,
        asset: %{id: 101},
        volume: Decimal.new("1.0")
      })

    volume_patch =
      21
      |> track("music", 0)
      |> Map.merge(%{
        track_key: "score",
        asset_id: nil,
        asset: nil,
        volume: Decimal.new("0.5"),
        is_override: true,
        overridden_fields: ["volume"]
      })

    asset_patch =
      31
      |> track("music", 0)
      |> Map.merge(%{
        track_key: "score",
        asset_id: 303,
        asset: %{id: 303},
        volume: Decimal.new("0.1"),
        is_override: true,
        overridden_fields: ["asset_id"]
      })

    nodes = %{
      1 => 1 |> sequence(nil, [], [base]) |> Map.put(:composition_source_id, nil),
      2 => composition_dialogue(2, 1, [], [volume_patch]),
      3 => composition_dialogue(3, 2, [], [asset_patch])
    }

    assert %{audio_tracks: [volume_result]} = Flows.compose_node_sequences(2, nodes)
    assert volume_result.item.asset == %{id: 101}
    assert volume_result.item.volume == Decimal.new("0.5")
    assert volume_result.asset_source_row_id == 11
    assert volume_result.continuity_key == "score:11"

    assert %{audio_tracks: [asset_result]} = Flows.compose_node_sequences(3, nodes)
    assert asset_result.item.asset == %{id: 303}
    assert asset_result.item.volume == Decimal.new("0.5")
    assert asset_result.asset_source_row_id == 31
    assert asset_result.continuity_key == "score:31"
  end

  test "tombstones remove inherited visual and audio entries" do
    layer_tombstone = %{
      id: 21,
      layer_key: "hero",
      overridden_fields: [],
      removed: true
    }

    track_tombstone = %{
      id: 22,
      track_key: "score",
      kind: "music",
      is_override: true,
      overridden_fields: [],
      removed: true
    }

    nodes = %{
      1 =>
        1
        |> sequence(
          nil,
          [Map.put(layer(11, 0), :layer_key, "hero")],
          [Map.put(track(12, "music", 0), :track_key, "score")]
        )
        |> Map.put(:composition_source_id, nil),
      2 => composition_dialogue(2, 1, [layer_tombstone], [track_tombstone])
    }

    assert Flows.compose_node_sequences(2, nodes) == %{
             visual_layers: [],
             audio_tracks: [],
             diagnostics: []
           }
  end

  test "complete restorations and non-override tracks become local definitions" do
    base_layer =
      11
      |> layer(0)
      |> Map.merge(%{layer_key: "hero", asset_id: 101, asset: %{id: 101}})

    base_track =
      12
      |> track("music", 0)
      |> Map.merge(%{track_key: "score", asset_id: 201, asset: %{id: 201}})

    layer_tombstone = %{
      id: 21,
      layer_key: "hero",
      overridden_fields: [],
      removed: true
    }

    track_tombstone = %{
      id: 22,
      track_key: "score",
      kind: "music",
      is_override: true,
      overridden_fields: [],
      removed: true
    }

    restored_layer =
      31
      |> layer(5)
      |> Map.merge(%{
        layer_key: "hero",
        asset_id: 102,
        asset: %{id: 102},
        overridden_fields: visual_fields()
      })

    restored_track =
      32
      |> track("music", 0)
      |> Map.merge(%{
        track_key: "score",
        asset_id: 202,
        asset: %{id: 202},
        is_override: true,
        overridden_fields: track_fields()
      })

    replacement_track =
      41
      |> track("music", 0)
      |> Map.merge(%{
        track_key: "score",
        asset_id: 203,
        asset: %{id: 203},
        is_override: false,
        overridden_fields: track_fields()
      })

    nodes = %{
      1 =>
        1
        |> sequence(nil, [base_layer], [base_track])
        |> Map.put(:composition_source_id, nil),
      2 => composition_dialogue(2, 1, [layer_tombstone], [track_tombstone]),
      3 => composition_dialogue(3, 2, [restored_layer], [restored_track]),
      4 => composition_dialogue(4, 3, [], [replacement_track])
    }

    assert %{visual_layers: [visual], audio_tracks: [audio]} =
             Flows.inspect_node_sequences(3, nodes)

    assert visual.sequence_id == 3
    assert visual.depth == 2
    assert visual.item.asset_id == 102
    assert audio.sequence_id == 3
    assert audio.depth == 2
    assert audio.item.asset_id == 202

    assert %{audio_tracks: [replacement]} = Flows.inspect_node_sequences(4, nodes)
    assert replacement.sequence_id == 4
    assert replacement.depth == 3
    assert replacement.item.asset_id == 203
    assert replacement.asset_source_row_id == 41

    standalone = %{
      5 =>
        composition_dialogue(
          5,
          nil,
          [Map.put(restored_layer, :id, 51)],
          [Map.put(restored_track, :id, 52)]
        )
    }

    assert %{visual_layers: [standalone_layer], audio_tracks: [standalone_track], diagnostics: []} =
             Flows.inspect_node_sequences(5, standalone)

    assert standalone_layer.sequence_id == 5
    assert standalone_track.sequence_id == 5
  end

  test "partial overrides cannot restore an identity hidden by a tombstone" do
    base_layer = Map.merge(layer(11, 0), %{layer_key: "hero", overridden_fields: visual_fields()})

    base_track =
      Map.merge(track(12, "music", 0), %{
        track_key: "score",
        is_override: false,
        overridden_fields: track_fields()
      })

    layer_tombstone = %{id: 21, layer_key: "hero", overridden_fields: [], removed: true}

    track_tombstone = %{
      id: 22,
      track_key: "score",
      kind: "music",
      is_override: true,
      overridden_fields: [],
      removed: true
    }

    layer_patch = %{
      id: 31,
      layer_key: "hero",
      opacity: 0.5,
      overridden_fields: ["opacity"],
      removed: false
    }

    track_patch = %{
      id: 32,
      track_key: "score",
      kind: "music",
      volume: Decimal.new("0.5"),
      is_override: true,
      overridden_fields: ["volume"],
      removed: false
    }

    nodes = %{
      1 => composition_dialogue(1, nil, [base_layer], [base_track]),
      2 => composition_dialogue(2, 1, [layer_tombstone], [track_tombstone]),
      3 => composition_dialogue(3, 2, [layer_patch], [track_patch])
    }

    composition = Flows.inspect_node_sequences(3, nodes)

    assert composition.visual_layers == []
    assert composition.audio_tracks == []
    assert Enum.any?(composition.diagnostics, &(&1.code == "missing_inherited_layer"))
    assert Enum.any?(composition.diagnostics, &(&1.code == "missing_inherited_track"))
  end

  test "returns an empty composition when there is no active runtime node" do
    assert Flows.compose_player_sequences(%{current_node_id: 999}, %{}) == %{
             visual_layers: [],
             audio_tracks: [],
             diagnostics: []
           }
  end

  defp sequence(id, parent_id, layers, tracks) do
    %{
      id: id,
      type: "sequence",
      parent_id: parent_id,
      sequence_visual_layers: layers,
      sequence_tracks: tracks
    }
  end

  defp layer(id, z_index, visible \\ true), do: %{id: id, z_index: z_index, visible: visible}
  defp track(id, kind, position), do: %{id: id, kind: kind, position: position}

  defp visual_fields do
    ~w(asset_id kind label z_index slot x y width height anchor_x anchor_y fit opacity visible)
  end

  defp track_fields, do: ~w(position asset_id start_time end_time volume)

  defp composition_dialogue(id, source_id, layers, tracks) do
    %{
      id: id,
      type: "dialogue",
      composition_source_id: source_id,
      sequence_visual_layers: layers,
      sequence_tracks: tracks
    }
  end
end

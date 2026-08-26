defmodule Storyarn.Flows.SequenceCompositionTest do
  use ExUnit.Case, async: true

  alias Storyarn.Flows

  test "composes parent and child visual layers in deterministic depth and z order" do
    nodes = %{
      1 => sequence(1, nil, [layer(11, 20), layer(12, 10), layer(13, 0, false)], []),
      2 => sequence(2, 1, [layer(21, -10)], []),
      3 => %{id: 3, type: "dialogue", parent_id: 2}
    }

    assert %{visual_layers: layers} = Flows.compose_player_sequences(%{current_node_id: 3}, nodes)

    assert Enum.map(layers, &{&1.item.id, &1.sequence_id, &1.depth}) == [
             {12, 1, 0},
             {11, 1, 0},
             {21, 2, 1}
           ]
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

  test "protects against malformed parent cycles" do
    nodes = %{
      1 => sequence(1, 2, [layer(11, 0)], []),
      2 => sequence(2, 1, [layer(21, 0)], []),
      3 => %{id: 3, type: "dialogue", parent_id: 1}
    }

    composition = Flows.compose_player_sequences(%{current_node_id: 3}, nodes)

    assert Enum.map(composition.visual_layers, & &1.item.id) == [21, 11]
  end

  test "returns an empty composition when there is no active runtime node" do
    assert Flows.compose_player_sequences(%{current_node_id: 999}, %{}) == %{
             visual_layers: [],
             audio_tracks: []
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
end

defmodule Storyarn.Flows.SequenceComposition do
  @moduledoc """
  Computes the active nested sequence composition for a player frame.

  It owns ancestor resolution, cycle protection and deterministic ordering.
  Presentation adapters remain responsible for turning attached assets into
  media URLs and serializing the final props.
  """

  @type composed_item :: %{
          item: map(),
          sequence_id: integer(),
          depth: non_neg_integer()
        }

  @type t :: %{
          visual_layers: [composed_item()],
          audio_tracks: [composed_item()]
        }

  @doc "Composes the active sequence ancestors for the current player node."
  @spec compose(map(), map()) :: t()
  def compose(state, nodes) when is_map(state) and is_map(nodes) do
    sequences = active_sequence_chain(state, nodes)

    %{
      visual_layers: compose_visual_layers(sequences),
      audio_tracks: compose_audio_tracks(sequences)
    }
  end

  def compose(_state, _nodes), do: %{visual_layers: [], audio_tracks: []}

  defp active_sequence_chain(state, nodes) do
    nodes
    |> Map.get(state.current_node_id)
    |> sequence_chain_for_node(nodes)
  end

  defp sequence_chain_for_node(%{parent_id: parent_id}, nodes) do
    do_sequence_chain(parent_id, nodes, MapSet.new(), [])
  end

  defp sequence_chain_for_node(_node, _nodes), do: []

  defp do_sequence_chain(nil, _nodes, _visited, acc), do: acc

  defp do_sequence_chain(sequence_id, nodes, visited, acc) do
    if MapSet.member?(visited, sequence_id) do
      acc
    else
      visited = MapSet.put(visited, sequence_id)

      case Map.get(nodes, sequence_id) do
        %{type: "sequence", parent_id: parent_id} = sequence ->
          do_sequence_chain(parent_id, nodes, visited, [sequence | acc])

        %{parent_id: parent_id} ->
          do_sequence_chain(parent_id, nodes, visited, acc)

        _missing ->
          acc
      end
    end
  end

  defp compose_visual_layers(sequences) do
    sequences
    |> Enum.with_index()
    |> Enum.flat_map(fn {sequence, depth} ->
      sequence
      |> list_value(:sequence_visual_layers)
      |> Enum.filter(&(Map.get(&1, :visible) != false))
      |> Enum.map(&composed_item(&1, sequence.id, depth))
    end)
    |> Enum.sort_by(fn %{item: layer, sequence_id: sequence_id, depth: depth} ->
      {depth, value(layer, :z_index, 0), sequence_id, value(layer, :id, 0)}
    end)
  end

  defp compose_audio_tracks(sequences) do
    sequences
    |> Enum.with_index()
    |> Enum.flat_map(fn {sequence, depth} ->
      sequence
      |> list_value(:sequence_tracks)
      |> Enum.sort_by(&{track_kind_order(&1), value(&1, :position, 0), value(&1, :id, 0)})
      |> Enum.map(&composed_item(&1, sequence.id, depth))
    end)
  end

  defp composed_item(item, sequence_id, depth) do
    %{item: item, sequence_id: sequence_id, depth: depth}
  end

  defp list_value(container, key) do
    case Map.get(container, key) do
      values when is_list(values) -> values
      _not_loaded -> []
    end
  end

  defp value(item, key, default), do: Map.get(item, key) || default

  defp track_kind_order(%{kind: "ambience"}), do: 0
  defp track_kind_order(%{kind: "music"}), do: 1
  defp track_kind_order(%{kind: "sfx"}), do: 2
  defp track_kind_order(_track), do: 3
end

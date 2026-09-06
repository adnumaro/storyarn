defmodule Storyarn.Flows.Editor.Queries.SequenceComposition do
  @moduledoc false

  import Ecto.Query

  alias Storyarn.Flows.FlowNode
  alias Storyarn.Flows.Runtime
  alias Storyarn.Flows.SequenceTrack
  alias Storyarn.Repo

  @doc false
  def inherited_visual_layer(flow_id, owner, layer_key) do
    with {:ok, composition} <- inherited_composition(flow_id, owner),
         %{layer_key: ^layer_key} = layer <-
           Enum.find(composition.visual_layers, &(&1.layer_key == layer_key)) do
      {:ok, layer}
    else
      nil -> {:error, :inherited_layer_not_found}
      {:error, _reason} = error -> error
    end
  end

  @doc false
  def inherited_audio_track(flow_id, owner, track_key) do
    with {:ok, composition} <- inherited_composition(flow_id, owner),
         %{track_key: ^track_key} = track <-
           Enum.find(composition.audio_tracks, &(&1.track_key == track_key)) do
      {:ok, track}
    else
      nil -> {:error, :inherited_track_not_found}
      {:error, _reason} = error -> error
    end
  end

  @doc false
  def inherited_or_materialized_audio_track(flow_id, owner, track_key, local) do
    case inherited_audio_track(flow_id, owner, track_key) do
      {:ok, _inherited} = result ->
        result

      {:error, :inherited_track_not_found} = not_found ->
        if complete_materialized_track?(local) do
          {:ok, %{item: local}}
        else
          not_found
        end

      {:error, _reason} = error ->
        error
    end
  end

  @doc false
  def inherited_removed_visual_layer(flow_id, owner, layer_key) do
    with {:ok, composition} <- inherited_composition_with_removed(flow_id, owner),
         %{layer_key: ^layer_key} = layer <-
           Enum.find(composition.removed_visual_layers, &(&1.layer_key == layer_key)) do
      {:ok, layer}
    else
      nil -> {:error, :sequence_visual_layer_not_found}
      {:error, _reason} = error -> error
    end
  end

  @doc false
  def inherited_removed_audio_track(flow_id, owner, track_key) do
    with {:ok, composition} <- inherited_composition_with_removed(flow_id, owner),
         %{track_key: ^track_key} = track <-
           Enum.find(composition.removed_audio_tracks, &(&1.track_key == track_key)) do
      {:ok, track}
    else
      nil -> {:error, :sequence_track_not_found}
      {:error, _reason} = error -> error
    end
  end

  defp inherited_composition(_flow_id, %FlowNode{composition_source_id: nil}),
    do: {:ok, %{visual_layers: [], audio_tracks: [], diagnostics: []}}

  defp inherited_composition(flow_id, %FlowNode{composition_source_id: source_id}) do
    composition = Runtime.compose_node_sequences(source_id, composition_nodes(flow_id))

    case composition.diagnostics do
      [] -> {:ok, composition}
      diagnostics -> {:error, {:invalid_composition_source_chain, diagnostics}}
    end
  end

  defp inherited_composition_with_removed(_flow_id, %FlowNode{composition_source_id: nil}) do
    {:ok,
     %{
       visual_layers: [],
       removed_visual_layers: [],
       audio_tracks: [],
       removed_audio_tracks: [],
       diagnostics: []
     }}
  end

  defp inherited_composition_with_removed(flow_id, %FlowNode{composition_source_id: source_id}) do
    composition = Runtime.inspect_node_sequences(source_id, composition_nodes(flow_id))

    case composition.diagnostics do
      [] -> {:ok, composition}
      diagnostics -> {:error, {:invalid_composition_source_chain, diagnostics}}
    end
  end

  defp composition_nodes(flow_id) do
    from(node in FlowNode,
      where:
        node.flow_id == ^flow_id and node.type in ["sequence", "dialogue"] and
          is_nil(node.deleted_at),
      preload: [sequence_tracks: [:asset], sequence_visual_layers: [:asset]]
    )
    |> Repo.all()
    |> Map.new(&{&1.id, &1})
  end

  defp complete_materialized_track?(%SequenceTrack{is_override: true, removed: false, overridden_fields: fields}) do
    MapSet.new(fields) == MapSet.new(SequenceTrack.property_fields())
  end

  defp complete_materialized_track?(_track), do: false
end

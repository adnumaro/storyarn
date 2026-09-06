defmodule Storyarn.Flows.Editor.Commands.SequenceLayerReorder do
  @moduledoc """
  Sets the back-to-front order of one owner's effective visual layers.

  Logical keys include hidden layers, but exclude removed layers. The complete
  set is checked under the Flow write lock, so a stale list cannot drop a
  collaborator's new layer. Ancestors and their layer rows are never changed.
  """

  import Ecto.Query

  alias Storyarn.Flows.Editor.Commands.SequenceCompositionWrite
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Flows.Runtime
  alias Storyarn.Repo

  @spec reorder(integer(), [String.t()]) :: {:ok, FlowNode.t()} | {:error, term()}
  def reorder(owner_id, layer_keys) when is_integer(owner_id) and is_list(layer_keys) do
    Repo.transaction(fn ->
      with {:ok, %{node: owner, flow: flow}} <- SequenceCompositionWrite.lock_owner(owner_id),
           composition = Runtime.compose_node_sequences(owner_id, composition_nodes(flow.id)),
           :ok <- validate_order(layer_keys, composition),
           {:ok, updated} <-
             owner
             |> Ecto.Changeset.change(data: Map.put(owner.data || %{}, "composition_layer_order", layer_keys))
             |> Repo.update() do
        updated
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def reorder(_owner_id, _layer_keys), do: {:error, :invalid_sequence_layer_order}

  defp validate_order(keys, %{diagnostics: [], visual_layers: layers}) do
    expected_keys = Enum.map(layers, & &1.layer_key)

    cond do
      not Enum.all?(keys, &is_binary/1) or length(keys) != length(Enum.uniq(keys)) ->
        {:error, :invalid_sequence_layer_order}

      MapSet.new(keys) != MapSet.new(expected_keys) ->
        {:error, :sequence_layer_order_conflict}

      true ->
        :ok
    end
  end

  defp validate_order(_keys, _composition), do: {:error, :invalid_composition_source_chain}

  defp composition_nodes(flow_id) do
    from(node in FlowNode,
      where: node.flow_id == ^flow_id and node.type in ["sequence", "dialogue"] and is_nil(node.deleted_at),
      preload: [:sequence_visual_layers, :sequence_tracks]
    )
    |> Repo.all()
    |> Map.new(&{&1.id, &1})
  end
end

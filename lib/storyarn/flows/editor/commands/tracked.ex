defmodule Storyarn.Flows.Editor.Commands.Tracked do
  @moduledoc """
  Flow editor commands that publish Editor-owned facts after success.

  Event construction remains inside the capability so presentation adapters do
  not own either the event vocabulary or its payload contract.
  """

  alias Storyarn.Flows.Editor.Events
  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Flows.NodeCrud
  alias Storyarn.Flows.NodeTypes
  alias Storyarn.Flows.SequenceCrud
  alias Storyarn.Flows.SequenceVisualLayer

  @spec create_node(term(), Flow.t(), map(), String.t()) ::
          {:ok, FlowNode.t()} | {:error, term()} | {:error, term(), term()}
  def create_node(scope, %Flow{} = flow, attrs, creation_method) do
    flow
    |> NodeCrud.create_node(attrs)
    |> tap_success(fn node -> emit_node_created(scope, flow, node, creation_method) end)
  end

  @spec duplicate_node(term(), Flow.t(), FlowNode.t()) ::
          {:ok, FlowNode.t()} | {:error, term()} | {:error, term(), term()}
  def duplicate_node(scope, %Flow{} = flow, %FlowNode{} = node) do
    if node.type in ["sequence", "dialogue"] do
      flow
      |> SequenceCrud.duplicate_composition_owner(node)
      |> tap_success(fn duplicate -> emit_node_created(scope, flow, duplicate, "duplicate") end)
    else
      attrs = %{
        type: node.type,
        position_x: node.position_x + 50.0,
        position_y: node.position_y + 50.0,
        data: NodeTypes.duplicate_data(node.type, node.data)
      }

      create_node(scope, flow, attrs, "duplicate")
    end
  end

  @spec create_sequence(term(), Flow.t(), map(), String.t()) ::
          {:ok, FlowNode.t()} | {:error, term()}
  def create_sequence(scope, %Flow{} = flow, attrs, creation_method) do
    attrs = put_default_sequence_name(attrs)

    flow.id
    |> SequenceCrud.create_sequence(attrs)
    |> tap_success(fn sequence ->
      emit_node_created(scope, flow, sequence, creation_method)
    end)
  end

  @spec wrap_selection_in_sequence(term(), Flow.t(), [integer()], map()) ::
          {:ok, FlowNode.t()} | {:error, term()}
  def wrap_selection_in_sequence(scope, %Flow{} = flow, node_ids, attrs) do
    flow
    |> SequenceCrud.wrap_selection_in_sequence(node_ids, attrs)
    |> tap_success(fn sequence ->
      emit_node_created(scope, flow, sequence, "wrap_selection")
    end)
  end

  @spec create_sequence_visual_layer(term(), Flow.t(), integer(), map()) ::
          {:ok, SequenceVisualLayer.t()} | {:error, term()}
  def create_sequence_visual_layer(scope, %Flow{} = flow, sequence_id, attrs) do
    sequence_id
    |> SequenceCrud.create_sequence_visual_layer(attrs)
    |> tap_success(fn layer ->
      emit_visual_layer(
        scope,
        flow,
        sequence_id,
        layer,
        :sequence_visual_layer_created,
        true
      )
    end)
  end

  @spec update_sequence_visual_layer(
          term(),
          Flow.t(),
          integer(),
          SequenceVisualLayer.t(),
          map()
        ) :: {:ok, SequenceVisualLayer.t()} | {:error, term()}
  def update_sequence_visual_layer(scope, %Flow{} = flow, sequence_id, layer, attrs) do
    layer
    |> SequenceCrud.update_sequence_visual_layer(attrs)
    |> tap_success(fn updated_layer ->
      emit_visual_layer(
        scope,
        flow,
        sequence_id,
        updated_layer,
        :sequence_visual_layer_updated,
        has_attr?(attrs, :asset_id)
      )
    end)
  end

  @spec upsert_sequence_track(term(), Flow.t(), integer(), String.t(), map()) ::
          {:ok, term()} | {:error, term()}
  def upsert_sequence_track(scope, %Flow{} = flow, sequence_id, kind, attrs) do
    sequence_id
    |> SequenceCrud.upsert_sequence_track(kind, attrs)
    |> tap_success(fn track ->
      Events.emit(scope, :sequence_track_updated, %{
        changed_asset: has_attr?(attrs, :asset_id),
        changed_volume: has_attr?(attrs, :volume),
        flow_id: flow.id,
        has_asset: not is_nil(track.asset_id),
        project_id: flow.project_id,
        sequence_id: sequence_id,
        track_kind: track.kind
      })
    end)
  end

  defp emit_node_created(scope, flow, node, creation_method) do
    Events.emit(scope, :node_created, %{
      creation_method: creation_method,
      flow_id: flow.id,
      has_parent: not is_nil(node.parent_id),
      node_type: node.type,
      project_id: flow.project_id
    })
  end

  defp emit_visual_layer(scope, flow, sequence_id, layer, event, changed_asset) do
    Events.emit(scope, event, %{
      changed_asset: changed_asset,
      flow_id: flow.id,
      has_asset: not is_nil(layer.asset_id),
      layer_kind: layer.kind,
      project_id: flow.project_id,
      sequence_id: sequence_id,
      slot: layer.slot
    })
  end

  defp tap_success({:ok, value} = result, callback) do
    callback.(value)
    result
  end

  defp tap_success(result, _callback), do: result

  defp has_attr?(attrs, key) do
    Map.has_key?(attrs, key) or Map.has_key?(attrs, Atom.to_string(key))
  end

  defp put_default_sequence_name(attrs) do
    if Map.has_key?(attrs, :name) or Map.has_key?(attrs, "name") do
      attrs
    else
      Map.put(attrs, "name", "Sequence")
    end
  end
end

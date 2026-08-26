defmodule Storyarn.Flows.Editor.Events do
  @moduledoc """
  Business facts produced by successful Flow editor operations.

  Editor owns the event vocabulary and payload. Platform owns the product
  reactions attached to those facts.
  """

  alias Storyarn.Flows.FlowNode
  alias Storyarn.Flows.SequenceTrack
  alias Storyarn.Flows.SequenceVisualLayer
  alias Storyarn.Platform

  @creation_methods ~w(create duplicate wrap_selection)
  @event_types [
    :node_created,
    :sequence_track_updated,
    :sequence_visual_layer_created,
    :sequence_visual_layer_updated
  ]

  @type event_type ::
          :node_created
          | :sequence_track_updated
          | :sequence_visual_layer_created
          | :sequence_visual_layer_updated

  @spec emit(term(), event_type(), map()) :: :ok
  def emit(scope_or_user, event_type, payload) when event_type in @event_types and is_map(payload) do
    if valid_payload?(event_type, payload) do
      Platform.react_to_event(scope_or_user, :flows, event_type, payload)
    else
      :ok
    end
  end

  def emit(_scope_or_user, _event_type, _payload), do: :ok

  @doc false
  @spec event_types() :: [event_type()]
  def event_types, do: @event_types

  @doc false
  @spec valid_payload?(event_type(), map()) :: boolean()
  def valid_payload?(:node_created, %{
        creation_method: creation_method,
        flow_id: flow_id,
        has_parent: has_parent,
        node_type: node_type,
        project_id: project_id
      }),
      do:
        creation_method in @creation_methods and valid_ids?(flow_id, project_id) and is_boolean(has_parent) and
          node_type in FlowNode.node_types()

  def valid_payload?(:sequence_track_updated, %{
        changed_asset: changed_asset,
        changed_volume: changed_volume,
        flow_id: flow_id,
        has_asset: has_asset,
        project_id: project_id,
        sequence_id: sequence_id,
        track_kind: track_kind
      }),
      do:
        is_boolean(changed_asset) and is_boolean(changed_volume) and valid_ids?(flow_id, project_id) and
          is_boolean(has_asset) and valid_id?(sequence_id) and track_kind in SequenceTrack.kinds()

  def valid_payload?(event_type, %{
        changed_asset: changed_asset,
        flow_id: flow_id,
        has_asset: has_asset,
        layer_kind: layer_kind,
        project_id: project_id,
        sequence_id: sequence_id,
        slot: slot
      })
      when event_type in [:sequence_visual_layer_created, :sequence_visual_layer_updated],
      do:
        is_boolean(changed_asset) and valid_ids?(flow_id, project_id) and is_boolean(has_asset) and
          layer_kind in SequenceVisualLayer.kinds() and valid_id?(sequence_id) and slot in SequenceVisualLayer.slots()

  def valid_payload?(_event_type, _payload), do: false

  defp valid_ids?(flow_id, project_id), do: valid_id?(flow_id) and valid_id?(project_id)
  defp valid_id?(id), do: is_integer(id) and id > 0
end

defmodule Storyarn.Platform.ProductMetrics do
  @moduledoc """
  Platform-owned product metric reactions and privacy allowlists.

  The source context owns the fact and its payload. This module owns the
  external metric name and the exact coarse properties that may leave Storyarn.
  """

  @behaviour Storyarn.Analytics.EventContract
  @behaviour Storyarn.Platform.EventReaction

  alias Storyarn.Analytics
  alias Storyarn.Analytics.EventContract
  alias Storyarn.Platform.EventReaction

  @creation_methods ~w(create duplicate wrap_selection)
  @flow_node_types ~w(annotation dialogue hub condition instruction jump entry exit subflow sequence)
  @sequence_track_kinds ~w(music ambience sfx)
  @visual_layer_kinds ~w(backdrop character prop overlay)
  @visual_layer_slots ~w(
    full left center right custom
    top-left top-center top-right
    middle-left middle-center middle-right
    bottom-left bottom-center bottom-right
  )

  @events %{
    {:flows, :debug_started} => {"flow debug started", ~w(flow_id project_id)},
    {:flows, :node_created} => {"flow node created", ~w(creation_method flow_id has_parent node_type project_id)},
    {:flows, :player_started} => {"flow player started", ~w(flow_id project_id)},
    {:flows, :sequence_track_updated} =>
      {"sequence track updated", ~w(changed_asset changed_volume flow_id has_asset project_id sequence_id track_kind)},
    {:flows, :sequence_visual_layer_created} =>
      {"sequence visual layer created", ~w(flow_id has_asset layer_kind project_id sequence_id slot)},
    {:flows, :sequence_visual_layer_updated} =>
      {"sequence visual layer updated", ~w(changed_asset flow_id has_asset layer_kind project_id sequence_id slot)},
    {:flows, :version_compared} => {"version compared", ~w(entity_type project_id)},
    {:flows, :version_created} => {"version created", ~w(entity_type project_id)},
    {:flows, :version_panel_opened} => {"version panel opened", ~w(entity_type project_id)},
    {:flows, :version_restored} => {"version restored", ~w(entity_type project_id)}
  }

  @impl EventReaction
  @spec handle(term(), atom(), atom(), map()) :: :ok
  def handle(scope_or_user, source, event_type, payload)
      when is_atom(source) and is_atom(event_type) and is_map(payload) do
    Analytics.track(scope_or_user, __MODULE__, {source, event_type}, payload)
  end

  def handle(_scope_or_user, _source, _event_type, _payload), do: :ok

  @doc false
  @impl EventReaction
  @spec events() :: [{atom(), atom()}]
  def events, do: @events |> Map.keys() |> Enum.sort()

  @impl EventContract
  def event(event) do
    case Map.fetch(@events, event) do
      {:ok, {name, property_keys}} -> {:ok, name, property_keys}
      :error -> :error
    end
  end

  @impl EventContract
  def sanitize(event, payload), do: sanitize_payload(event, payload)

  @doc false
  @spec sanitize_payload({atom(), atom()}, map()) :: {:ok, map()} | :error
  def sanitize_payload({:flows, event_type}, %{flow_id: flow_id, project_id: project_id} = payload)
      when event_type in [:debug_started, :player_started] do
    if valid_ids?(flow_id, project_id), do: {:ok, Map.take(payload, [:flow_id, :project_id])}, else: :error
  end

  def sanitize_payload(
        {:flows, :node_created},
        %{
          creation_method: creation_method,
          flow_id: flow_id,
          has_parent: has_parent,
          node_type: node_type,
          project_id: project_id
        } = payload
      ) do
    if creation_method in @creation_methods and valid_ids?(flow_id, project_id) and is_boolean(has_parent) and
         node_type in @flow_node_types do
      {:ok, Map.take(payload, [:creation_method, :flow_id, :has_parent, :node_type, :project_id])}
    else
      :error
    end
  end

  def sanitize_payload(
        {:flows, :sequence_track_updated},
        %{
          changed_asset: changed_asset,
          changed_volume: changed_volume,
          flow_id: flow_id,
          has_asset: has_asset,
          project_id: project_id,
          sequence_id: sequence_id,
          track_kind: track_kind
        } = payload
      ) do
    if is_boolean(changed_asset) and is_boolean(changed_volume) and valid_ids?(flow_id, project_id) and
         is_boolean(has_asset) and valid_id?(sequence_id) and track_kind in @sequence_track_kinds do
      {:ok,
       Map.take(payload, [
         :changed_asset,
         :changed_volume,
         :flow_id,
         :has_asset,
         :project_id,
         :sequence_id,
         :track_kind
       ])}
    else
      :error
    end
  end

  def sanitize_payload(
        {:flows, event_type},
        %{
          changed_asset: changed_asset,
          flow_id: flow_id,
          has_asset: has_asset,
          layer_kind: layer_kind,
          project_id: project_id,
          sequence_id: sequence_id,
          slot: slot
        } = payload
      )
      when event_type in [:sequence_visual_layer_created, :sequence_visual_layer_updated] do
    if is_boolean(changed_asset) and valid_ids?(flow_id, project_id) and is_boolean(has_asset) and
         layer_kind in @visual_layer_kinds and valid_id?(sequence_id) and slot in @visual_layer_slots do
      allowed_keys = [:flow_id, :has_asset, :layer_kind, :project_id, :sequence_id, :slot]

      allowed_keys =
        if event_type == :sequence_visual_layer_updated,
          do: [:changed_asset | allowed_keys],
          else: allowed_keys

      {:ok, Map.take(payload, allowed_keys)}
    else
      :error
    end
  end

  def sanitize_payload({:flows, event_type}, %{entity_type: "flow", project_id: project_id} = payload)
      when event_type in [:version_compared, :version_created, :version_panel_opened, :version_restored] do
    if valid_id?(project_id), do: {:ok, Map.take(payload, [:entity_type, :project_id])}, else: :error
  end

  def sanitize_payload(_event, _payload), do: :error

  defp valid_ids?(flow_id, project_id), do: valid_id?(flow_id) and valid_id?(project_id)
  defp valid_id?(id), do: is_integer(id) and id > 0
end

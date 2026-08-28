defmodule Storyarn.Flows.Runtime.Events do
  @moduledoc false

  alias Storyarn.Flows.Flow
  alias Storyarn.Platform

  @event_types [:debug_started, :player_started]

  @type event_type :: :debug_started | :player_started

  @spec emit(term(), event_type(), map()) :: :ok
  def emit(scope_or_user, event_type, payload) when event_type in @event_types and is_map(payload) do
    if valid_payload?(event_type, payload) do
      Platform.react_to_event(scope_or_user, :flows, event_type, payload)
    else
      :ok
    end
  end

  def emit(_scope_or_user, _event_type, _payload), do: :ok

  @spec debug_started(term(), Flow.t()) :: :ok
  def debug_started(scope_or_user, %Flow{} = flow) do
    emit(scope_or_user, :debug_started, %{flow_id: flow.id, project_id: flow.project_id})
  end

  @spec player_started(term(), Flow.t()) :: :ok
  def player_started(scope_or_user, %Flow{} = flow) do
    emit(scope_or_user, :player_started, %{flow_id: flow.id, project_id: flow.project_id})
  end

  @doc false
  @spec event_types() :: [event_type()]
  def event_types, do: @event_types

  @doc false
  @spec valid_payload?(event_type(), map()) :: boolean()
  def valid_payload?(event_type, %{flow_id: flow_id, project_id: project_id}) when event_type in @event_types,
    do: valid_id?(flow_id) and valid_id?(project_id)

  def valid_payload?(_event_type, _payload), do: false

  defp valid_id?(id), do: is_integer(id) and id > 0
end

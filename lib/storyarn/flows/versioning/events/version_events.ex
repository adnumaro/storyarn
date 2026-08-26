defmodule Storyarn.Flows.Versioning.Events do
  @moduledoc false

  alias Storyarn.Platform

  @event_types [:version_compared, :version_created, :version_panel_opened, :version_restored]

  @type event_type ::
          :version_compared | :version_created | :version_panel_opened | :version_restored

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
  def valid_payload?(event_type, %{entity_type: "flow", project_id: project_id}) when event_type in @event_types,
    do: is_integer(project_id) and project_id > 0

  def valid_payload?(_event_type, _payload), do: false
end

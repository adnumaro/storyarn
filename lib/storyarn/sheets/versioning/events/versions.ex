defmodule Storyarn.Sheets.Versioning.Events do
  @moduledoc false

  alias Storyarn.Platform

  @event_types [:version_compared, :version_created, :version_panel_opened, :version_restored]

  @spec emit(term(), atom(), map()) :: :ok
  def emit(scope_or_user, event_type, %{entity_type: "sheet", project_id: project_id} = payload)
      when event_type in @event_types and is_integer(project_id) and project_id > 0 do
    Platform.react_to_event(scope_or_user, :sheets, event_type, payload)
  end

  def emit(_scope_or_user, _event_type, _payload), do: :ok
end

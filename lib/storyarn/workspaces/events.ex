defmodule Storyarn.Workspaces.Events do
  @moduledoc """
  Workspace-owned business event vocabulary.

  Workspaces owns the facts and payloads. Platform owns cross-cutting
  reactions such as product metrics.
  """

  alias Storyarn.Platform
  alias Storyarn.Workspaces.Workspace

  @event_types [:workspace_created]

  @spec emit(term(), atom(), map()) :: :ok
  def emit(scope_or_user, event_type, payload) when event_type in @event_types and is_map(payload) do
    if valid_payload?(event_type, payload) do
      Platform.react_to_event(scope_or_user, :workspaces, event_type, payload)
    else
      :ok
    end
  end

  def emit(_scope_or_user, _event_type, _payload), do: :ok

  @doc "Publishes the product fact for a created workspace."
  @spec workspace_created(term(), Workspace.t()) :: :ok
  def workspace_created(scope_or_user, %Workspace{} = workspace) do
    emit(scope_or_user, :workspace_created, %{workspace_id: workspace.id})
  end

  def workspace_created(_scope_or_user, _workspace), do: :ok

  defp valid_payload?(:workspace_created, %{workspace_id: workspace_id}), do: valid_id?(workspace_id)
  defp valid_payload?(_event_type, _payload), do: false

  defp valid_id?(id), do: is_integer(id) and id > 0
end

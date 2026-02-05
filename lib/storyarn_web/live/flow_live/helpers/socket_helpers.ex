defmodule StoryarnWeb.FlowLive.Helpers.SocketHelpers do
  @moduledoc """
  Shared socket helpers for the flow editor.

  Provides common operations used across multiple handler and helper modules:
  - `reload_flow_data/1` - Refreshes flow, flow_data, and flow_hubs assigns
  - `schedule_save_status_reset/0` - Schedules the save indicator reset

  Import this module in any flow_live handler or helper that needs these.
  """

  import Phoenix.Component, only: [assign: 3]

  alias Storyarn.Flows

  @doc """
  Reloads flow data from the database and updates socket assigns.

  Refreshes `:flow`, `:flow_data`, and `:flow_hubs`.
  """
  @spec reload_flow_data(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def reload_flow_data(socket) do
    flow = Flows.get_flow!(socket.assigns.project.id, socket.assigns.flow.id)
    flow_data = Flows.serialize_for_canvas(flow)
    flow_hubs = Flows.list_hubs(flow.id)

    socket
    |> assign(:flow, flow)
    |> assign(:flow_data, flow_data)
    |> assign(:flow_hubs, flow_hubs)
  end

  @doc """
  Schedules a message to reset the save status indicator after 2 seconds.
  """
  @spec schedule_save_status_reset() :: reference()
  def schedule_save_status_reset do
    Process.send_after(self(), :reset_save_status, 2000)
  end
end

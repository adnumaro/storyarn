defmodule StoryarnWeb.FlowLive.Helpers.ConnectionHelpers do
  @moduledoc """
  Connection operation helpers for the flow editor.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3, put_flash: 3]

  alias Storyarn.Flows
  alias StoryarnWeb.FlowLive.Helpers.CollaborationHelpers

  import StoryarnWeb.FlowLive.Helpers.SocketHelpers

  # Note: FormHelpers import removed - connection forms no longer need condition fields

  @doc """
  Creates a new connection from canvas event.
  Returns {:noreply, socket} tuple.
  """
  @spec create_connection(Phoenix.LiveView.Socket.t(), map()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def create_connection(socket, %{
        "source_node_id" => source_id,
        "source_pin" => source_pin,
        "target_node_id" => target_id,
        "target_pin" => target_pin
      }) do
    attrs = %{
      source_node_id: source_id,
      target_node_id: target_id,
      source_pin: source_pin,
      target_pin: target_pin
    }

    case Flows.create_connection_with_attrs(socket.assigns.flow, attrs) do
      {:ok, conn} ->
        schedule_save_status_reset()

        connection_data = %{
          id: conn.id,
          source_node_id: source_id,
          source_pin: source_pin,
          target_node_id: target_id,
          target_pin: target_pin
        }

        {:noreply,
         socket
         |> reload_flow_data()
         |> assign(:save_status, :saved)
         |> push_event("connection_added", connection_data)
         |> CollaborationHelpers.broadcast_change(:connection_added, %{
           connection_data: connection_data
         })}

      {:error, _} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           Gettext.dgettext(StoryarnWeb.Gettext, "flows", "Could not create connection.")
         )}
    end
  end

  @doc """
  Handles connection deletion by node IDs (from canvas).
  Returns {:noreply, socket} tuple.
  """
  @spec delete_connection_by_nodes(Phoenix.LiveView.Socket.t(), any(), any()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def delete_connection_by_nodes(socket, source_id, target_id) do
    Flows.delete_connection_by_nodes(socket.assigns.flow.id, source_id, target_id)
    flow = Flows.get_flow!(socket.assigns.project.id, socket.assigns.flow.id)
    flow_data = Flows.serialize_for_canvas(flow)
    schedule_save_status_reset()

    {:noreply,
     socket
     |> assign(:flow, flow)
     |> assign(:flow_data, flow_data)
     |> assign(:save_status, :saved)
     |> CollaborationHelpers.broadcast_change(:connection_deleted, %{
       source_node_id: source_id,
       target_node_id: target_id
     })}
  end
end

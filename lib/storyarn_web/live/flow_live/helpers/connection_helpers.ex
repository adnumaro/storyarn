defmodule StoryarnWeb.FlowLive.Helpers.ConnectionHelpers do
  @moduledoc """
  Connection operation helpers for the flow editor.
  """

  import Phoenix.LiveView, only: [push_event: 3, put_flash: 3]
  import StoryarnWeb.FlowLive.Helpers.SocketHelpers
  import StoryarnWeb.Helpers.AutoSnapshot, only: [schedule: 2]
  import StoryarnWeb.Helpers.SaveStatusTimer, only: [mark_saved: 1]

  alias Phoenix.LiveView.Socket
  alias Storyarn.Collaboration
  alias Storyarn.Flows
  alias StoryarnWeb.FlowLive.Helpers.CollaborationHelpers

  # Note: FormHelpers import removed - connection forms no longer need condition fields

  @doc """
  Creates a new connection from canvas event.
  Returns {:noreply, socket} tuple.
  """
  @spec create_connection(Socket.t(), map()) ::
          {:noreply, Socket.t()}
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
        Collaboration.broadcast_dashboard_change(socket.assigns.flow.project_id, :flows)

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
         |> mark_saved()
         |> schedule(:flow)
         |> push_event("connection_added", connection_data)
         |> CollaborationHelpers.broadcast_change(:connection_added, %{
           connection_data: connection_data
         })}

      {:error, _} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           Gettext.dgettext(Storyarn.Gettext, "flows", "Could not create connection.")
         )}
    end
  end

  @doc """
  Handles connection deletion by node IDs (from canvas).
  Returns {:noreply, socket} tuple.
  """
  @spec delete_connection_by_nodes(Socket.t(), any(), any()) ::
          {:noreply, Socket.t()}
  def delete_connection_by_nodes(socket, source_id, target_id) do
    {deleted_count, _} =
      Flows.delete_connection_by_nodes(socket.assigns.flow.id, source_id, target_id)

    if deleted_count > 0 do
      Collaboration.broadcast_dashboard_change(socket.assigns.flow.project_id, :flows)
    end

    {:noreply,
     socket
     |> reload_flow_data()
     |> mark_saved()
     |> schedule(:flow)
     |> CollaborationHelpers.broadcast_change(:connection_deleted, %{
       source_node_id: source_id,
       target_node_id: target_id
     })}
  end
end

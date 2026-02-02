defmodule StoryarnWeb.FlowLive.Helpers.ConnectionHelpers do
  @moduledoc """
  Connection operation helpers for the flow editor.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3, put_flash: 3]

  alias Storyarn.Flows
  alias StoryarnWeb.FlowLive.Helpers.CollaborationHelpers
  alias StoryarnWeb.FlowLive.Helpers.FormHelpers

  @doc """
  Handles selection of a connection.
  Returns {:noreply, socket} tuple.
  """
  @spec select_connection(Phoenix.LiveView.Socket.t(), any()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def select_connection(socket, connection_id) do
    connection = Flows.get_connection!(socket.assigns.flow.id, connection_id)
    form = FormHelpers.connection_data_to_form(connection)

    {:noreply,
     socket
     |> assign(:selected_node, nil)
     |> assign(:node_form, nil)
     |> assign(:selected_connection, connection)
     |> assign(:connection_form, form)}
  end

  @doc """
  Handles deselection of a connection.
  Returns {:noreply, socket} tuple.
  """
  @spec deselect_connection(Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def deselect_connection(socket) do
    {:noreply,
     socket
     |> assign(:selected_connection, nil)
     |> assign(:connection_form, nil)
     |> push_event("deselect_connection", %{})}
  end

  @doc """
  Updates connection data (label, condition).
  Returns {:noreply, socket} tuple.
  """
  @spec update_connection_data(Phoenix.LiveView.Socket.t(), map()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def update_connection_data(socket, conn_params) do
    connection = socket.assigns.selected_connection

    case Flows.update_connection(connection, conn_params) do
      {:ok, updated_connection} ->
        schedule_save_status_reset()

        {:noreply,
         socket
         |> reload_flow_data()
         |> assign(:selected_connection, updated_connection)
         |> assign(:save_status, :saved)
         |> push_event("connection_updated", %{
           id: updated_connection.id,
           label: updated_connection.label,
           condition: updated_connection.condition
         })
         |> CollaborationHelpers.broadcast_change(:connection_updated, %{
           connection_id: updated_connection.id,
           label: updated_connection.label,
           condition: updated_connection.condition
         })}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  @doc """
  Deletes a connection.
  Returns {:noreply, socket} tuple.
  """
  @spec delete_connection(Phoenix.LiveView.Socket.t(), any()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def delete_connection(socket, connection_id) do
    connection = Flows.get_connection!(socket.assigns.flow.id, connection_id)

    case Flows.delete_connection(connection) do
      {:ok, _} ->
        {:noreply,
         socket
         |> reload_flow_data()
         |> assign(:selected_connection, nil)
         |> assign(:connection_form, nil)
         |> push_event("connection_removed", %{
           source_node_id: connection.source_node_id,
           target_node_id: connection.target_node_id
         })
         |> CollaborationHelpers.broadcast_change(:connection_deleted, %{
           source_node_id: connection.source_node_id,
           target_node_id: connection.target_node_id
         })}

      {:error, _} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           Gettext.gettext(StoryarnWeb.Gettext, "Could not delete connection.")
         )}
    end
  end

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
           Gettext.gettext(StoryarnWeb.Gettext, "Could not create connection.")
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

  # Private functions

  defp reload_flow_data(socket) do
    flow = Flows.get_flow!(socket.assigns.project.id, socket.assigns.flow.id)
    flow_data = Flows.serialize_for_canvas(flow)
    socket |> assign(:flow, flow) |> assign(:flow_data, flow_data)
  end

  defp schedule_save_status_reset do
    Process.send_after(self(), :reset_save_status, 2000)
  end
end

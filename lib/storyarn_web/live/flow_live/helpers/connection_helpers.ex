defmodule StoryarnWeb.FlowLive.Helpers.ConnectionHelpers do
  @moduledoc """
  Connection operation helpers for the flow editor.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3, put_flash: 3]
  import StoryarnWeb.FlowLive.Helpers.SocketHelpers
  import StoryarnWeb.Helpers.AutoSnapshot, only: [schedule: 2]
  import StoryarnWeb.Helpers.SaveStatusTimer, only: [mark_saved: 1]

  alias Phoenix.LiveView.Socket
  alias Storyarn.Collaboration
  alias Storyarn.Flows
  alias Storyarn.Shared.MapUtils
  alias StoryarnWeb.FlowLive.Helpers.CollaborationHelpers

  require Logger

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
  Handles precise connection deletion from a canvas event.

  Persisted connections are deleted by ID. A pin-pair fallback covers the
  short window before the server-created ID reaches the canvas.
  Returns {:noreply, socket} tuple.
  """
  @spec delete_connection(Socket.t(), map()) ::
          {:noreply, Socket.t()}
  def delete_connection(socket, params) do
    case delete_requested_connection(socket.assigns.flow.id, params) do
      {:ok, deletion_payload} ->
        Collaboration.broadcast_dashboard_change(socket.assigns.flow.project_id, :flows)

        {:noreply,
         socket
         |> reload_flow_data()
         |> mark_saved()
         |> schedule(:flow)
         |> CollaborationHelpers.broadcast_change(
           :connection_deleted,
           deletion_payload
         )}

      {:error, _reason} ->
        rejected_connection_delete(socket)
    end
  end

  @doc """
  Deletes every connection between two nodes.

  This bulk operation is retained for internal callers. Canvas events must use
  `delete_connection/2` so parallel pin connections are not collapsed.
  """
  @spec delete_connection_by_nodes(Socket.t(), any(), any()) ::
          {:noreply, Socket.t()}
  def delete_connection_by_nodes(socket, source_id, target_id) do
    case Flows.delete_connection_by_nodes(socket.assigns.flow.id, source_id, target_id) do
      {deleted_count, _result} when deleted_count > 0 ->
        Collaboration.broadcast_dashboard_change(socket.assigns.flow.project_id, :flows)

        {:noreply,
         socket
         |> reload_flow_data()
         |> mark_saved()
         |> schedule(:flow)
         |> CollaborationHelpers.broadcast_change(:connection_deleted, %{
           source_node_id: source_id,
           target_node_id: target_id
         })}

      {0, _reason} ->
        rejected_connection_delete(socket)
    end
  end

  defp delete_requested_connection(flow_id, %{"id" => connection_id}) when connection_id not in [nil, ""] do
    case Flows.delete_connection_by_id(flow_id, connection_id) do
      {:ok, connection} -> {:ok, deletion_payload(connection)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp delete_requested_connection(flow_id, %{
         "source_node_id" => source_id,
         "source_pin" => source_pin,
         "target_node_id" => target_id,
         "target_pin" => target_pin
       }) do
    case Flows.delete_connection_by_pins(
           flow_id,
           source_id,
           source_pin,
           target_id,
           target_pin
         ) do
      {1, _result} ->
        {:ok,
         %{
           id: nil,
           source_node_id: MapUtils.parse_int(source_id),
           source_pin: source_pin,
           target_node_id: MapUtils.parse_int(target_id),
           target_pin: target_pin
         }}

      {_count, reason} ->
        {:error, reason}
    end
  end

  defp delete_requested_connection(_flow_id, _params), do: {:error, :connection_identity_required}

  defp deletion_payload(connection) do
    %{
      id: connection.id,
      source_node_id: connection.source_node_id,
      source_pin: connection.source_pin,
      target_node_id: connection.target_node_id,
      target_pin: connection.target_pin
    }
  end

  defp rejected_connection_delete(socket) do
    {:noreply,
     socket
     |> resync_authoritative_flow()
     |> put_flash(
       :error,
       Gettext.dgettext(
         Storyarn.Gettext,
         "flows",
         "Could not delete connection."
       )
     )}
  end

  @doc false
  def resync_authoritative_flow(socket, reload_fun \\ &reload_flow_data/1) do
    socket =
      try do
        reload_fun.(socket)
      rescue
        Ecto.NoResultsError ->
          empty_flow_data = %{
            id: socket.assigns.flow.id,
            name: socket.assigns.flow.name,
            nodes: [],
            connections: []
          }

          socket
          |> assign(:flow_data, empty_flow_data)
          |> assign(:flow_hubs, [])
          |> assign(:flow_word_count, 0)
          |> assign(:flow_error_nodes, [])
          |> assign(:flow_warning_nodes, [])
          |> assign(:flow_info_nodes, [])

        error in [DBConnection.ConnectionError, Postgrex.Error] ->
          Logger.warning(
            "Could not resync flow #{socket.assigns.flow.id} after a rejected connection delete: " <>
              Exception.message(error)
          )

          socket
      end

    push_event(socket, "flow_updated", socket.assigns.flow_data)
  end
end

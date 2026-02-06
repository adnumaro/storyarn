defmodule StoryarnWeb.FlowLive.Helpers.NodeHelpers do
  @moduledoc """
  Node operation helpers for the flow editor.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3, put_flash: 3]
  import StoryarnWeb.FlowLive.Components.NodeTypeHelpers, only: [default_node_data: 1]

  alias Storyarn.Flows
  alias StoryarnWeb.FlowLive.Helpers.CollaborationHelpers
  alias StoryarnWeb.FlowLive.Helpers.FormHelpers

  import StoryarnWeb.FlowLive.Helpers.SocketHelpers

  @doc """
  Adds a new node to the flow.
  Returns {:noreply, socket} tuple.
  """
  @spec add_node(Phoenix.LiveView.Socket.t(), String.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def add_node(socket, type) do
    attrs = %{
      type: type,
      position_x: 100.0 + :rand.uniform(200),
      position_y: 100.0 + :rand.uniform(200),
      data: default_node_data(type)
    }

    case Flows.create_node(socket.assigns.flow, attrs) do
      {:ok, node} ->
        node_data = %{
          id: node.id,
          type: node.type,
          position: %{x: node.position_x, y: node.position_y},
          data: canvas_data(node)
        }

        {:noreply,
         socket
         |> reload_flow_data()
         |> push_event("node_added", node_data)
         |> CollaborationHelpers.broadcast_change(:node_added, %{node_data: node_data})}

      {:error, _} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           Gettext.gettext(StoryarnWeb.Gettext, "Could not create node.")
         )}
    end
  end

  @doc """
  Updates node data from form submission.
  Returns {:noreply, socket} tuple.
  """
  @spec update_node_data(Phoenix.LiveView.Socket.t(), map()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def update_node_data(socket, node_params) do
    node = socket.assigns.selected_node

    # Merge new params with existing data to preserve other fields
    merged_data = Map.merge(node.data || %{}, node_params)

    case Flows.update_node_data(node, merged_data) do
      {:ok, updated_node, %{renamed_jumps: renamed_count}} ->
        form = FormHelpers.node_data_to_form(updated_node)
        schedule_save_status_reset()

        socket =
          socket
          |> reload_flow_data()
          |> assign(:selected_node, updated_node)
          |> assign(:node_form, form)
          |> assign(:save_status, :saved)

        # Refresh referencing_jumps for hub nodes
        socket =
          if updated_node.type == "hub" do
            jumps =
              Flows.list_referencing_jumps(
                socket.assigns.flow.id,
                updated_node.data["hub_id"] || ""
              )

            assign(socket, :referencing_jumps, jumps)
          else
            socket
          end

        # Full reload when cascade happened, otherwise single node update
        socket =
          if renamed_count > 0 do
            socket
            |> put_flash(
              :info,
              Gettext.ngettext(
                StoryarnWeb.Gettext,
                "%{count} Jump node updated.",
                "%{count} Jump nodes updated.",
                renamed_count,
                count: renamed_count
              )
            )
            |> push_event("flow_updated", socket.assigns.flow_data)
          else
            push_event(socket, "node_updated", %{id: node.id, data: canvas_data(updated_node)})
          end

        {:noreply, socket}

      {:error, :hub_id_required} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           Gettext.gettext(StoryarnWeb.Gettext, "Hub ID is required.")
         )}

      {:error, :hub_id_not_unique} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           Gettext.gettext(StoryarnWeb.Gettext, "Hub ID already exists in this flow.")
         )}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  @doc """
  Duplicates a node.
  Returns {:noreply, socket} tuple.
  """
  @spec duplicate_node(Phoenix.LiveView.Socket.t(), any()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def duplicate_node(socket, node_id) do
    node = Flows.get_node!(socket.assigns.flow.id, node_id)

    # Clear hub_id when duplicating hub nodes so a new unique one is auto-generated
    data =
      if node.type == "hub" do
        Map.put(node.data, "hub_id", "")
      else
        node.data
      end

    attrs = %{
      type: node.type,
      position_x: node.position_x + 50.0,
      position_y: node.position_y + 50.0,
      data: data
    }

    case Flows.create_node(socket.assigns.flow, attrs) do
      {:ok, new_node} ->
        node_data = %{
          id: new_node.id,
          type: new_node.type,
          position: %{x: new_node.position_x, y: new_node.position_y},
          data: canvas_data(new_node)
        }

        {:noreply,
         socket
         |> reload_flow_data()
         |> push_event("node_added", node_data)
         |> CollaborationHelpers.broadcast_change(:node_added, %{node_data: node_data})}

      {:error, _} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           Gettext.gettext(StoryarnWeb.Gettext, "Could not duplicate node.")
         )}
    end
  end

  @doc """
  Updates a node's text content (from TipTap editor).
  Returns {:noreply, socket} tuple.
  """
  @spec update_node_text(Phoenix.LiveView.Socket.t(), any(), String.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def update_node_text(socket, node_id, content) do
    node = Flows.get_node!(socket.assigns.flow.id, node_id)
    updated_data = Map.put(node.data, "text", content)

    case Flows.update_node_data(node, updated_data) do
      {:ok, updated_node, _meta} ->
        schedule_save_status_reset()

        socket =
          socket
          |> reload_flow_data()
          |> assign(:save_status, :saved)
          |> maybe_update_selected_node(node, updated_node)
          |> push_event("node_updated", %{id: node.id, data: canvas_data(updated_node)})

        {:noreply, socket}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  @doc """
  Deletes a node, checking for locks first.
  Returns {:noreply, socket} tuple.
  """
  @spec delete_node(Phoenix.LiveView.Socket.t(), any()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def delete_node(socket, node_id) do
    if CollaborationHelpers.node_locked_by_other?(socket, node_id) do
      {:noreply,
       Phoenix.LiveView.put_flash(
         socket,
         :error,
         Gettext.gettext(StoryarnWeb.Gettext, "This node is being edited by another user.")
       )}
    else
      perform_node_deletion(socket, node_id)
    end
  end

  @doc """
  Updates a single field in a node's data map.
  Returns {:noreply, socket} tuple.
  """
  @spec update_node_field(Phoenix.LiveView.Socket.t(), any(), String.t(), any()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def update_node_field(socket, node_id, field, value) do
    node = Flows.get_node!(socket.assigns.flow.id, node_id)
    updated_data = Map.put(node.data, field, value)

    case Flows.update_node_data(node, updated_data) do
      {:ok, updated_node, _meta} ->
        form = FormHelpers.node_data_to_form(updated_node)
        schedule_save_status_reset()

        {:noreply,
         socket
         |> reload_flow_data()
         |> assign(:selected_node, updated_node)
         |> assign(:node_form, form)
         |> assign(:save_status, :saved)
         |> push_event("node_updated", %{id: node_id, data: canvas_data(updated_node)})}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  # Private functions

  # Resolves node data for canvas events (e.g., hub color name → hex).
  defp canvas_data(node) do
    Flows.resolve_node_colors(node.type, node.data)
  end

  defp maybe_update_selected_node(socket, original_node, updated_node) do
    if socket.assigns.selected_node && socket.assigns.selected_node.id == original_node.id do
      form = FormHelpers.node_data_to_form(updated_node)

      socket
      |> assign(:selected_node, updated_node)
      |> assign(:node_form, form)
    else
      socket
    end
  end

  defp perform_node_deletion(socket, node_id) do
    node = Flows.get_node!(socket.assigns.flow.id, node_id)

    case Flows.delete_node(node) do
      {:ok, _, %{orphaned_jumps: count}} when count > 0 ->
        socket = reload_flow_data(socket)
        flow_data = socket.assigns.flow_data

        {:noreply,
         socket
         |> assign(:selected_node, nil)
         |> assign(:node_form, nil)
         |> put_flash(
           :warning,
           Gettext.ngettext(
             StoryarnWeb.Gettext,
             "%{count} Jump node lost its target.",
             "%{count} Jump nodes lost their target.",
             count,
             count: count
           )
         )
         |> push_event("flow_updated", flow_data)
         |> CollaborationHelpers.broadcast_change(:flow_refresh, %{node_id: node_id})}

      {:ok, _, _meta} ->
        socket = reload_flow_data(socket)

        {:noreply,
         socket
         |> assign(:selected_node, nil)
         |> assign(:node_form, nil)
         |> push_event("node_removed", %{id: node_id})
         |> CollaborationHelpers.broadcast_change(:node_deleted, %{node_id: node_id})}

      {:error, _} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           Gettext.gettext(StoryarnWeb.Gettext, "Could not delete node.")
         )}
    end
  end
end

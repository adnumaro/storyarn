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
          data: node.data
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
      {:ok, updated_node} ->
        form = FormHelpers.node_data_to_form(updated_node)
        schedule_save_status_reset()

        {:noreply,
         socket
         |> reload_flow_data()
         |> assign(:selected_node, updated_node)
         |> assign(:node_form, form)
         |> assign(:save_status, :saved)
         |> push_event("node_updated", %{id: node.id, data: updated_node.data})}

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

    attrs = %{
      type: node.type,
      position_x: node.position_x + 50.0,
      position_y: node.position_y + 50.0,
      data: node.data
    }

    case Flows.create_node(socket.assigns.flow, attrs) do
      {:ok, new_node} ->
        node_data = %{
          id: new_node.id,
          type: new_node.type,
          position: %{x: new_node.position_x, y: new_node.position_y},
          data: new_node.data
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
  Adds a response to a dialogue node.
  Returns {:noreply, socket} tuple.
  """
  @spec add_response(Phoenix.LiveView.Socket.t(), any()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def add_response(socket, node_id) do
    node = Flows.get_node!(socket.assigns.flow.id, node_id)
    responses = node.data["responses"] || []

    new_id = "r#{length(responses) + 1}_#{:erlang.unique_integer([:positive])}"
    new_response = %{"id" => new_id, "text" => "", "condition" => nil}
    updated_data = Map.put(node.data, "responses", responses ++ [new_response])

    case Flows.update_node_data(node, updated_data) do
      {:ok, updated_node} ->
        form = FormHelpers.node_data_to_form(updated_node)
        schedule_save_status_reset()

        {:noreply,
         socket
         |> reload_flow_data()
         |> assign(:selected_node, updated_node)
         |> assign(:node_form, form)
         |> assign(:save_status, :saved)
         |> push_event("node_updated", %{id: node_id, data: updated_node.data})}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  @doc """
  Removes a response from a dialogue node.
  Returns {:noreply, socket} tuple.
  """
  @spec remove_response(Phoenix.LiveView.Socket.t(), any(), String.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def remove_response(socket, node_id, response_id) do
    node = Flows.get_node!(socket.assigns.flow.id, node_id)
    responses = node.data["responses"] || []
    updated_responses = Enum.reject(responses, fn r -> r["id"] == response_id end)
    updated_data = Map.put(node.data, "responses", updated_responses)

    case Flows.update_node_data(node, updated_data) do
      {:ok, updated_node} ->
        form = FormHelpers.node_data_to_form(updated_node)
        schedule_save_status_reset()

        {:noreply,
         socket
         |> reload_flow_data()
         |> assign(:selected_node, updated_node)
         |> assign(:node_form, form)
         |> assign(:save_status, :saved)
         |> push_event("node_updated", %{id: node_id, data: updated_node.data})}

      {:error, _} ->
        {:noreply, socket}
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
      {:ok, updated_node} ->
        flow = Flows.get_flow!(socket.assigns.project.id, socket.assigns.flow.id)
        flow_data = Flows.serialize_for_canvas(flow)
        schedule_save_status_reset()

        socket =
          socket
          |> assign(:flow, flow)
          |> assign(:flow_data, flow_data)
          |> assign(:save_status, :saved)
          |> maybe_update_selected_node(node, updated_node)

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
      {:ok, updated_node} ->
        form = FormHelpers.node_data_to_form(updated_node)
        schedule_save_status_reset()

        {:noreply,
         socket
         |> reload_flow_data()
         |> assign(:selected_node, updated_node)
         |> assign(:node_form, form)
         |> assign(:save_status, :saved)
         |> push_event("node_updated", %{id: node_id, data: updated_node.data})}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  @doc """
  Updates a response field (text or condition) in a dialogue node.
  Returns {:noreply, socket} tuple.
  """
  @spec update_response_field(Phoenix.LiveView.Socket.t(), any(), String.t(), String.t(), any()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def update_response_field(socket, node_id, response_id, field, value) do
    node = Flows.get_node!(socket.assigns.flow.id, node_id)
    responses = node.data["responses"] || []

    updated_responses = update_response_in_list(responses, response_id, field, value)
    updated_data = Map.put(node.data, "responses", updated_responses)

    case Flows.update_node_data(node, updated_data) do
      {:ok, updated_node} ->
        flow = Flows.get_flow!(socket.assigns.project.id, socket.assigns.flow.id)
        flow_data = Flows.serialize_for_canvas(flow)
        form = FormHelpers.node_data_to_form(updated_node)
        schedule_save_status_reset()

        {:noreply,
         socket
         |> assign(:flow, flow)
         |> assign(:flow_data, flow_data)
         |> assign(:selected_node, updated_node)
         |> assign(:node_form, form)
         |> assign(:save_status, :saved)
         |> push_event("node_updated", %{id: node_id, data: updated_node.data})}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  # Private functions

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
      {:ok, _} ->
        flow = Flows.get_flow!(socket.assigns.project.id, socket.assigns.flow.id)
        flow_data = Flows.serialize_for_canvas(flow)

        {:noreply,
         socket
         |> assign(:flow, flow)
         |> assign(:flow_data, flow_data)
         |> assign(:selected_node, nil)
         |> assign(:node_form, nil)
         |> push_event("node_removed", %{id: node_id})
         |> CollaborationHelpers.broadcast_change(:node_deleted, %{node_id: node_id})}

      {:error, _} ->
        {:noreply,
         Phoenix.LiveView.put_flash(
           socket,
           :error,
           Gettext.gettext(StoryarnWeb.Gettext, "Could not delete node.")
         )}
    end
  end

  defp update_response_in_list(responses, response_id, field, value) do
    Enum.map(responses, fn r ->
      if r["id"] == response_id, do: Map.put(r, field, value), else: r
    end)
  end

  defp reload_flow_data(socket) do
    flow = Flows.get_flow!(socket.assigns.project.id, socket.assigns.flow.id)
    flow_data = Flows.serialize_for_canvas(flow)
    flow_hubs = Flows.list_hubs(flow.id)

    socket
    |> assign(:flow, flow)
    |> assign(:flow_data, flow_data)
    |> assign(:flow_hubs, flow_hubs)
  end

  defp schedule_save_status_reset do
    Process.send_after(self(), :reset_save_status, 2000)
  end
end

defmodule StoryarnWeb.FlowLive.Helpers.NodeHelpers do
  @moduledoc """
  Node operation helpers for the flow editor.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3, put_flash: 3]
  import StoryarnWeb.FlowLive.Components.NodeTypeHelpers, only: [default_node_data: 1]

  alias Storyarn.Flows
  alias Storyarn.Flows.FlowNode
  alias StoryarnWeb.FlowLive.Helpers.CollaborationHelpers
  alias StoryarnWeb.FlowLive.Helpers.FormHelpers
  alias StoryarnWeb.FlowLive.NodeTypeRegistry

  import StoryarnWeb.FlowLive.Helpers.SocketHelpers

  @doc """
  Single canonical path for all node data updates.

  Always reads fresh from DB (never from socket assigns), applies the caller's
  transform function, writes to DB, reloads flow data, and pushes to canvas.

  ## Parameters

    * `socket` - The LiveView socket
    * `node_id` - The database ID of the node to update
    * `update_fn` - A function `(current_data :: map()) -> new_data :: map()`

  ## Returns

    `{:noreply, socket}` — ready for direct return from a handle_event/handle_info.
  """
  @spec persist_node_update(Phoenix.LiveView.Socket.t(), any(), (map() -> map())) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def persist_node_update(socket, node_id, update_fn) do
    # 1. ALWAYS read fresh from DB (never from socket.assigns.selected_node)
    node = Flows.get_node!(socket.assigns.flow.id, node_id)
    old_data = node.data || %{}

    # 2. Apply caller's transform
    new_data = update_fn.(old_data)

    # 3. Write to DB
    case Flows.update_node_data(node, new_data) do
      {:ok, updated_node, %{renamed_jumps: renamed_count}} ->
        form = FormHelpers.node_data_to_form(updated_node)
        schedule_save_status_reset()

        socket =
          socket
          |> reload_flow_data()
          |> assign(:selected_node, updated_node)
          |> assign(:node_form, form)
          |> assign(:save_status, :saved)
          |> maybe_refresh_referencing_jumps(updated_node)
          |> push_node_or_flow_update(updated_node, renamed_count)

        # Push undo snapshot only when no cascade occurred.
        # Hub rename cascade triggers flow_updated → history.clear() anyway.
        socket =
          if renamed_count == 0 do
            push_event(socket, "node_data_changed", %{
              id: node_id,
              prev_data: old_data,
              new_data: new_data
            })
          else
            socket
          end

        {:noreply, socket}

      {:error, :hub_id_required} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           Gettext.dgettext(StoryarnWeb.Gettext, "flows", "Hub ID is required.")
         )}

      {:error, :hub_id_not_unique} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           Gettext.dgettext(StoryarnWeb.Gettext, "flows", "Hub ID already exists in this flow.")
         )}

      {:error, _} ->
        {:noreply, socket}
    end
  end

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
         |> push_event("node_added", Map.put(node_data, :self, true))
         |> CollaborationHelpers.broadcast_change(:node_added, %{node_data: node_data})}

      {:error, _} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           Gettext.dgettext(StoryarnWeb.Gettext, "flows", "Could not create node.")
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
    node_id = socket.assigns.selected_node.id
    normalized_params = normalize_form_params(node_params)

    persist_node_update(socket, node_id, fn data ->
      Map.merge(data, normalized_params)
    end)
  end

  @doc """
  Duplicates a node.
  Returns {:noreply, socket} tuple.
  """
  @spec duplicate_node(Phoenix.LiveView.Socket.t(), any()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def duplicate_node(socket, node_id) do
    node = Flows.get_node!(socket.assigns.flow.id, node_id)

    # Delegate unique identifier cleanup to per-type module
    data = NodeTypeRegistry.duplicate_data_cleanup(node.type, node.data)

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
         |> push_event("node_added", Map.put(node_data, :self, true))
         |> CollaborationHelpers.broadcast_change(:node_added, %{node_data: node_data})}

      {:error, _} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           Gettext.dgettext(StoryarnWeb.Gettext, "flows", "Could not duplicate node.")
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
    persist_node_update(socket, node_id, fn data ->
      Map.put(data, "text", content)
    end)
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
         Gettext.dgettext(StoryarnWeb.Gettext, "flows", "This node is being edited by another user.")
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
    persist_node_update(socket, node_id, fn data ->
      Map.put(data, field, value)
    end)
  end

  # Private functions

  # Resolves node data for canvas events (e.g., hub color name → hex).
  # Also used by persist_node_update and add_node.
  defp canvas_data(node) do
    Flows.resolve_node_colors(node.type, node.data)
  end

  # Pushes a full flow update when hub renames cascaded, otherwise a single node update.
  defp push_node_or_flow_update(socket, _node, renamed_count) when renamed_count > 0 do
    socket
    |> put_flash(
      :info,
      Gettext.dngettext(StoryarnWeb.Gettext, "flows",
        "%{count} Jump node updated.",
        "%{count} Jump nodes updated.",
        renamed_count,
        count: renamed_count
      )
    )
    |> push_event("flow_updated", socket.assigns.flow_data)
  end

  defp push_node_or_flow_update(socket, node, _renamed_count) do
    push_event(socket, "node_updated", %{id: node.id, data: canvas_data(node)})
  end

  # Refreshes referencing_jumps assign for hub nodes.
  defp maybe_refresh_referencing_jumps(socket, %{type: "hub"} = node) do
    jumps =
      Flows.list_referencing_jumps(
        socket.assigns.flow.id,
        node.data["hub_id"] || ""
      )

    assign(socket, :referencing_jumps, jumps)
  end

  defp maybe_refresh_referencing_jumps(socket, _node), do: socket

  # Normalizes empty strings to nil for ID fields that should be nullable.
  @doc false
  def normalize_form_params(params) do
    params
    |> normalize_empty_to_nil("speaker_sheet_id")
    |> normalize_empty_to_nil("audio_asset_id")
  end

  defp normalize_empty_to_nil(params, key) do
    case params[key] do
      "" -> Map.put(params, key, nil)
      _ -> params
    end
  end

  @doc """
  Restores a soft-deleted node and its valid connections.
  Returns {:noreply, socket} tuple.
  """
  @spec restore_node(Phoenix.LiveView.Socket.t(), any()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def restore_node(socket, node_id) do
    case Flows.restore_node(socket.assigns.flow.id, node_id) do
      {:ok, %FlowNode{} = node} ->
        socket = reload_flow_data(socket)
        {node_data, connections} = build_restored_node_payload(socket, node)

        {:noreply,
         socket
         |> push_event("node_restored", %{node: node_data, connections: connections})
         |> CollaborationHelpers.broadcast_change(:node_restored, %{
           node_data: node_data,
           connections: connections
         })}

      {:ok, :already_active} ->
        {:noreply, socket}

      {:error, _} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           Gettext.dgettext(StoryarnWeb.Gettext, "flows", "Could not restore node.")
         )}
    end
  end

  @doc """
  Restores a node's data to a specific snapshot (for undo/redo).
  Pushes node_updated (NOT node_data_changed) to avoid feedback loops.
  """
  @spec restore_node_data(Phoenix.LiveView.Socket.t(), any(), map()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def restore_node_data(socket, node_id, data) do
    node = Flows.get_node!(socket.assigns.flow.id, node_id)

    case Flows.update_node_data(node, data) do
      {:ok, updated_node, _meta} ->
        form = FormHelpers.node_data_to_form(updated_node)
        schedule_save_status_reset()

        {:noreply,
         socket
         |> reload_flow_data()
         |> assign(:selected_node, updated_node)
         |> assign(:node_form, form)
         |> assign(:save_status, :saved)
         |> maybe_refresh_referencing_jumps(updated_node)
         |> push_event("node_updated", %{id: node_id, data: canvas_data(updated_node)})}

      {:error, :hub_id_required} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           Gettext.dgettext(StoryarnWeb.Gettext, "flows", "Hub ID is required.")
         )}

      {:error, :hub_id_not_unique} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           Gettext.dgettext(StoryarnWeb.Gettext, "flows", "Hub ID already exists in this flow.")
         )}

      {:error, _} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           Gettext.dgettext(StoryarnWeb.Gettext, "flows", "Could not restore node data.")
         )}
    end
  end

  defp build_restored_node_payload(socket, node) do
    node_data = %{
      id: node.id,
      type: node.type,
      position: %{x: node.position_x, y: node.position_y},
      data: canvas_data(node)
    }

    # Use flow_data.connections (already serialized by reload_flow_data)
    # and filter to connections involving this node where both endpoints are active.
    active_node_ids = socket.assigns.flow_data.nodes |> Enum.map(& &1.id) |> MapSet.new()

    connections =
      socket.assigns.flow_data.connections
      |> Enum.filter(fn c ->
        (c.source_node_id == node.id or c.target_node_id == node.id) and
          MapSet.member?(active_node_ids, c.source_node_id) and
          MapSet.member?(active_node_ids, c.target_node_id)
      end)

    {node_data, connections}
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
           Gettext.dngettext(StoryarnWeb.Gettext, "flows",
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
         |> push_event("node_removed", %{id: node_id, self: true})
         |> CollaborationHelpers.broadcast_change(:node_deleted, %{node_id: node_id})}

      {:error, :cannot_delete_entry_node} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           Gettext.dgettext(StoryarnWeb.Gettext, "flows", "The Entry node cannot be deleted.")
         )}

      {:error, :cannot_delete_last_exit} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           Gettext.dgettext(StoryarnWeb.Gettext, "flows", "A flow must have at least one Exit node.")
         )}

      {:error, _} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           Gettext.dgettext(StoryarnWeb.Gettext, "flows", "Could not delete node.")
         )}
    end
  end
end

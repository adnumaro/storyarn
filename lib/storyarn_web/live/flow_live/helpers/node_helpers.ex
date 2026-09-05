defmodule StoryarnWeb.FlowLive.Helpers.NodeHelpers do
  @moduledoc """
  Node operation helpers for the flow editor.
  """

  use Gettext, backend: Storyarn.Gettext

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3, put_flash: 3]
  import StoryarnWeb.FlowLive.Helpers.SocketHelpers
  import StoryarnWeb.Helpers.AutoSnapshot, only: [schedule: 2]
  import StoryarnWeb.Helpers.SaveStatusTimer, only: [mark_saved: 1]

  alias Phoenix.LiveView.Socket
  alias Storyarn.Flows
  alias StoryarnWeb.FlowLive.Helpers.CollaborationHelpers
  alias StoryarnWeb.FlowLive.Helpers.FormHelpers
  alias StoryarnWeb.FlowLive.Helpers.SequencePresentation

  @doc """
  Single canonical path for all node data updates.

  Web passes a closed Flow operation and its payload. Flows locks and reloads
  the node before deriving the transition, then returns the before/after data
  needed by the transport adapter.

  ## Parameters

    * `socket` - The LiveView socket
    * `node_id` - The database ID of the node to update
    * `operation` - an operation owned by `Storyarn.Flows.NodeEditor`
    * `payload` - the operation's typed input

  ## Returns

    `{:noreply, socket}` — ready for direct return from a handle_event/handle_info.
  """
  @spec persist_node_update(Socket.t(), any(), atom(), map()) ::
          {:noreply, Socket.t()}
  def persist_node_update(socket, node_id, operation, payload \\ %{}) do
    case Flows.edit_node(socket.assigns.flow.id, node_id, operation, payload) do
      {:ok, %{changed?: false}} ->
        {:noreply, socket}

      {:ok, result} ->
        updated_node = result.node
        renamed_count = result.renamed_jumps
        connections_changed? = result.connections_changed?
        full_refresh? = result.graph_changed?
        form = FormHelpers.node_data_to_form(updated_node)

        socket =
          socket
          |> reload_flow_data()
          |> assign(:selected_node, updated_node)
          |> assign(:node_form, form)
          |> mark_saved()
          |> schedule(:flow)
          |> maybe_refresh_referencing_jumps(updated_node)
          |> push_node_or_flow_update(
            updated_node,
            renamed_count,
            connections_changed?
          )
          |> maybe_refresh_dialogue_panel(updated_node)
          |> maybe_refresh_sequence_stage(updated_node)

        # Broadcast node data change to other users
        socket =
          if full_refresh? do
            # Hub cascades and pin reconciliation both mutate more than one row.
            CollaborationHelpers.broadcast_change(socket, :flow_refresh, %{})
          else
            CollaborationHelpers.broadcast_change(socket, :node_updated, %{
              node_id: updated_node.id,
              node_data: canvas_data(updated_node, socket.assigns.flow.project_id)
            })
          end

        # Full graph mutations trigger flow_updated → history.clear(); a
        # node-only undo snapshot could not recreate deleted connections.
        socket =
          if full_refresh? do
            socket
          else
            push_event(socket, "node_data_changed", %{
              id: node_id,
              prev_data: result.previous_data,
              new_data: result.current_data
            })
          end

        {:noreply, socket}

      {:error, :hub_id_required} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           Gettext.dgettext(Storyarn.Gettext, "flows", "Hub ID is required.")
         )}

      {:error, :hub_id_not_unique} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           Gettext.dgettext(Storyarn.Gettext, "flows", "Hub ID already exists in this flow.")
         )}

      {:error, reason}
      when reason in [:invalid_flow_reference, :self_reference, :circular_reference, :flow_not_found] ->
        {:noreply, put_node_operation_error(socket, operation, reason)}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  @doc """
  Adds a new node to the flow.
  Returns {:noreply, socket} tuple.
  """
  @spec add_node(Socket.t(), String.t(), keyword()) ::
          {:noreply, Socket.t()}
  def add_node(socket, type, opts \\ [])

  def add_node(socket, "sequence", opts) do
    {pos_x, pos_y} = node_position(opts)

    attrs = maybe_put_parent_id(%{"position_x" => pos_x, "position_y" => pos_y}, opts)

    case Flows.create_editor_sequence(
           socket.assigns.current_scope,
           socket.assigns.flow,
           attrs,
           "create"
         ) do
      {:ok, node} ->
        node_data = Flows.serialize_editor_node(node, socket.assigns.flow.project_id)

        {:noreply,
         socket
         |> reload_flow_data()
         |> schedule(:flow)
         |> push_event("node_added", Map.put(node_data, :self, true))
         |> CollaborationHelpers.broadcast_change(:node_added, %{node_data: node_data})}

      {:error, _} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("flows", "Could not create sequence")
         )}
    end
  end

  def add_node(socket, type, opts) do
    {pos_x, pos_y} = node_position(opts)

    attrs =
      maybe_put_parent_id(
        %{type: type, position_x: pos_x, position_y: pos_y, data: Flows.default_node_data(type)},
        opts
      )

    case Flows.create_editor_node(
           socket.assigns.current_scope,
           socket.assigns.flow,
           attrs,
           "create"
         ) do
      {:ok, node} ->
        node_data = Flows.serialize_editor_node(node, socket.assigns.flow.project_id)

        {:noreply,
         socket
         |> reload_flow_data()
         |> schedule(:flow)
         |> push_event("node_added", Map.put(node_data, :self, true))
         |> CollaborationHelpers.broadcast_change(:node_added, %{node_data: node_data})}

      {:error, :limit_reached, _details} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("Item limit reached for your plan")
         )}

      {:error, _} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("flows", "Could not create node.")
         )}
    end
  end

  @doc """
  Updates node data from form submission.
  Returns {:noreply, socket} tuple.
  """
  @spec update_node_data(Socket.t(), map()) ::
          {:noreply, Socket.t()}
  def update_node_data(socket, node_params) do
    if is_nil(socket.assigns.selected_node),
      do: {:noreply, socket},
      else: do_update_node_data(socket, node_params)
  end

  defp do_update_node_data(socket, node_params) do
    node_id = socket.assigns.selected_node.id

    persist_node_update(socket, node_id, :merge_form, %{params: node_params})
  end

  @doc """
  Duplicates a node.
  Returns {:noreply, socket} tuple.
  """
  @spec duplicate_node(Socket.t(), any()) ::
          {:noreply, Socket.t()}
  def duplicate_node(socket, node_id) do
    node = Flows.get_node!(socket.assigns.flow.id, node_id)

    case Flows.duplicate_editor_node(socket.assigns.current_scope, socket.assigns.flow, node) do
      {:ok, new_node} ->
        node_data = Flows.serialize_editor_node(new_node, socket.assigns.flow.project_id)

        {:noreply,
         socket
         |> reload_flow_data()
         |> schedule(:flow)
         |> push_event("node_added", Map.put(node_data, :self, true))
         |> CollaborationHelpers.broadcast_change(:node_added, %{node_data: node_data})}

      {:error, :limit_reached, _details} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("Item limit reached for your plan")
         )}

      {:error, _} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("flows", "Could not duplicate node.")
         )}
    end
  end

  @doc """
  Updates a node's text content (from TipTap editor).
  Returns {:noreply, socket} tuple.
  """
  @spec update_node_text(Socket.t(), any(), String.t()) ::
          {:noreply, Socket.t()}
  def update_node_text(socket, node_id, content) do
    persist_node_update(socket, node_id, :put_field, %{field: "text", value: content})
  end

  @doc """
  Deletes a node, checking for locks first.
  Returns {:noreply, socket} tuple.
  """
  @spec delete_node(Socket.t(), any()) ::
          {:noreply, Socket.t()}
  def delete_node(socket, node_id) do
    if CollaborationHelpers.node_locked_by_other?(socket, node_id) do
      {:noreply,
       Phoenix.LiveView.put_flash(
         socket,
         :error,
         Gettext.dgettext(
           Storyarn.Gettext,
           "flows",
           "This node is being edited by another user."
         )
       )}
    else
      perform_node_deletion(socket, node_id)
    end
  end

  @doc """
  Updates a single field in a node's data map.
  Returns {:noreply, socket} tuple.
  """
  @spec update_node_field(Socket.t(), any(), String.t(), any()) ::
          {:noreply, Socket.t()}
  def update_node_field(socket, node_id, field, value) do
    persist_node_update(socket, node_id, :put_field, %{field: field, value: value})
  end

  # Private functions

  defp node_position(opts) do
    case Keyword.get(opts, :position) do
      {x, y} -> {x * 1.0, y * 1.0}
      _ -> {100.0 + :rand.uniform(200), 100.0 + :rand.uniform(200)}
    end
  end

  defp maybe_put_parent_id(attrs, opts) do
    case Keyword.get(opts, :parent_id) do
      parent_id when is_integer(parent_id) -> Map.put(attrs, :parent_id, parent_id)
      _ -> attrs
    end
  end

  # Web keeps the event envelope; Flows owns the node projection itself.
  defp canvas_data(node, project_id) do
    node
    |> Flows.serialize_editor_node(project_id)
    |> Map.fetch!(:data)
  end

  defp maybe_refresh_sequence_stage(socket, %{type: type, id: node_id}) when type in ["sequence", "dialogue"] do
    graph = Flows.load_runtime_graph(socket.assigns.flow.id)
    speakers_map = FormHelpers.player_speakers_map(socket.assigns.all_sheets)

    assign(
      socket,
      :sequence_stage,
      SequencePresentation.stage(
        node_id,
        graph.nodes,
        speakers_map,
        socket.assigns.project.id,
        nil,
        SequencePresentation.locale_context(socket.assigns)
      )
    )
  end

  defp maybe_refresh_sequence_stage(socket, _node), do: socket

  # Pushes a full flow update for graph-wide mutations, otherwise a single node update.
  defp push_node_or_flow_update(socket, _node, renamed_count, _connections_changed?) when renamed_count > 0 do
    socket
    |> put_flash(
      :info,
      Gettext.dngettext(
        Storyarn.Gettext,
        "flows",
        "%{count} Jump node updated.",
        "%{count} Jump nodes updated.",
        renamed_count,
        count: renamed_count
      )
    )
    |> push_event("flow_updated", socket.assigns.flow_data)
  end

  defp push_node_or_flow_update(socket, _node, _renamed_count, true) do
    push_event(socket, "flow_updated", socket.assigns.flow_data)
  end

  defp push_node_or_flow_update(socket, node, _renamed_count, false) do
    push_event(socket, "node_updated", %{
      id: node.id,
      data: canvas_data(node, socket.assigns.flow.project_id)
    })
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

  # Rebuilds `:dialogue_panel_data` after every dialogue write so the panel
  # reflects field updates (response add/remove/edit, condition / instruction
  # builder writes, etc.). Only fires when the just-updated node is the one
  # the panel is currently bound to — otherwise leaves the assign untouched.
  defp maybe_refresh_dialogue_panel(socket, %{type: "dialogue", id: id} = node) do
    sel = socket.assigns[:selected_node]

    if sel && sel.id == id do
      assign(
        socket,
        :dialogue_panel_data,
        StoryarnWeb.FlowLive.Handlers.GenericNodeHandlers.build_dialogue_panel_data(socket, node)
      )
    else
      socket
    end
  end

  defp maybe_refresh_dialogue_panel(socket, _node), do: socket

  defp put_node_operation_error(socket, :put_exit_flow_reference, :self_reference) do
    put_flash(socket, :error, dgettext("flows", "Cannot reference the current flow."))
  end

  defp put_node_operation_error(socket, :put_subflow_reference, :self_reference) do
    put_flash(socket, :error, dgettext("flows", "A flow cannot reference itself."))
  end

  defp put_node_operation_error(socket, :put_subflow_reference, :circular_reference) do
    put_flash(
      socket,
      :error,
      dgettext(
        "flows",
        "Circular reference detected. This flow is already referenced by the target."
      )
    )
  end

  defp put_node_operation_error(socket, _operation, :circular_reference) do
    put_flash(socket, :error, dgettext("flows", "This would create a circular reference."))
  end

  defp put_node_operation_error(socket, _operation, :flow_not_found) do
    put_flash(socket, :error, dgettext("flows", "Flow not found."))
  end

  defp put_node_operation_error(socket, _operation, :invalid_flow_reference) do
    put_flash(socket, :error, dgettext("flows", "Invalid flow reference."))
  end

  @doc """
  Restores a soft-deleted node and its valid connections.
  Returns {:noreply, socket} tuple.
  """
  @spec restore_node(Socket.t(), any()) ::
          {:noreply, Socket.t()}
  def restore_node(socket, node_id) do
    case Flows.restore_editor_node(socket.assigns.flow, node_id) do
      {:ok, %{node: %{id: restored_node_id} = node_data, connections: connections}}
      when is_integer(restored_node_id) ->
        {:noreply,
         socket
         |> reload_flow_data()
         |> push_event("node_restored", %{node: node_data, connections: connections})
         |> CollaborationHelpers.broadcast_change(:node_restored, %{
           node_data: node_data,
           connections: connections
         })}

      {:ok, :already_active} ->
        {:noreply, socket}

      {:error, :inactive_composition_source} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           Gettext.dgettext(
             Storyarn.Gettext,
             "flows",
             "This node cannot be restored while its sequence composition source is in the trash."
           )
         )}

      {:error, _} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           Gettext.dgettext(Storyarn.Gettext, "flows", "Could not restore node.")
         )}
    end
  end

  @doc """
  Restores a node's data to a specific snapshot (for undo/redo).
  Pushes node_updated (NOT node_data_changed) to avoid feedback loops.
  """
  @spec restore_node_data(Socket.t(), any(), map()) ::
          {:noreply, Socket.t()}
  def restore_node_data(socket, node_id, data) do
    case Flows.edit_node(socket.assigns.flow.id, node_id, :restore_data, %{data: data}) do
      {:ok, result} ->
        updated_node = result.node
        form = FormHelpers.node_data_to_form(updated_node)

        socket =
          socket
          |> reload_flow_data()
          |> assign(:selected_node, updated_node)
          |> assign(:node_form, form)
          |> mark_saved()
          |> maybe_refresh_referencing_jumps(updated_node)

        {:noreply,
         if result.graph_changed? do
           push_event(socket, "flow_updated", socket.assigns.flow_data)
         else
           push_event(socket, "node_updated", %{
             id: node_id,
             data: canvas_data(updated_node, socket.assigns.flow.project_id)
           })
         end}

      {:error, :hub_id_required} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           Gettext.dgettext(Storyarn.Gettext, "flows", "Hub ID is required.")
         )}

      {:error, :hub_id_not_unique} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           Gettext.dgettext(Storyarn.Gettext, "flows", "Hub ID already exists in this flow.")
         )}

      {:error, _} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           Gettext.dgettext(Storyarn.Gettext, "flows", "Could not restore node data.")
         )}
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
         |> schedule(:flow)
         |> assign(:selected_node, nil)
         |> assign(:node_form, nil)
         |> put_flash(
           :warning,
           Gettext.dngettext(
             Storyarn.Gettext,
             "flows",
             "%{count} Jump node lost its target.",
             "%{count} Jump nodes lost their target.",
             count,
             count: count
           )
         )
         |> push_event("flow_updated", flow_data)
         |> CollaborationHelpers.broadcast_change(:flow_refresh, %{node_id: node_id})}

      {:ok, _deleted_node, %{graph_changed?: true}} ->
        socket = reload_flow_data(socket)
        flow_data = socket.assigns.flow_data

        {:noreply,
         socket
         |> schedule(:flow)
         |> assign(:selected_node, nil)
         |> assign(:node_form, nil)
         |> push_event("flow_updated", flow_data)
         |> CollaborationHelpers.broadcast_change(:flow_refresh, %{node_id: node_id})}

      {:ok, _deleted_node, %{graph_changed?: false}} ->
        socket = reload_flow_data(socket)

        {:noreply,
         socket
         |> schedule(:flow)
         |> assign(:selected_node, nil)
         |> assign(:node_form, nil)
         |> push_event("node_removed", %{id: node_id, self: true})
         |> CollaborationHelpers.broadcast_change(:node_deleted, %{node_id: node_id})}

      {:error, :cannot_delete_entry_node} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           Gettext.dgettext(Storyarn.Gettext, "flows", "The Entry node cannot be deleted.")
         )}

      {:error, :cannot_delete_last_exit} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           Gettext.dgettext(
             Storyarn.Gettext,
             "flows",
             "A flow must have at least one Exit node."
           )
         )}

      {:error, :composition_source_in_use} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           Gettext.dgettext(
             Storyarn.Gettext,
             "flows",
             "This node cannot be deleted while other nodes inherit its sequence composition."
           )
         )}

      {:error, _} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           Gettext.dgettext(Storyarn.Gettext, "flows", "Could not delete node.")
         )}
    end
  end
end

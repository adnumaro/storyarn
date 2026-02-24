defmodule StoryarnWeb.FlowLive.Handlers.GenericNodeHandlers do
  @moduledoc """
  Handles generic node events for the flow editor LiveView.

  Responsible for type-agnostic operations: add, select, deselect, move,
  delete, duplicate, update data/text/field, open/close editor.

  Type-specific event handlers live in their respective `Nodes.{Type}.Node` modules.
  Delegates heavy lifting to NodeHelpers. Returns `{:noreply, socket}`.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3, push_navigate: 2, put_flash: 3]

  use StoryarnWeb, :verified_routes
  use Gettext, backend: StoryarnWeb.Gettext

  alias Storyarn.Flows
  alias Storyarn.Sheets
  alias StoryarnWeb.FlowLive.Helpers.CollaborationHelpers
  alias StoryarnWeb.FlowLive.Helpers.FormHelpers
  alias StoryarnWeb.FlowLive.Helpers.NodeHelpers
  alias StoryarnWeb.FlowLive.NodeTypeRegistry

  import StoryarnWeb.FlowLive.Helpers.SocketHelpers

  @spec handle_add_node(map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_add_node(%{"type" => type} = params, socket) do
    opts =
      case {params["position_x"], params["position_y"]} do
        {x, y} when is_number(x) and is_number(y) -> [position: {x, y}]
        _ -> []
      end

    NodeHelpers.add_node(socket, type, opts)
  end

  @spec handle_save_name(map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_save_name(%{"name" => name}, socket) do
    flow = socket.assigns.flow
    prev_name = flow.name

    case Flows.update_flow(flow, %{name: name}) do
      {:ok, updated_flow} ->
        schedule_save_status_reset()

        {:noreply,
         socket
         |> assign(:flow, updated_flow)
         |> assign(:save_status, :saved)
         |> push_event("flow_meta_changed", %{field: "name", prev: prev_name, new: name})}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, dgettext("flows", "Could not save flow name."))}
    end
  end

  @spec handle_save_shortcut(map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_save_shortcut(%{"shortcut" => shortcut}, socket) do
    flow = socket.assigns.flow
    prev_shortcut = flow.shortcut
    shortcut = if shortcut == "", do: nil, else: shortcut

    case Flows.update_flow(flow, %{shortcut: shortcut}) do
      {:ok, updated_flow} ->
        schedule_save_status_reset()

        {:noreply,
         socket
         |> assign(:flow, updated_flow)
         |> assign(:save_status, :saved)
         |> push_event("flow_meta_changed", %{
           field: "shortcut",
           prev: prev_shortcut,
           new: shortcut
         })}

      {:error, changeset} ->
        error_msg = format_shortcut_error(changeset)
        {:noreply, put_flash(socket, :error, error_msg)}
    end
  end

  @spec handle_restore_flow_meta(map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_restore_flow_meta(%{"field" => "name", "value" => value}, socket) do
    flow = socket.assigns.flow

    case Flows.update_flow(flow, %{name: value}) do
      {:ok, updated_flow} ->
        schedule_save_status_reset()

        {:noreply,
         socket
         |> assign(:flow, updated_flow)
         |> assign(:save_status, :saved)
         |> push_event("restore_page_content", %{
           name: updated_flow.name,
           shortcut: updated_flow.shortcut || ""
         })}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("flows", "Could not restore flow name."))}
    end
  end

  def handle_restore_flow_meta(%{"field" => "shortcut", "value" => value}, socket) do
    flow = socket.assigns.flow
    shortcut = if value == "" or is_nil(value), do: nil, else: value

    case Flows.update_flow(flow, %{shortcut: shortcut}) do
      {:ok, updated_flow} ->
        schedule_save_status_reset()

        {:noreply,
         socket
         |> assign(:flow, updated_flow)
         |> assign(:save_status, :saved)
         |> push_event("restore_page_content", %{
           name: updated_flow.name,
           shortcut: updated_flow.shortcut || ""
         })}

      {:error, changeset} ->
        error_msg = format_shortcut_error(changeset)
        {:noreply, put_flash(socket, :error, error_msg)}
    end
  end

  def handle_restore_flow_meta(_params, socket), do: {:noreply, socket}

  @spec handle_node_selected(map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_node_selected(%{"id" => node_id}, socket) do
    node = Flows.get_node!(socket.assigns.flow.id, node_id)
    form = FormHelpers.node_data_to_form(node)
    user = socket.assigns.current_scope.user

    socket =
      if socket.assigns.can_edit do
        handle_node_lock_acquisition(socket, node_id, user)
      else
        socket
      end

    socket = NodeTypeRegistry.on_select(node.type, node, socket)

    {:noreply,
     socket
     |> assign(:selected_node, node)
     |> assign(:node_form, form)
     |> assign(:editing_mode, :toolbar)}
  end

  @spec handle_node_double_clicked(map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_node_double_clicked(%{"id" => node_id}, socket) do
    node = Flows.get_node!(socket.assigns.flow.id, node_id)
    editing_mode = NodeTypeRegistry.on_double_click(node.type, node)

    case editing_mode do
      {:navigate, flow_id} ->
        socket =
          if socket.assigns.selected_node && socket.assigns.can_edit do
            release_node_lock(socket, socket.assigns.selected_node.id)
          else
            socket
          end

        flow_id = if is_binary(flow_id), do: flow_id, else: to_string(flow_id)

        {:noreply,
         push_navigate(socket,
           to:
             ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/flows/#{flow_id}"
         )}

      mode ->
        form = FormHelpers.node_data_to_form(node)
        user = socket.assigns.current_scope.user

        socket =
          if socket.assigns.can_edit do
            handle_node_lock_acquisition(socket, node_id, user)
          else
            socket
          end

        {:noreply,
         socket
         |> assign(:selected_node, node)
         |> assign(:node_form, form)
         |> assign(:editing_mode, mode)}
    end
  end

  @spec handle_open_sidebar(Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_open_sidebar(socket) do
    {:noreply, assign(socket, :editing_mode, :toolbar)}
  end

  @spec handle_close_editor(Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_close_editor(socket) do
    socket =
      if socket.assigns.selected_node && socket.assigns.can_edit do
        release_node_lock(socket, socket.assigns.selected_node.id)
      else
        socket
      end

    {:noreply,
     socket
     |> assign(:selected_node, nil)
     |> assign(:node_form, nil)
     |> assign(:editing_mode, nil)}
  end

  @spec handle_deselect_node(Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_deselect_node(socket) do
    socket =
      if socket.assigns.selected_node && socket.assigns.can_edit do
        release_node_lock(socket, socket.assigns.selected_node.id)
      else
        socket
      end

    {:noreply,
     socket
     |> assign(:selected_node, nil)
     |> assign(:node_form, nil)
     |> assign(:editing_mode, nil)}
  end

  @spec handle_create_sheet(Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_create_sheet(socket) do
    case Sheets.create_sheet(socket.assigns.project, %{name: dgettext("flows", "Untitled")}) do
      {:ok, new_sheet} ->
        {:noreply,
         push_navigate(socket,
           to:
             ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/sheets/#{new_sheet.id}"
         )}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, dgettext("flows", "Could not create sheet."))}
    end
  end

  @spec handle_batch_update_positions(map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_batch_update_positions(%{"positions" => positions}, socket)
      when is_list(positions) do
    flow = socket.assigns.flow

    parsed =
      positions
      |> Enum.filter(fn pos ->
        is_integer(pos["id"]) and is_number(pos["position_x"]) and is_number(pos["position_y"])
      end)
      |> Enum.map(fn pos ->
        %{
          id: pos["id"],
          position_x: pos["position_x"] / 1,
          position_y: pos["position_y"] / 1
        }
      end)

    case Flows.batch_update_positions(flow.id, parsed) do
      {:ok, _count} ->
        schedule_save_status_reset()

        {:noreply,
         socket
         |> assign(:save_status, :saved)
         |> CollaborationHelpers.broadcast_change(:flow_refresh, %{})}

      {:error, _reason} ->
        {:noreply,
         put_flash(socket, :error, dgettext("flows", "Could not update node positions."))}
    end
  end

  def handle_batch_update_positions(_params, socket), do: {:noreply, socket}

  @search_limit Flows.default_search_limit()

  @spec handle_search_available_flows(map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_search_available_flows(%{"query" => query}, socket) when is_binary(query) do
    project_id = socket.assigns.project.id
    current_flow_id = socket.assigns.flow.id

    results = search_flows(socket, project_id, query, exclude_id: current_flow_id)

    {:noreply,
     socket
     |> assign(:available_flows, results)
     |> assign(:flow_search_query, query)
     |> assign(:flow_search_offset, @search_limit)
     |> assign(:flow_search_has_more, length(results) >= @search_limit)}
  end

  def handle_search_available_flows(_params, socket), do: {:noreply, socket}

  @spec handle_toggle_deep_search(Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_toggle_deep_search(socket) do
    deep = !socket.assigns[:flow_search_deep]
    socket = assign(socket, :flow_search_deep, deep)

    # Re-run the current search with the new mode
    query = socket.assigns[:flow_search_query] || ""
    handle_search_available_flows(%{"query" => query}, socket)
  end

  @spec handle_search_flows_more(Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_search_flows_more(socket) do
    project_id = socket.assigns.project.id
    current_flow_id = socket.assigns.flow.id
    query = socket.assigns[:flow_search_query] || ""
    offset = socket.assigns[:flow_search_offset] || 0

    more = search_flows(socket, project_id, query, offset: offset, exclude_id: current_flow_id)

    {:noreply,
     socket
     |> assign(:available_flows, (socket.assigns[:available_flows] || []) ++ more)
     |> assign(:flow_search_offset, offset + @search_limit)
     |> assign(:flow_search_has_more, length(more) >= @search_limit)}
  end

  defp search_flows(socket, project_id, query, opts) do
    if socket.assigns[:flow_search_deep],
      do: Flows.search_flows_deep(project_id, query, opts),
      else: Flows.search_flows(project_id, query, opts)
  end

  @spec handle_node_moved(map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_node_moved(%{"id" => node_id, "position_x" => x, "position_y" => y}, socket) do
    # Use non-raising get_node/2 — the node may have been deleted while a
    # debounced move event was still in flight.
    case Flows.get_node(socket.assigns.flow.id, node_id) do
      nil ->
        {:noreply, socket}

      node ->
        case Flows.update_node_position(node, %{position_x: x, position_y: y}) do
          {:ok, _} ->
            schedule_save_status_reset()

            {:noreply,
             socket
             |> assign(:save_status, :saved)
             |> CollaborationHelpers.broadcast_change(:node_moved, %{
               node_id: node_id,
               x: x,
               y: y
             })}

          {:error, _} ->
            {:noreply, socket}
        end
    end
  end

  @spec handle_update_node_data(map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_update_node_data(%{"node" => node_params}, socket) do
    NodeHelpers.update_node_data(socket, node_params)
  end

  @spec handle_update_node_text(map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_update_node_text(%{"id" => node_id, "content" => content}, socket) do
    NodeHelpers.update_node_text(socket, node_id, content)
  end

  @spec handle_mention_suggestions(map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_mention_suggestions(%{"query" => query}, socket) do
    project_id = socket.assigns.project.id
    results = Sheets.search_referenceable(project_id, query, ["sheet", "flow"])

    items =
      Enum.map(results, fn result ->
        %{
          id: result.id,
          type: result.type,
          name: result.name,
          shortcut: result.shortcut,
          label: result.shortcut || result.name
        }
      end)

    {:noreply, push_event(socket, "mention_suggestions_result", %{items: items})}
  end

  @spec handle_delete_node(map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_delete_node(%{"id" => node_id}, socket) do
    NodeHelpers.delete_node(socket, node_id)
  end

  @spec handle_duplicate_node(map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_duplicate_node(%{"id" => node_id}, socket) do
    NodeHelpers.duplicate_node(socket, node_id)
  end

  @spec handle_update_node_field(map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_update_node_field(%{"field" => field, "value" => value}, socket) do
    node = socket.assigns.selected_node

    if node do
      NodeHelpers.update_node_field(socket, node.id, field, value)
    else
      {:noreply, socket}
    end
  end

  @spec handle_start_preview(map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_start_preview(%{"id" => node_id}, socket) do
    node = Flows.get_node!(socket.assigns.flow.id, node_id)
    {:noreply, socket |> assign(:preview_show, true) |> assign(:preview_node, node)}
  end

  # Private helpers

  defp format_shortcut_error(changeset) do
    case changeset.errors[:shortcut] do
      {msg, _opts} -> dgettext("flows", "Shortcut %{error}", error: msg)
      nil -> dgettext("flows", "Could not save shortcut.")
    end
  end

  defp handle_node_lock_acquisition(socket, node_id, user) do
    alias Storyarn.Collaboration

    case Collaboration.acquire_lock(socket.assigns.flow.id, node_id, user) do
      {:ok, _lock_info} ->
        CollaborationHelpers.broadcast_lock_change(socket, :node_locked, node_id)
        node_locks = Collaboration.list_locks(socket.assigns.flow.id)

        socket
        |> assign(:node_locks, node_locks)
        |> push_event("locks_updated", %{locks: node_locks})

      {:error, :already_locked, lock_info} ->
        put_flash(
          socket,
          :info,
          dgettext("flows", "This node is being edited by %{user}",
            user: FormHelpers.get_email_name(lock_info.user_email)
          )
        )
    end
  end

  defp release_node_lock(socket, node_id) do
    alias Storyarn.Collaboration

    user_id = socket.assigns.current_scope.user.id
    Collaboration.release_lock(socket.assigns.flow.id, node_id, user_id)
    CollaborationHelpers.broadcast_lock_change(socket, :node_unlocked, node_id)
    node_locks = Collaboration.list_locks(socket.assigns.flow.id)
    socket |> assign(:node_locks, node_locks) |> push_event("locks_updated", %{locks: node_locks})
  end
end

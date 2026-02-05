defmodule StoryarnWeb.FlowLive.Handlers.NodeEventHandlers do
  @moduledoc """
  Handles node-related events for the flow editor LiveView.

  Responsible for: add, select, deselect, move, delete, duplicate,
  update node data/text/field, generate technical ID.

  Delegates heavy lifting to NodeHelpers. Returns `{:noreply, socket}`.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3, push_navigate: 2, put_flash: 3]

  use StoryarnWeb, :verified_routes
  use Gettext, backend: StoryarnWeb.Gettext

  alias Storyarn.Flows
  alias Storyarn.Pages
  alias Storyarn.Repo
  alias StoryarnWeb.FlowLive.Helpers.CollaborationHelpers
  alias StoryarnWeb.FlowLive.Helpers.FormHelpers
  alias StoryarnWeb.FlowLive.Helpers.NodeHelpers

  import StoryarnWeb.FlowLive.Components.NodeTypeHelpers, only: [generate_technical_id: 3]
  import StoryarnWeb.FlowLive.Helpers.SocketHelpers

  @spec handle_add_node(map(), Phoenix.LiveView.Socket.t()) :: {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_add_node(%{"type" => type}, socket) do
    NodeHelpers.add_node(socket, type)
  end

  @spec handle_save_shortcut(map(), Phoenix.LiveView.Socket.t()) :: {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_save_shortcut(%{"shortcut" => shortcut}, socket) do
    flow = socket.assigns.flow
    shortcut = if shortcut == "", do: nil, else: shortcut

    case Flows.update_flow(flow, %{shortcut: shortcut}) do
      {:ok, updated_flow} ->
        schedule_save_status_reset()

        {:noreply,
         socket
         |> assign(:flow, updated_flow)
         |> assign(:save_status, :saved)}

      {:error, changeset} ->
        error_msg = format_shortcut_error(changeset)
        {:noreply, put_flash(socket, :error, error_msg)}
    end
  end

  @spec handle_node_selected(map(), Phoenix.LiveView.Socket.t()) :: {:noreply, Phoenix.LiveView.Socket.t()}
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

    {:noreply,
     socket
     |> assign(:selected_node, node)
     |> assign(:node_form, form)
     |> assign(:editing_mode, :sidebar)}
  end

  @spec handle_node_double_clicked(map(), Phoenix.LiveView.Socket.t()) :: {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_node_double_clicked(%{"id" => node_id}, socket) do
    node = Flows.get_node!(socket.assigns.flow.id, node_id)
    form = FormHelpers.node_data_to_form(node)
    user = socket.assigns.current_scope.user

    # Only dialogue nodes support screenplay mode
    editing_mode = if node.type == "dialogue", do: :screenplay, else: :sidebar

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
     |> assign(:editing_mode, editing_mode)}
  end

  @spec handle_open_screenplay(Phoenix.LiveView.Socket.t()) :: {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_open_screenplay(socket) do
    if socket.assigns.selected_node && socket.assigns.selected_node.type == "dialogue" do
      {:noreply, assign(socket, :editing_mode, :screenplay)}
    else
      {:noreply, socket}
    end
  end

  @spec handle_open_sidebar(Phoenix.LiveView.Socket.t()) :: {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_open_sidebar(socket) do
    {:noreply, assign(socket, :editing_mode, :sidebar)}
  end

  @spec handle_close_editor(Phoenix.LiveView.Socket.t()) :: {:noreply, Phoenix.LiveView.Socket.t()}
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

  @spec handle_deselect_node(Phoenix.LiveView.Socket.t()) :: {:noreply, Phoenix.LiveView.Socket.t()}
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

  @spec handle_create_page(Phoenix.LiveView.Socket.t()) :: {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_create_page(socket) do
    case Pages.create_page(socket.assigns.project, %{name: gettext("Untitled")}) do
      {:ok, new_page} ->
        {:noreply,
         push_navigate(socket,
           to:
             ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/pages/#{new_page.id}"
         )}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, gettext("Could not create page."))}
    end
  end

  @spec handle_node_moved(map(), Phoenix.LiveView.Socket.t()) :: {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_node_moved(%{"id" => node_id, "position_x" => x, "position_y" => y}, socket) do
    node = Flows.get_node_by_id!(node_id)

    case Flows.update_node_position(node, %{position_x: x, position_y: y}) do
      {:ok, _} ->
        schedule_save_status_reset()

        {:noreply,
         socket
         |> assign(:save_status, :saved)
         |> CollaborationHelpers.broadcast_change(:node_moved, %{node_id: node_id, x: x, y: y})}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  @spec handle_update_node_data(map(), Phoenix.LiveView.Socket.t()) :: {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_update_node_data(%{"node" => node_params}, socket) do
    NodeHelpers.update_node_data(socket, node_params)
  end

  @spec handle_update_node_text(map(), Phoenix.LiveView.Socket.t()) :: {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_update_node_text(%{"id" => node_id, "content" => content}, socket) do
    NodeHelpers.update_node_text(socket, node_id, content)
  end

  @spec handle_mention_suggestions(map(), Phoenix.LiveView.Socket.t()) :: {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_mention_suggestions(%{"query" => query}, socket) do
    project_id = socket.assigns.project.id
    results = Pages.search_referenceable(project_id, query, ["page", "flow"])

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

  @spec handle_delete_node(map(), Phoenix.LiveView.Socket.t()) :: {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_delete_node(%{"id" => node_id}, socket) do
    NodeHelpers.delete_node(socket, node_id)
  end

  @spec handle_duplicate_node(map(), Phoenix.LiveView.Socket.t()) :: {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_duplicate_node(%{"id" => node_id}, socket) do
    NodeHelpers.duplicate_node(socket, node_id)
  end

  @spec handle_generate_technical_id(Phoenix.LiveView.Socket.t()) :: {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_generate_technical_id(socket) do
    node = socket.assigns.selected_node

    if node && node.type == "dialogue" do
      flow = socket.assigns.flow
      speaker_page_id = node.data["speaker_page_id"]
      speaker_name = get_speaker_name(socket, speaker_page_id)
      speaker_count = count_speaker_in_flow(flow, speaker_page_id, node.id)
      technical_id = generate_technical_id(flow.shortcut, speaker_name, speaker_count)

      NodeHelpers.update_node_field(socket, node.id, "technical_id", technical_id)
    else
      {:noreply, socket}
    end
  end

  @spec handle_update_node_field(map(), Phoenix.LiveView.Socket.t()) :: {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_update_node_field(%{"field" => field, "value" => value}, socket) do
    node = socket.assigns.selected_node

    if node do
      NodeHelpers.update_node_field(socket, node.id, field, value)
    else
      {:noreply, socket}
    end
  end

  @spec handle_start_preview(map(), Phoenix.LiveView.Socket.t()) :: {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_start_preview(%{"id" => node_id}, socket) do
    node = Flows.get_node!(socket.assigns.flow.id, node_id)
    {:noreply, socket |> assign(:preview_show, true) |> assign(:preview_node, node)}
  end

  # Private helpers

  defp format_shortcut_error(changeset) do
    case changeset.errors[:shortcut] do
      {msg, _opts} -> gettext("Shortcut %{error}", error: msg)
      nil -> gettext("Could not save shortcut.")
    end
  end

  defp get_speaker_name(_socket, nil), do: nil

  defp get_speaker_name(socket, speaker_page_id) do
    Enum.find_value(socket.assigns.leaf_pages, fn page ->
      if to_string(page.id) == to_string(speaker_page_id), do: page.name
    end)
  end

  defp count_speaker_in_flow(flow, speaker_page_id, current_node_id) do
    flow = Repo.preload(flow, :nodes)

    same_speaker_nodes =
      flow.nodes
      |> Enum.filter(fn node ->
        node.type == "dialogue" &&
          to_string(node.data["speaker_page_id"]) == to_string(speaker_page_id)
      end)
      |> Enum.sort_by(& &1.inserted_at)

    case Enum.find_index(same_speaker_nodes, &(&1.id == current_node_id)) do
      nil -> length(same_speaker_nodes) + 1
      index -> index + 1
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
          gettext("This node is being edited by %{user}",
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

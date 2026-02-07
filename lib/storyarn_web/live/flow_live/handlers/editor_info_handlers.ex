defmodule StoryarnWeb.FlowLive.Handlers.EditorInfoHandlers do
  @moduledoc """
  Handles info messages related to the editor state.

  Responsible for: reset_save_status, node_updated (from ScreenplayEditor),
  close_preview, and mention_suggestions (from ScreenplayEditor).
  Returns `{:noreply, socket}`.
  """

  import Phoenix.Component, only: [assign: 2, assign: 3]
  import Phoenix.LiveView, only: [push_event: 3]

  alias Storyarn.Flows
  alias Storyarn.Pages
  alias StoryarnWeb.FlowLive.Helpers.FormHelpers

  import StoryarnWeb.FlowLive.Helpers.SocketHelpers

  @spec handle_reset_save_status(Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_reset_save_status(socket) do
    {:noreply, assign(socket, :save_status, :idle)}
  end

  @spec handle_flow_refresh(Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_flow_refresh(socket) do
    socket = reload_flow_data(socket)

    {:noreply, push_event(socket, "flow_updated", socket.assigns.flow_data)}
  end

  @spec handle_node_updated(Storyarn.Flows.FlowNode.t(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_node_updated(updated_node, socket) do
    # The ScreenplayEditor already wrote to DB, so just reload state and push canvas data
    form = FormHelpers.node_data_to_form(updated_node)
    schedule_save_status_reset()

    {:noreply,
     socket
     |> reload_flow_data()
     |> assign(:selected_node, updated_node)
     |> assign(:node_form, form)
     |> assign(:save_status, :saved)
     |> push_event("node_updated", %{
       id: updated_node.id,
       data: Flows.resolve_node_colors(updated_node.type, updated_node.data)
     })}
  end

  @spec handle_close_preview(Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_close_preview(socket) do
    {:noreply, assign(socket, preview_show: false, preview_node: nil)}
  end

  @spec handle_mention_suggestions(String.t(), any(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_mention_suggestions(query, component_cid, socket) do
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

    {:noreply,
     push_event(socket, "mention_suggestions_result", %{items: items, target: component_cid})}
  end
end

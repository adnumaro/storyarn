defmodule StoryarnWeb.FlowLive.Handlers.EditorInfoHandlers do
  @moduledoc """
  Handles info messages related to the editor state.

  Responsible for: reset_save_status, node_updated (from the dialogue editor),
  close_preview, and mention_suggestions (from the dialogue editor).
  Returns `{:noreply, socket}`.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3]
  import StoryarnWeb.FlowLive.Helpers.SocketHelpers
  import StoryarnWeb.Helpers.SaveStatusTimer, only: [mark_saved: 1]

  alias Phoenix.LiveView.Socket
  alias Storyarn.Flows
  alias StoryarnWeb.FlowLive.Helpers.FormHelpers

  @spec handle_reset_save_status(Socket.t(), reference()) ::
          {:noreply, Socket.t()}
  def handle_reset_save_status(socket, token) do
    if socket.assigns[:save_status_reset_token] == token do
      {:noreply,
       socket
       |> assign(:save_status, :idle)
       |> assign(:save_status_reset_token, nil)}
    else
      {:noreply, socket}
    end
  end

  @spec handle_flow_refresh(Socket.t()) ::
          {:noreply, Socket.t()}
  def handle_flow_refresh(socket) do
    socket = reload_flow_data(socket)

    {:noreply, push_event(socket, "flow_updated", socket.assigns.flow_data)}
  end

  @spec handle_node_updated(map(), Socket.t()) ::
          {:noreply, Socket.t()}
  def handle_node_updated(updated_node, socket) do
    # The dialogue editor already wrote to DB, so just reload state and push canvas data
    form = FormHelpers.node_data_to_form(updated_node)

    {:noreply,
     socket
     |> reload_flow_data()
     |> assign(:selected_node, updated_node)
     |> assign(:node_form, form)
     |> mark_saved()
     |> push_event("node_updated", %{
       id: updated_node.id,
       data: Flows.resolve_node_colors(updated_node.type, updated_node.data)
     })}
  end

  @spec handle_mention_suggestions(String.t(), any(), Socket.t()) ::
          {:noreply, Socket.t()}
  def handle_mention_suggestions(query, _component_cid, socket) do
    project_id = socket.assigns.project.id
    results = Flows.search_mentions(project_id, query)

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

  @spec handle_variable_suggestions(String.t(), any(), Socket.t()) ::
          {:noreply, Socket.t()}
  def handle_variable_suggestions(query, _component_cid, socket) do
    results = Flows.search_variable_suggestions(socket.assigns.project_variables, query)

    {:noreply, push_event(socket, "variable_suggestions_result", %{items: results})}
  end
end

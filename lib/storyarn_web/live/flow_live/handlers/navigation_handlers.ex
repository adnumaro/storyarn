defmodule StoryarnWeb.FlowLive.Handlers.NavigationHandlers do
  @moduledoc """
  Navigation handlers for the flow editor.

  Handles cross-flow navigation (subflow, exit, referencing flows) and
  canvas node-level navigation events.
  """

  import Phoenix.LiveView, only: [push_navigate: 2, put_flash: 3]

  use StoryarnWeb, :verified_routes
  use Gettext, backend: StoryarnWeb.Gettext

  alias Storyarn.Flows

  @spec handle_navigate_to_flow(String.t(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_navigate_to_flow(flow_id_str, socket) do
    case Integer.parse(flow_id_str) do
      {flow_id, ""} ->
        case Flows.get_flow_brief(socket.assigns.project.id, flow_id) do
          nil ->
            {:noreply, put_flash(socket, :error, dgettext("flows", "Flow not found."))}

          _flow ->
            {:noreply,
             push_navigate(socket,
               to:
                 ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/flows/#{flow_id}"
             )}
        end

      _ ->
        {:noreply, put_flash(socket, :error, dgettext("flows", "Invalid flow ID."))}
    end
  end
end

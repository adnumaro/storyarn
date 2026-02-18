defmodule StoryarnWeb.ScreenplayLive.Handlers.FlowSyncHandlers do
  @moduledoc """
  Flow sync handlers for the screenplay LiveView.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_navigate: 2, put_flash: 3]
  use Gettext, backend: StoryarnWeb.Gettext
  use StoryarnWeb, :verified_routes

  alias Storyarn.Flows
  alias Storyarn.Flows.Flow
  alias Storyarn.Screenplays
  alias Storyarn.Screenplays.Screenplay

  import StoryarnWeb.ScreenplayLive.Helpers.SocketHelpers

  def do_sync_to_flow(socket) do
    if socket.assigns.link_status != :linked do
      {:noreply, put_flash(socket, :error, dgettext("screenplays", "Screenplay is not linked to a flow."))}
    else
      case Screenplays.sync_to_flow(socket.assigns.screenplay) do
        {:ok, _flow} ->
          {:noreply, put_flash(socket, :info, dgettext("screenplays", "Screenplay synced to flow."))}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, dgettext("screenplays", "Could not sync screenplay."))}
      end
    end
  end

  def do_sync_from_flow(socket) do
    screenplay = socket.assigns.screenplay

    if socket.assigns.link_status != :linked do
      {:noreply, put_flash(socket, :error, dgettext("screenplays", "Screenplay is not linked to a flow."))}
    else
      case Screenplays.sync_from_flow(screenplay) do
        {:ok, _screenplay} ->
          elements = Screenplays.list_elements(screenplay.id)

          {:noreply,
           socket
           |> assign_elements(elements)
           |> push_editor_content(elements)
           |> put_flash(:info, dgettext("screenplays", "Screenplay updated from flow."))}

        {:error, :no_entry_node} ->
          {:noreply, put_flash(socket, :error, dgettext("screenplays", "Flow has no entry node."))}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, dgettext("screenplays", "Could not sync from flow."))}
      end
    end
  end

  def do_create_flow_from_screenplay(socket) do
    screenplay = socket.assigns.screenplay

    with {:ok, flow} <- Screenplays.ensure_flow(screenplay),
         screenplay = Screenplays.get_screenplay!(screenplay.project_id, screenplay.id),
         {:ok, _flow} <- Screenplays.sync_to_flow(screenplay) do
      {:noreply,
       socket
       |> assign(:screenplay, screenplay)
       |> assign(:link_status, :linked)
       |> assign(:linked_flow, flow)
       |> put_flash(:info, dgettext("screenplays", "Flow created and synced."))}
    else
      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, dgettext("screenplays", "Could not create flow."))}
    end
  end

  def do_unlink_flow(socket) do
    screenplay = socket.assigns.screenplay

    case Screenplays.unlink_flow(screenplay) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:screenplay, updated)
         |> assign(:link_status, :unlinked)
         |> assign(:linked_flow, nil)
         |> put_flash(:info, dgettext("screenplays", "Flow unlinked."))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, dgettext("screenplays", "Could not unlink flow."))}
    end
  end

  def do_navigate_to_flow(socket) do
    flow = socket.assigns.linked_flow

    if flow do
      {:noreply,
       push_navigate(socket,
         to:
           ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/flows/#{flow.id}"
       )}
    else
      {:noreply, socket}
    end
  end

  def detect_link_status(%Screenplay{linked_flow_id: nil}), do: {:unlinked, nil}

  def detect_link_status(%Screenplay{project_id: project_id, linked_flow_id: flow_id}) do
    case Flows.get_flow_including_deleted(project_id, flow_id) do
      nil ->
        {:flow_missing, nil}

      flow ->
        if Flow.deleted?(flow),
          do: {:flow_deleted, flow},
          else: {:linked, flow}
    end
  end
end

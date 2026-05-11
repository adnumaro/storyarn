defmodule StoryarnWeb.PresenceLive do
  @moduledoc """
  Invisible sticky LV that tracks project-level presence and broadcasts
  online user changes on the shell topic.

  Rendered as a sticky nested child of the project layout purely to keep the
  presence process alive across page navigations. Does NOT render any
  visible chrome — the toolbar Vue components (`ProjectNavbarContext` /
  `ProjectNavbarAccount`) are rendered by the layout, which receives
  `online_users` as an attr from each page LV. Page LVs subscribe to the
  shell topic where this LV broadcasts presence changes.

  Broadcast shape: `{:online_users, list}` on `"project:\#{id}:shell"`.
  """

  use StoryarnWeb, :live_view

  alias Storyarn.Collaboration.Presence
  alias StoryarnWeb.Live.Shared.CollaborationHelpers, as: Collab

  @impl true
  def mount(_params, session, socket) do
    current_scope = session["current_scope"]
    project_id = session["project_id"]
    scope = project_id && {:project, project_id}

    online_users =
      if current_scope && scope do
        Collab.setup(socket, scope, current_scope.user, changes: false, locks: false)
        {users, _locks} = Collab.get_initial_state(socket, scope)
        users
      else
        []
      end

    if connected?(socket) && project_id do
      broadcast_online_users(project_id, online_users)
    end

    socket =
      socket
      |> assign(:current_scope, current_scope)
      |> assign(:project_id, project_id)
      |> assign(:collab_scope, scope)
      |> assign(:online_users, online_users)

    {:ok, socket, layout: false}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="presence-live" hidden></div>
    """
  end

  @impl true
  def handle_info({Presence, {:join, presence}}, socket) do
    {:noreply, socket} = Collab.handle_presence_join(socket, presence)
    broadcast_online_users(socket.assigns.project_id, socket.assigns.online_users)
    {:noreply, socket}
  end

  def handle_info({Presence, {:leave, presence}}, socket) do
    {:noreply, socket} = Collab.handle_presence_leave(socket, presence)
    broadcast_online_users(socket.assigns.project_id, socket.assigns.online_users)
    {:noreply, socket}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def terminate(_reason, socket) do
    if scope = socket.assigns[:collab_scope] do
      user_id = socket.assigns.current_scope.user.id
      Collab.teardown(scope, user_id)
    end

    :ok
  end

  defp broadcast_online_users(project_id, users) do
    Phoenix.PubSub.broadcast(
      Storyarn.PubSub,
      "project:#{project_id}:shell",
      {:online_users, users}
    )
  end
end

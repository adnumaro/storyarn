defmodule StoryarnWeb.ToolbarsLive do
  @moduledoc """
  Floating top toolbars (left + right).

  Rendered as a nested child of `ProjectShellLive`. Owns project-level
  presence — the right toolbar shows online users, so presence tracking
  lives here (keeping the shell's template Vue-free avoids the LiveVue
  nested-LV mount race).
  """

  use StoryarnWeb, :live_view

  alias Storyarn.Collaboration.Presence
  alias StoryarnWeb.Live.Shared.CollaborationHelpers, as: Collab

  @impl true
  def mount(_params, session, socket) do
    current_scope = session["current_scope"]
    current_user = session["current_user"]
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

    socket =
      socket
      |> assign(:current_scope, current_scope)
      |> assign(:current_user, current_user)
      |> assign(:project_name, session["project_name"])
      |> assign(:workspace_name, session["workspace_name"])
      |> assign(:is_super_admin, session["is_super_admin"] || false)
      |> assign(:urls, session["urls"] || %{})
      |> assign(:active_tool, session["active_tool"] || "sheets")
      |> assign(:collab_scope, scope)
      |> assign(:online_users, online_users)

    {:ok, socket, layout: false}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div class="fixed top-3 left-3 z-41 flex items-stretch gap-2">
        <.vue
          v-component="layout/LeftToolbar"
          v-socket={@socket}
          id="shell-left-toolbar"
          active-tool={@active_tool}
          has-tree={true}
          tree-panel-open={true}
          project-name={@project_name}
          workspace-name={@workspace_name}
          show-tool-switcher={true}
          is-super-admin={@is_super_admin}
          urls={@urls}
        />
      </div>

      <div
        id={"shell-right-toolbar-wrapper-#{online_users_key(@online_users)}"}
        class="fixed top-3 right-3 z-41 flex items-stretch gap-2"
        phx-update="ignore"
      >
        <.vue
          v-component="layout/RightToolbar"
          v-socket={@socket}
          id="shell-right-toolbar"
          current-user={@current_user}
          online-users={@online_users}
          urls={@urls}
        />
      </div>
    </div>
    """
  end

  # Tree panel events come from LeftToolbar.vue (inside this LV's DOM) but
  # their state lives in SidebarLive. Forward via PubSub on the shell topic.
  @impl true
  def handle_event("tree_panel_" <> _ = event, params, socket) do
    forward_toolbar_event(socket.assigns[:collab_scope], event, params)
    {:noreply, socket}
  end

  defp forward_toolbar_event({:project, project_id}, event, params) do
    Phoenix.PubSub.broadcast(
      Storyarn.PubSub,
      StoryarnWeb.SidebarLive.shell_topic(project_id),
      {:toolbar_event, event, params}
    )
  end

  defp forward_toolbar_event(_scope, _event, _params), do: :ok

  @impl true
  def handle_info({Presence, {:join, presence}}, socket) do
    Collab.handle_presence_join(socket, presence)
  end

  def handle_info({Presence, {:leave, presence}}, socket) do
    Collab.handle_presence_leave(socket, presence)
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  defp online_users_key(users) do
    users
    |> Enum.map(& &1.user_id)
    |> Enum.sort()
    |> Enum.join("-")
    |> case do
      "" -> "empty"
      key -> key
    end
  end

  @impl true
  def terminate(_reason, socket) do
    if scope = socket.assigns[:collab_scope] do
      user_id = socket.assigns.current_scope.user.id
      Collab.teardown(scope, user_id)
    end

    :ok
  end
end

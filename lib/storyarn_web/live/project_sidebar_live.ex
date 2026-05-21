defmodule StoryarnWeb.ProjectSidebarLive do
  @moduledoc """
  Project dashboard left sidebar.

  It is intentionally static: project dashboards need navigation to the main
  tools and project settings, while tool-specific trees stay in their own
  sidebar LiveViews.
  """

  use StoryarnWeb, :live_view

  @impl true
  def mount(_params, session, socket) do
    if locale = session["locale"], do: Gettext.put_locale(Storyarn.Gettext, locale)

    socket =
      socket
      |> assign(:workspace_slug, session["workspace_slug"])
      |> assign(:project_slug, session["project_slug"])
      |> assign(:active_item, session["active_item"] || "dashboard")
      |> assign(:main_sidebar_open, true)

    {:ok, socket, layout: false}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.vue
        v-component="live/project/sidebar/ProjectSidebar"
        v-socket={@socket}
        id="project-sidebar"
        main-sidebar-open={@main_sidebar_open}
        workspace-slug={@workspace_slug}
        project-slug={@project_slug}
        active-item={@active_item}
      />
    </div>
    """
  end
end

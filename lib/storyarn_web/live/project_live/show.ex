defmodule StoryarnWeb.ProjectLive.Show do
  @moduledoc false

  use StoryarnWeb, :live_view

  alias Storyarn.Pages
  alias Storyarn.Projects
  alias Storyarn.Repo

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.project
      flash={@flash}
      current_scope={@current_scope}
      project={@project}
      workspace={@workspace}
      pages_tree={@pages_tree}
      current_path={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}"}
    >
      <div class="text-center mb-8">
        <.header>
          {@project.name}
          <:subtitle :if={@project.description}>
            {@project.description}
          </:subtitle>
          <:actions :if={@can_manage}>
            <.link
              navigate={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/settings"}
              class="btn btn-ghost btn-sm"
            >
              <.icon name="hero-cog-6-tooth" class="size-4 mr-1" />
              {gettext("Settings")}
            </.link>
          </:actions>
        </.header>
      </div>

      <div class="text-center py-12 text-base-content/70">
        <.icon name="hero-document-text" class="size-12 mx-auto mb-4 text-base-content/30" />
        <p>{gettext("Project workspace coming soon!")}</p>
        <p class="text-sm mt-2">{gettext("This is where you'll design your narrative flows.")}</p>
      </div>
    </Layouts.project>
    """
  end

  @impl true
  def mount(
        %{"workspace_slug" => workspace_slug, "project_slug" => project_slug},
        _session,
        socket
      ) do
    case Projects.get_project_by_slugs(socket.assigns.current_scope, workspace_slug, project_slug) do
      {:ok, project, membership} ->
        project = Repo.preload(project, :workspace)
        can_manage = Projects.ProjectMembership.can?(membership.role, :manage_project)
        pages_tree = Pages.list_pages_tree(project.id)

        socket =
          socket
          |> assign(:project, project)
          |> assign(:workspace, project.workspace)
          |> assign(:current_workspace, project.workspace)
          |> assign(:membership, membership)
          |> assign(:can_manage, can_manage)
          |> assign(:pages_tree, pages_tree)

        {:ok, socket}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Project not found."))
         |> redirect(to: ~p"/workspaces")}
    end
  end
end

defmodule StoryarnWeb.ProjectLive.Show do
  @moduledoc false

  use StoryarnWeb, :live_view

  alias Storyarn.Projects
  alias Storyarn.Repo

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      workspaces={@workspaces}
      current_workspace={@current_workspace}
    >
      <div class="mb-8">
        <.back navigate={~p"/workspaces/#{@project.workspace.slug}"}>
          {gettext("Back to %{workspace}", workspace: @project.workspace.name)}
        </.back>
      </div>

      <div class="text-center mb-8">
        <.header>
          {@project.name}
          <:subtitle :if={@project.description}>
            {@project.description}
          </:subtitle>
          <:actions :if={@can_manage}>
            <.link navigate={~p"/projects/#{@project.id}/settings"} class="btn btn-ghost btn-sm">
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
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Projects.get_project(socket.assigns.current_scope, id) do
      {:ok, project, membership} ->
        project = Repo.preload(project, :workspace)
        can_manage = Projects.ProjectMembership.can?(membership.role, :manage_project)

        socket =
          socket
          |> assign(:project, project)
          |> assign(:current_workspace, project.workspace)
          |> assign(:membership, membership)
          |> assign(:can_manage, can_manage)

        {:ok, socket}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Project not found."))
         |> redirect(to: ~p"/workspaces")}
    end
  end
end

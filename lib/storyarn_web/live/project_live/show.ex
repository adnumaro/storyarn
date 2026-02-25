defmodule StoryarnWeb.ProjectLive.Show do
  @moduledoc false

  use StoryarnWeb, :live_view

  import StoryarnWeb.Live.Shared.TreePanelHandlers

  alias Storyarn.Projects
  alias Storyarn.Sheets
  alias StoryarnWeb.Components.Sidebar.SheetTree

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.focus
      flash={@flash}
      current_scope={@current_scope}
      project={@project}
      workspace={@workspace}
      active_tool={:sheets}
      has_tree={true}
      tree_panel_open={@tree_panel_open}
      tree_panel_pinned={@tree_panel_pinned}
    >
      <:tree_content>
        <SheetTree.sheets_section
          sheets_tree={@sheets_tree}
          workspace={@workspace}
          project={@project}
          can_edit={false}
        />
      </:tree_content>
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
              <.icon name="settings" class="size-4 mr-1" />
              {dgettext("projects", "Settings")}
            </.link>
          </:actions>
        </.header>
      </div>

      <div class="text-center py-12 text-base-content/70">
        <.icon name="file-text" class="size-12 mx-auto mb-4 text-base-content/30" />
        <p>{dgettext("projects", "Project workspace coming soon!")}</p>
        <p class="text-sm mt-2">
          {dgettext("projects", "This is where you'll design your narrative flows.")}
        </p>
      </div>
    </Layouts.focus>
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
        can_manage = Projects.can?(membership.role, :manage_project)
        sheets_tree = Sheets.list_sheets_tree(project.id)

        socket =
          socket
          |> assign(focus_layout_defaults())
          |> assign(:project, project)
          |> assign(:workspace, project.workspace)
          |> assign(:current_workspace, project.workspace)
          |> assign(:membership, membership)
          |> assign(:can_manage, can_manage)
          |> assign(:sheets_tree, sheets_tree)

        {:ok, socket}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, dgettext("projects", "Project not found."))
         |> redirect(to: ~p"/workspaces")}
    end
  end

  @impl true
  # Tree panel events (from FocusLayout)
  def handle_event("tree_panel_" <> _ = event, params, socket),
    do: handle_tree_panel_event(event, params, socket)
end

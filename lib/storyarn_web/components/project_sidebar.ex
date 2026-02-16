defmodule StoryarnWeb.Components.ProjectSidebar do
  @moduledoc """
  Sidebar component for project navigation.
  Dispatches to SheetTree and FlowTree for content sections.
  """

  use Phoenix.Component
  use StoryarnWeb, :verified_routes
  use Gettext, backend: StoryarnWeb.Gettext

  import StoryarnWeb.Components.CoreComponents
  import StoryarnWeb.Components.TreeComponents

  alias StoryarnWeb.Components.Sidebar.FlowTree
  alias StoryarnWeb.Components.Sidebar.ScreenplayTree
  alias StoryarnWeb.Components.Sidebar.SheetTree

  attr :project, :map, required: true
  attr :workspace, :map, required: true
  attr :sheets_tree, :list, default: []
  attr :flows_tree, :list, default: []
  attr :screenplays_tree, :list, default: []
  attr :active_tool, :atom, default: :sheets
  attr :current_path, :string, required: true
  attr :selected_sheet_id, :string, default: nil
  attr :selected_flow_id, :string, default: nil
  attr :selected_screenplay_id, :string, default: nil
  attr :can_edit, :boolean, default: false

  def project_sidebar(assigns) do
    ~H"""
    <aside class="w-64 h-screen bg-base-200 flex flex-col border-r border-base-300">
      <%!-- Back to workspace --%>
      <div class="p-3 border-b border-base-300">
        <.link
          navigate={~p"/workspaces/#{@workspace.slug}"}
          class="flex items-center gap-2 text-sm text-base-content/70 hover:text-base-content"
        >
          <.icon name="chevron-left" class="size-4" />
          {gettext("Back to Workspace")}
        </.link>
      </div>

      <%!-- Project header --%>
      <div class="p-3 border-b border-base-300">
        <div class="flex items-center gap-2 font-semibold truncate">
          <.icon name="folder" class="size-5 shrink-0" />
          <span class="truncate">{@project.name}</span>
        </div>
      </div>

      <%!-- Main navigation --%>
      <nav class="flex-1 overflow-y-auto p-2 space-y-4">
        <%!-- Project tools section --%>
        <div>
          <.tree_section label={gettext("Tools")} />
          <.tree_link
            label={gettext("Flows")}
            href={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/flows"}
            icon="git-branch"
            active={flows_page?(@current_path, @workspace.slug, @project.slug)}
          />
          <.tree_link
            label={gettext("Screenplays")}
            href={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/screenplays"}
            icon="scroll-text"
            active={screenplays_page?(@current_path, @workspace.slug, @project.slug)}
          />
          <.tree_link
            label={gettext("Sheets")}
            href={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/sheets"}
            icon="file-text"
            active={sheets_tool_page?(@current_path, @workspace.slug, @project.slug)}
          />
          <.tree_link
            label={gettext("Assets")}
            href={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/assets"}
            icon="image"
            active={assets_page?(@current_path, @workspace.slug, @project.slug)}
          />
        </div>

        <%!-- Dynamic content section based on active tool --%>
        <%= cond do %>
          <% @active_tool == :flows -> %>
            <FlowTree.flows_section
              flows_tree={@flows_tree}
              workspace={@workspace}
              project={@project}
              selected_flow_id={@selected_flow_id}
              can_edit={@can_edit}
            />
          <% @active_tool == :screenplays -> %>
            <ScreenplayTree.screenplays_section
              screenplays_tree={@screenplays_tree}
              workspace={@workspace}
              project={@project}
              selected_screenplay_id={@selected_screenplay_id}
              can_edit={@can_edit}
            />
          <% true -> %>
            <SheetTree.sheets_section
              sheets_tree={@sheets_tree}
              workspace={@workspace}
              project={@project}
              selected_sheet_id={@selected_sheet_id}
              can_edit={@can_edit}
            />
        <% end %>
      </nav>

      <%!-- Footer links --%>
      <div class="p-2 border-t border-base-300">
        <.tree_link
          label={gettext("Trash")}
          href={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/trash"}
          icon="trash-2"
          active={trash_page?(@current_path, @workspace.slug, @project.slug)}
        />
        <.tree_link
          label={gettext("Settings")}
          href={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/settings"}
          icon="settings"
          active={settings_page?(@current_path, @workspace.slug, @project.slug)}
        />
      </div>
    </aside>
    """
  end

  defp settings_page?(path, workspace_slug, project_slug) do
    String.contains?(path, "/workspaces/#{workspace_slug}/projects/#{project_slug}/settings")
  end

  defp trash_page?(path, workspace_slug, project_slug) do
    String.contains?(path, "/workspaces/#{workspace_slug}/projects/#{project_slug}/trash")
  end

  defp flows_page?(path, workspace_slug, project_slug) do
    String.contains?(path, "/workspaces/#{workspace_slug}/projects/#{project_slug}/flows")
  end

  defp screenplays_page?(path, workspace_slug, project_slug) do
    String.contains?(path, "/workspaces/#{workspace_slug}/projects/#{project_slug}/screenplays")
  end

  defp sheets_tool_page?(path, workspace_slug, project_slug) do
    String.contains?(path, "/workspaces/#{workspace_slug}/projects/#{project_slug}/sheets")
  end

  defp assets_page?(path, workspace_slug, project_slug) do
    String.contains?(path, "/workspaces/#{workspace_slug}/projects/#{project_slug}/assets")
  end
end

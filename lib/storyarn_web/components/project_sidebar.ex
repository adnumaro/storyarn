defmodule StoryarnWeb.Components.ProjectSidebar do
  @moduledoc """
  Sidebar component for project navigation with pages tree.
  """
  use Phoenix.Component
  use StoryarnWeb, :verified_routes
  use Gettext, backend: StoryarnWeb.Gettext

  import StoryarnWeb.CoreComponents
  import StoryarnWeb.TreeComponents

  attr :project, :map, required: true
  attr :workspace, :map, required: true
  attr :pages_tree, :list, default: []
  attr :current_path, :string, required: true
  attr :selected_page_id, :string, default: nil

  def project_sidebar(assigns) do
    ~H"""
    <aside class="w-64 h-screen bg-base-200 flex flex-col border-r border-base-300">
      <%!-- Back to workspace --%>
      <div class="p-3 border-b border-base-300">
        <.link
          navigate={~p"/workspaces/#{@workspace.slug}"}
          class="flex items-center gap-2 text-sm text-base-content/70 hover:text-base-content"
        >
          <.icon name="hero-chevron-left" class="size-4" />
          {gettext("Back to Workspace")}
        </.link>
      </div>

      <%!-- Project header --%>
      <div class="p-3 border-b border-base-300">
        <.link
          navigate={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}"}
          class="flex items-center gap-2 font-semibold hover:text-primary truncate"
        >
          <.icon name="hero-folder" class="size-5 shrink-0" />
          <span class="truncate">{@project.name}</span>
        </.link>
      </div>

      <%!-- Main navigation --%>
      <nav class="flex-1 overflow-y-auto p-2 space-y-4">
        <%!-- Pages section with tree --%>
        <div>
          <div class="flex items-center justify-between mb-1">
            <.tree_section label={gettext("Pages")} />
            <.link
              navigate={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/pages/new"}
              class="btn btn-ghost btn-xs"
              title={gettext("New Page")}
            >
              <.icon name="hero-plus" class="size-3" />
            </.link>
          </div>
          <div :if={@pages_tree == []} class="text-sm text-base-content/50 px-4 py-2">
            {gettext("No pages yet")}
          </div>
          <.page_tree_items
            :for={page <- @pages_tree}
            page={page}
            workspace={@workspace}
            project={@project}
            selected_page_id={@selected_page_id}
          />
        </div>

        <%!-- Project tools section --%>
        <div>
          <.tree_section label={gettext("Tools")} />
          <.tree_link
            label={gettext("Flows")}
            href={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}"}
            icon="hero-arrows-pointing-out"
            active={false}
          />
        </div>
      </nav>

      <%!-- Settings footer --%>
      <div class="p-2 border-t border-base-300">
        <.tree_link
          label={gettext("Settings")}
          href={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/settings"}
          icon="hero-cog-6-tooth"
          active={settings_page?(@current_path, @workspace.slug, @project.slug)}
        />
      </div>
    </aside>
    """
  end

  # Recursive component for rendering page tree items
  attr :page, :map, required: true
  attr :workspace, :map, required: true
  attr :project, :map, required: true
  attr :selected_page_id, :string, default: nil

  defp page_tree_items(assigns) do
    has_children = has_children?(assigns.page)
    is_selected = assigns.selected_page_id == to_string(assigns.page.id)

    is_expanded =
      has_children and has_selected_page_recursive?(assigns.page.children, assigns.selected_page_id)

    assigns =
      assigns
      |> assign(:has_children, has_children)
      |> assign(:is_selected, is_selected)
      |> assign(:is_expanded, is_expanded)

    ~H"""
    <%= if @has_children do %>
      <.tree_node
        id={"page-#{@page.id}"}
        label={@page.name}
        icon_text={@page.icon || "page"}
        expanded={@is_expanded}
        has_children={true}
        href={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/pages/#{@page.id}"}
      >
        <.page_tree_items
          :for={child <- @page.children}
          page={child}
          workspace={@workspace}
          project={@project}
          selected_page_id={@selected_page_id}
        />
      </.tree_node>
    <% else %>
      <.tree_leaf
        label={@page.name}
        icon_text={@page.icon || "page"}
        href={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/pages/#{@page.id}"}
        active={@is_selected}
      />
    <% end %>
    """
  end

  defp has_children?(page) do
    case Map.get(page, :children) do
      nil -> false
      [] -> false
      children when is_list(children) -> true
      _ -> false
    end
  end

  defp has_selected_page_recursive?(pages, selected_id) when is_binary(selected_id) do
    Enum.any?(pages, fn page ->
      to_string(page.id) == selected_id or
        has_selected_page_recursive?(Map.get(page, :children, []), selected_id)
    end)
  end

  defp has_selected_page_recursive?(_pages, _selected_id), do: false

  defp settings_page?(path, workspace_slug, project_slug) do
    String.contains?(path, "/workspaces/#{workspace_slug}/projects/#{project_slug}/settings")
  end
end

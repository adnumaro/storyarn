defmodule StoryarnWeb.Components.ProjectSidebar do
  @moduledoc """
  Sidebar component for project navigation with pages tree.
  """
  use Phoenix.Component
  use StoryarnWeb, :verified_routes
  use Gettext, backend: StoryarnWeb.Gettext

  import StoryarnWeb.Components.CoreComponents
  import StoryarnWeb.Components.TreeComponents

  attr :project, :map, required: true
  attr :workspace, :map, required: true
  attr :pages_tree, :list, default: []
  attr :flows_tree, :list, default: []
  attr :active_tool, :atom, default: :pages
  attr :current_path, :string, required: true
  attr :selected_page_id, :string, default: nil
  attr :selected_flow_id, :string, default: nil
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
            label={gettext("Pages")}
            href={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/pages"}
            icon="file-text"
            active={pages_tool_page?(@current_path, @workspace.slug, @project.slug)}
          />
        </div>

        <%!-- Dynamic content section based on active tool --%>
        <%= if @active_tool == :flows do %>
          <.flows_section
            flows_tree={@flows_tree}
            workspace={@workspace}
            project={@project}
            selected_flow_id={@selected_flow_id}
            can_edit={@can_edit}
          />
        <% else %>
          <.pages_section
            pages_tree={@pages_tree}
            workspace={@workspace}
            project={@project}
            selected_page_id={@selected_page_id}
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

  # Pages section component
  attr :pages_tree, :list, required: true
  attr :workspace, :map, required: true
  attr :project, :map, required: true
  attr :selected_page_id, :string, default: nil
  attr :can_edit, :boolean, default: false

  defp pages_section(assigns) do
    ~H"""
    <div>
      <div class="flex items-center justify-between mb-1">
        <.tree_section label={gettext("Pages")} />
        <button
          :if={@can_edit}
          type="button"
          phx-click="create_page"
          class="btn btn-ghost btn-xs"
          title={gettext("New Page")}
        >
          <.icon name="plus" class="size-3" />
        </button>
      </div>

      <%!-- Search input --%>
      <div
        :if={@pages_tree != []}
        id="pages-tree-search"
        phx-hook="TreeSearch"
        data-tree-id="pages-tree-container"
        class="mb-2"
      >
        <input
          type="text"
          data-tree-search-input
          placeholder={gettext("Filter pages...")}
          class="input input-xs input-bordered w-full"
        />
      </div>

      <div :if={@pages_tree == []} class="text-sm text-base-content/50 px-4 py-2">
        {gettext("No pages yet")}
      </div>

      <%!-- Tree container with sortable support --%>
      <div
        :if={@pages_tree != []}
        id="pages-tree-container"
        phx-hook={if @can_edit, do: "SortableTree", else: nil}
      >
        <div data-sortable-container data-parent-id="">
          <.page_tree_items
            :for={page <- @pages_tree}
            page={page}
            workspace={@workspace}
            project={@project}
            selected_page_id={@selected_page_id}
            can_edit={@can_edit}
          />
        </div>
      </div>
    </div>
    """
  end

  # Flows section component
  attr :flows_tree, :list, required: true
  attr :workspace, :map, required: true
  attr :project, :map, required: true
  attr :selected_flow_id, :string, default: nil
  attr :can_edit, :boolean, default: false

  defp flows_section(assigns) do
    ~H"""
    <div>
      <div class="flex items-center justify-between mb-1">
        <.tree_section label={gettext("Flows")} />
        <button
          :if={@can_edit}
          type="button"
          phx-click="create_flow"
          class="btn btn-ghost btn-xs"
          title={gettext("New Flow")}
        >
          <.icon name="plus" class="size-3" />
        </button>
      </div>

      <%!-- Search input --%>
      <div
        :if={@flows_tree != []}
        id="flows-tree-search"
        phx-hook="TreeSearch"
        data-tree-id="flows-tree-container"
        class="mb-2"
      >
        <input
          type="text"
          data-tree-search-input
          placeholder={gettext("Filter flows...")}
          class="input input-xs input-bordered w-full"
        />
      </div>

      <div :if={@flows_tree == []} class="text-sm text-base-content/50 px-4 py-2">
        {gettext("No flows yet")}
      </div>

      <%!-- Tree container with sortable support --%>
      <div
        :if={@flows_tree != []}
        id="flows-tree-container"
        phx-hook={if @can_edit, do: "SortableTree", else: nil}
        data-tree-type="flows"
      >
        <div data-sortable-container data-parent-id="">
          <.flow_tree_items
            :for={flow <- @flows_tree}
            flow={flow}
            workspace={@workspace}
            project={@project}
            selected_flow_id={@selected_flow_id}
            can_edit={@can_edit}
          />
        </div>
      </div>
    </div>
    """
  end

  # Recursive component for rendering flow tree items
  attr :flow, :map, required: true
  attr :workspace, :map, required: true
  attr :project, :map, required: true
  attr :selected_flow_id, :string, default: nil
  attr :can_edit, :boolean, default: false

  defp flow_tree_items(assigns) do
    has_children = has_flow_children?(assigns.flow)
    is_selected = assigns.selected_flow_id == to_string(assigns.flow.id)

    is_expanded =
      has_children and
        has_selected_flow_recursive?(assigns.flow.children, assigns.selected_flow_id)

    assigns =
      assigns
      |> assign(:has_children, has_children)
      |> assign(:is_selected, is_selected)
      |> assign(:is_expanded, is_expanded)
      |> assign(:flow_id, to_string(assigns.flow.id))

    ~H"""
    <%= if @has_children do %>
      <.tree_node
        id={"flow-#{@flow.id}"}
        label={@flow.name}
        icon="git-branch"
        expanded={@is_expanded}
        has_children={true}
        href={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/flows/#{@flow.id}"}
        page_id={@flow_id}
        page_name={@flow.name}
        can_drag={@can_edit}
      >
        <:actions :if={@can_edit}>
          <button
            type="button"
            phx-click="create_child_flow"
            phx-value-parent-id={@flow.id}
            class="btn btn-ghost btn-xs btn-square"
            title={gettext("Add child flow")}
            onclick="event.preventDefault(); event.stopPropagation();"
          >
            <.icon name="plus" class="size-3" />
          </button>
        </:actions>
        <:menu :if={@can_edit}>
          <.flow_menu flow_id={@flow_id} flow={@flow} />
        </:menu>
        <.flow_tree_items
          :for={child <- @flow.children}
          flow={child}
          workspace={@workspace}
          project={@project}
          selected_flow_id={@selected_flow_id}
          can_edit={@can_edit}
        />
      </.tree_node>
    <% else %>
      <.tree_leaf
        label={@flow.name}
        icon="git-branch"
        href={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/flows/#{@flow.id}"}
        active={@is_selected}
        page_id={@flow_id}
        page_name={@flow.name}
        can_drag={@can_edit}
      >
        <:actions :if={@can_edit}>
          <button
            type="button"
            phx-click="create_child_flow"
            phx-value-parent-id={@flow.id}
            class="btn btn-ghost btn-xs btn-square"
            title={gettext("Add child flow")}
            onclick="event.preventDefault(); event.stopPropagation();"
          >
            <.icon name="plus" class="size-3" />
          </button>
        </:actions>
        <:menu :if={@can_edit}>
          <.flow_menu flow_id={@flow_id} flow={@flow} />
        </:menu>
      </.tree_leaf>
    <% end %>
    """
  end

  attr :flow_id, :string, required: true
  attr :flow, :map, required: true

  defp flow_menu(assigns) do
    ~H"""
    <div class="dropdown dropdown-end">
      <button
        type="button"
        tabindex="0"
        class="btn btn-ghost btn-xs btn-square"
        onclick="event.preventDefault(); event.stopPropagation();"
      >
        <.icon name="more-horizontal" class="size-4" />
      </button>
      <ul
        tabindex="0"
        class="dropdown-content menu menu-sm bg-base-100 rounded-box shadow-lg border border-base-300 w-40 z-50"
      >
        <li :if={!@flow.is_main}>
          <button
            type="button"
            phx-click="set_main_flow"
            phx-value-id={@flow_id}
            onclick="event.stopPropagation();"
          >
            <.icon name="star" class="size-4" />
            {gettext("Set as main")}
          </button>
        </li>
        <li>
          <button
            type="button"
            class="text-error"
            phx-click="delete_flow"
            phx-value-id={@flow_id}
            onclick="event.stopPropagation();"
          >
            <.icon name="trash-2" class="size-4" />
            {gettext("Move to Trash")}
          </button>
        </li>
      </ul>
    </div>
    """
  end

  defp has_flow_children?(flow) do
    case Map.get(flow, :children) do
      nil -> false
      [] -> false
      children when is_list(children) -> true
      _ -> false
    end
  end

  defp has_selected_flow_recursive?(flows, selected_id) when is_binary(selected_id) do
    Enum.any?(flows, fn flow ->
      to_string(flow.id) == selected_id or
        has_selected_flow_recursive?(Map.get(flow, :children, []), selected_id)
    end)
  end

  defp has_selected_flow_recursive?(_flows, _selected_id), do: false

  # Recursive component for rendering page tree items
  attr :page, :map, required: true
  attr :workspace, :map, required: true
  attr :project, :map, required: true
  attr :selected_page_id, :string, default: nil
  attr :can_edit, :boolean, default: false

  defp page_tree_items(assigns) do
    has_children = has_children?(assigns.page)
    is_selected = assigns.selected_page_id == to_string(assigns.page.id)

    is_expanded =
      has_children and
        has_selected_page_recursive?(assigns.page.children, assigns.selected_page_id)

    assigns =
      assigns
      |> assign(:has_children, has_children)
      |> assign(:is_selected, is_selected)
      |> assign(:is_expanded, is_expanded)
      |> assign(:page_id, to_string(assigns.page.id))
      |> assign(:avatar_url, get_avatar_url(assigns.page))

    ~H"""
    <%= if @has_children do %>
      <.tree_node
        id={"page-#{@page.id}"}
        label={@page.name}
        avatar_url={@avatar_url}
        expanded={@is_expanded}
        has_children={true}
        href={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/pages/#{@page.id}"}
        page_id={@page_id}
        page_name={@page.name}
        can_drag={@can_edit}
      >
        <:actions :if={@can_edit}>
          <button
            type="button"
            phx-click="create_child_page"
            phx-value-parent-id={@page.id}
            class="btn btn-ghost btn-xs btn-square"
            title={gettext("Add child page")}
            onclick="event.preventDefault(); event.stopPropagation();"
          >
            <.icon name="plus" class="size-3" />
          </button>
        </:actions>
        <:menu :if={@can_edit}>
          <.page_menu page_id={@page.id} />
        </:menu>
        <.page_tree_items
          :for={child <- @page.children}
          page={child}
          workspace={@workspace}
          project={@project}
          selected_page_id={@selected_page_id}
          can_edit={@can_edit}
        />
      </.tree_node>
    <% else %>
      <.tree_leaf
        label={@page.name}
        avatar_url={@avatar_url}
        href={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/pages/#{@page.id}"}
        active={@is_selected}
        page_id={@page_id}
        page_name={@page.name}
        can_drag={@can_edit}
      >
        <:actions :if={@can_edit}>
          <button
            type="button"
            phx-click="create_child_page"
            phx-value-parent-id={@page.id}
            class="btn btn-ghost btn-xs btn-square"
            title={gettext("Add child page")}
            onclick="event.preventDefault(); event.stopPropagation();"
          >
            <.icon name="plus" class="size-3" />
          </button>
        </:actions>
        <:menu :if={@can_edit}>
          <.page_menu page_id={@page.id} />
        </:menu>
      </.tree_leaf>
    <% end %>
    """
  end

  defp page_menu(assigns) do
    ~H"""
    <div class="dropdown dropdown-end">
      <button
        type="button"
        tabindex="0"
        class="btn btn-ghost btn-xs btn-square"
        onclick="event.preventDefault(); event.stopPropagation();"
      >
        <.icon name="more-horizontal" class="size-4" />
      </button>
      <ul
        tabindex="0"
        class="dropdown-content menu menu-sm bg-base-100 rounded-box shadow-lg border border-base-300 w-40 z-50"
      >
        <li>
          <button
            type="button"
            class="text-error"
            phx-click="delete_page"
            phx-value-id={@page_id}
            onclick="event.stopPropagation();"
          >
            <.icon name="trash-2" class="size-4" />
            {gettext("Move to Trash")}
          </button>
        </li>
      </ul>
    </div>
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

  defp get_avatar_url(%{avatar_asset: %{url: url}}) when is_binary(url), do: url
  defp get_avatar_url(_page), do: nil

  defp settings_page?(path, workspace_slug, project_slug) do
    String.contains?(path, "/workspaces/#{workspace_slug}/projects/#{project_slug}/settings")
  end

  defp trash_page?(path, workspace_slug, project_slug) do
    String.contains?(path, "/workspaces/#{workspace_slug}/projects/#{project_slug}/trash")
  end

  defp flows_page?(path, workspace_slug, project_slug) do
    String.contains?(path, "/workspaces/#{workspace_slug}/projects/#{project_slug}/flows")
  end

  defp pages_tool_page?(path, workspace_slug, project_slug) do
    String.contains?(path, "/workspaces/#{workspace_slug}/projects/#{project_slug}/pages")
  end
end

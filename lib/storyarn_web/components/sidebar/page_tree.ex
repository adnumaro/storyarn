defmodule StoryarnWeb.Components.Sidebar.PageTree do
  @moduledoc """
  Page tree components for the project sidebar.

  Renders: pages section with search, sortable tree, page menu.
  """

  use Phoenix.Component
  use StoryarnWeb, :verified_routes
  use Gettext, backend: StoryarnWeb.Gettext

  import StoryarnWeb.Components.CoreComponents
  import StoryarnWeb.Components.TreeComponents

  attr :pages_tree, :list, required: true
  attr :workspace, :map, required: true
  attr :project, :map, required: true
  attr :selected_page_id, :string, default: nil
  attr :can_edit, :boolean, default: false

  def pages_section(assigns) do
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

  attr :page, :map, required: true
  attr :workspace, :map, required: true
  attr :project, :map, required: true
  attr :selected_page_id, :string, default: nil
  attr :can_edit, :boolean, default: false

  def page_tree_items(assigns) do
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
end

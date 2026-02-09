defmodule StoryarnWeb.Components.Sidebar.SheetTree do
  @moduledoc """
  Sheet tree components for the project sidebar.

  Renders: sheets section with search, sortable tree, sheet menu.
  """

  use Phoenix.Component
  use StoryarnWeb, :verified_routes
  use Gettext, backend: StoryarnWeb.Gettext

  import StoryarnWeb.Components.CoreComponents
  import StoryarnWeb.Components.TreeComponents

  alias StoryarnWeb.Components.Sidebar.TreeHelpers

  attr :sheets_tree, :list, required: true
  attr :workspace, :map, required: true
  attr :project, :map, required: true
  attr :selected_sheet_id, :string, default: nil
  attr :can_edit, :boolean, default: false

  def sheets_section(assigns) do
    ~H"""
    <div>
      <div class="flex items-center justify-between mb-1">
        <.tree_section label={gettext("Sheets")} />
        <button
          :if={@can_edit}
          type="button"
          phx-click="create_sheet"
          class="btn btn-ghost btn-xs"
          title={gettext("New Sheet")}
        >
          <.icon name="plus" class="size-3" />
        </button>
      </div>

      <%!-- Search input --%>
      <div
        :if={@sheets_tree != []}
        id="sheets-tree-search"
        phx-hook="TreeSearch"
        data-tree-id="sheets-tree-container"
        class="mb-2"
      >
        <input
          type="text"
          data-tree-search-input
          placeholder={gettext("Filter sheets...")}
          class="input input-xs input-bordered w-full"
        />
      </div>

      <div :if={@sheets_tree == []} class="text-sm text-base-content/50 px-4 py-2">
        {gettext("No sheets yet")}
      </div>

      <%!-- Tree container with sortable support --%>
      <div
        :if={@sheets_tree != []}
        id="sheets-tree-container"
        phx-hook={if @can_edit, do: "SortableTree", else: nil}
      >
        <div data-sortable-container data-parent-id="">
          <.sheet_tree_items
            :for={sheet <- @sheets_tree}
            sheet={sheet}
            workspace={@workspace}
            project={@project}
            selected_sheet_id={@selected_sheet_id}
            can_edit={@can_edit}
          />
        </div>
      </div>
    </div>
    """
  end

  attr :sheet, :map, required: true
  attr :workspace, :map, required: true
  attr :project, :map, required: true
  attr :selected_sheet_id, :string, default: nil
  attr :can_edit, :boolean, default: false

  def sheet_tree_items(assigns) do
    has_children = TreeHelpers.has_children?(assigns.sheet)
    is_selected = assigns.selected_sheet_id == to_string(assigns.sheet.id)

    is_expanded =
      has_children and
        TreeHelpers.has_selected_recursive?(assigns.sheet.children, assigns.selected_sheet_id)

    assigns =
      assigns
      |> assign(:has_children, has_children)
      |> assign(:is_selected, is_selected)
      |> assign(:is_expanded, is_expanded)
      |> assign(:sheet_id, to_string(assigns.sheet.id))
      |> assign(:avatar_url, get_avatar_url(assigns.sheet))

    ~H"""
    <%= if @has_children do %>
      <.tree_node
        id={"sheet-#{@sheet.id}"}
        label={@sheet.name}
        avatar_url={@avatar_url}
        expanded={@is_expanded}
        has_children={true}
        href={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/sheets/#{@sheet.id}"}
        item_id={@sheet_id}
        item_name={@sheet.name}
        can_drag={@can_edit}
      >
        <:actions :if={@can_edit}>
          <button
            type="button"
            phx-click="create_child_sheet"
            phx-value-parent-id={@sheet.id}
            class="btn btn-ghost btn-xs btn-square"
            title={gettext("Add child sheet")}
            onclick="event.preventDefault(); event.stopPropagation();"
          >
            <.icon name="plus" class="size-3" />
          </button>
        </:actions>
        <:menu :if={@can_edit}>
          <.sheet_menu sheet_id={@sheet.id} />
        </:menu>
        <.sheet_tree_items
          :for={child <- @sheet.children}
          sheet={child}
          workspace={@workspace}
          project={@project}
          selected_sheet_id={@selected_sheet_id}
          can_edit={@can_edit}
        />
      </.tree_node>
    <% else %>
      <.tree_leaf
        label={@sheet.name}
        avatar_url={@avatar_url}
        href={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/sheets/#{@sheet.id}"}
        active={@is_selected}
        item_id={@sheet_id}
        item_name={@sheet.name}
        can_drag={@can_edit}
      >
        <:actions :if={@can_edit}>
          <button
            type="button"
            phx-click="create_child_sheet"
            phx-value-parent-id={@sheet.id}
            class="btn btn-ghost btn-xs btn-square"
            title={gettext("Add child sheet")}
            onclick="event.preventDefault(); event.stopPropagation();"
          >
            <.icon name="plus" class="size-3" />
          </button>
        </:actions>
        <:menu :if={@can_edit}>
          <.sheet_menu sheet_id={@sheet.id} />
        </:menu>
      </.tree_leaf>
    <% end %>
    """
  end

  defp sheet_menu(assigns) do
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
            phx-click="delete_sheet"
            phx-value-id={@sheet_id}
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

  defp get_avatar_url(%{avatar_asset: %{url: url}}) when is_binary(url), do: url
  defp get_avatar_url(_sheet), do: nil
end

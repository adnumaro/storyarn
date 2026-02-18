defmodule StoryarnWeb.Components.Sidebar.MapTree do
  @moduledoc """
  Map tree components for the project sidebar.

  Renders: maps section with search, sortable tree, map menu.
  """

  use Phoenix.Component
  use StoryarnWeb, :verified_routes
  use Gettext, backend: StoryarnWeb.Gettext

  alias Phoenix.LiveView.JS

  import StoryarnWeb.Components.CoreComponents
  import StoryarnWeb.Components.TreeComponents

  alias StoryarnWeb.Components.Sidebar.TreeHelpers

  attr :maps_tree, :list, required: true
  attr :workspace, :map, required: true
  attr :project, :map, required: true
  attr :selected_map_id, :string, default: nil
  attr :can_edit, :boolean, default: false

  def maps_section(assigns) do
    ~H"""
    <div>
      <div class="flex items-center justify-between mb-1">
        <.tree_section label={gettext("Maps")} />
        <button
          :if={@can_edit}
          type="button"
          phx-click="create_map"
          class="btn btn-ghost btn-xs"
          title={gettext("New Map")}
        >
          <.icon name="plus" class="size-3" />
        </button>
      </div>

      <%!-- Search input --%>
      <div
        :if={@maps_tree != []}
        id="maps-tree-search"
        phx-hook="TreeSearch"
        data-tree-id="maps-tree-container"
        class="mb-2"
      >
        <input
          type="text"
          data-tree-search-input
          placeholder={gettext("Filter maps...")}
          class="input input-xs input-bordered w-full"
        />
      </div>

      <div :if={@maps_tree == []} class="text-sm text-base-content/50 px-4 py-2">
        {gettext("No maps yet")}
      </div>

      <%!-- Tree container with sortable support --%>
      <div
        :if={@maps_tree != []}
        id="maps-tree-container"
        phx-hook={if @can_edit, do: "SortableTree", else: nil}
        data-tree-type="maps"
      >
        <div data-sortable-container data-parent-id="">
          <.map_tree_items
            :for={map <- @maps_tree}
            map={map}
            workspace={@workspace}
            project={@project}
            selected_map_id={@selected_map_id}
            can_edit={@can_edit}
          />
        </div>
      </div>

      <.confirm_modal
        :if={@can_edit}
        id="delete-map-sidebar-confirm"
        title={gettext("Delete map?")}
        message={gettext("Are you sure you want to delete this map?")}
        confirm_text={gettext("Delete")}
        confirm_variant="error"
        icon="alert-triangle"
        on_confirm={JS.push("confirm_delete_map")}
      />
    </div>
    """
  end

  attr :map, :map, required: true
  attr :workspace, :map, required: true
  attr :project, :map, required: true
  attr :selected_map_id, :string, default: nil
  attr :can_edit, :boolean, default: false

  def map_tree_items(assigns) do
    has_children = TreeHelpers.has_children?(assigns.map)
    is_selected = assigns.selected_map_id == to_string(assigns.map.id)

    is_expanded =
      has_children and
        TreeHelpers.has_selected_recursive?(assigns.map.children, assigns.selected_map_id)

    assigns =
      assigns
      |> assign(:has_children, has_children)
      |> assign(:is_selected, is_selected)
      |> assign(:is_expanded, is_expanded)
      |> assign(:map_id, to_string(assigns.map.id))

    ~H"""
    <%= if @has_children do %>
      <.tree_node
        id={"map-#{@map.id}"}
        label={@map.name}
        icon="map"
        expanded={@is_expanded}
        has_children={true}
        href={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/maps/#{@map.id}"}
        item_id={@map_id}
        item_name={@map.name}
        can_drag={@can_edit}
      >
        <:actions :if={@can_edit}>
          <button
            type="button"
            phx-click="create_child_map"
            phx-value-parent-id={@map.id}
            class="btn btn-ghost btn-xs btn-square"
            title={gettext("Add child map")}
            onclick="event.preventDefault(); event.stopPropagation();"
          >
            <.icon name="plus" class="size-3" />
          </button>
        </:actions>
        <:menu :if={@can_edit}>
          <.map_menu map_id={@map_id} />
        </:menu>
        <.map_tree_items
          :for={child <- @map.children}
          map={child}
          workspace={@workspace}
          project={@project}
          selected_map_id={@selected_map_id}
          can_edit={@can_edit}
        />
      </.tree_node>
    <% else %>
      <.tree_leaf
        label={@map.name}
        icon="map"
        href={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/maps/#{@map.id}"}
        active={@is_selected}
        item_id={@map_id}
        item_name={@map.name}
        can_drag={@can_edit}
      >
        <:actions :if={@can_edit}>
          <button
            type="button"
            phx-click="create_child_map"
            phx-value-parent-id={@map.id}
            class="btn btn-ghost btn-xs btn-square"
            title={gettext("Add child map")}
            onclick="event.preventDefault(); event.stopPropagation();"
          >
            <.icon name="plus" class="size-3" />
          </button>
        </:actions>
        <:menu :if={@can_edit}>
          <.map_menu map_id={@map_id} />
        </:menu>
      </.tree_leaf>
    <% end %>
    """
  end

  defp map_menu(assigns) do
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
            phx-click={
              JS.push("set_pending_delete_map", value: %{id: @map_id})
              |> show_modal("delete-map-sidebar-confirm")
            }
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
end

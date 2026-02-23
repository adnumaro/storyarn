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
          placeholder={dgettext("maps", "Filter maps...")}
          class="input input-sm input-bordered w-full"
        />
      </div>

      <div :if={@maps_tree == []} class="text-sm text-base-content/50 px-4 py-2">
        {dgettext("maps", "No maps yet")}
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

      <%!-- Add new button (full width, below tree) --%>
      <button
        :if={@can_edit}
        type="button"
        phx-click="create_map"
        class="btn btn-ghost btn-sm w-full gap-1.5 mt-1 text-base-content/50 hover:text-base-content"
      >
        <.icon name="plus" class="size-4" />
        {dgettext("maps", "New Map")}
      </button>

      <.confirm_modal
        :if={@can_edit}
        id="delete-map-sidebar-confirm"
        title={dgettext("maps", "Delete map?")}
        message={dgettext("maps", "Are you sure you want to delete this map?")}
        confirm_text={dgettext("maps", "Delete")}
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
    has_child_maps = TreeHelpers.has_children?(assigns.map)

    has_elements =
      Map.get(assigns.map, :sidebar_zones, []) != [] or
        Map.get(assigns.map, :sidebar_pins, []) != []

    has_children = has_child_maps or has_elements
    is_selected = assigns.selected_map_id == to_string(assigns.map.id)

    is_expanded =
      has_children and
        (has_elements or
           TreeHelpers.has_selected_recursive?(assigns.map.children, assigns.selected_map_id))

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
            title={dgettext("maps", "Add child map")}
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

        <%!-- Zone element leaves --%>
        <.element_leaves
          items={Map.get(@map, :sidebar_zones, [])}
          total_count={Map.get(@map, :zone_count, 0)}
          icon="pentagon"
          map_id={@map.id}
          workspace={@workspace}
          project={@project}
          element_type="zone"
          label_fn={& &1.name}
          more_text={
            dgettext("maps", "%{count} more zones\u2026",
              count: Map.get(@map, :zone_count, 0) - length(Map.get(@map, :sidebar_zones, []))
            )
          }
        />

        <%!-- Pin element leaves --%>
        <.element_leaves
          items={Map.get(@map, :sidebar_pins, [])}
          total_count={Map.get(@map, :pin_count, 0)}
          icon="map-pin"
          map_id={@map.id}
          workspace={@workspace}
          project={@project}
          element_type="pin"
          label_fn={&(&1.label || dgettext("maps", "Pin"))}
          more_text={
            dgettext("maps", "%{count} more pins\u2026",
              count: Map.get(@map, :pin_count, 0) - length(Map.get(@map, :sidebar_pins, []))
            )
          }
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
            title={dgettext("maps", "Add child map")}
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

  attr :items, :list, required: true
  attr :total_count, :integer, required: true
  attr :icon, :string, required: true
  attr :map_id, :any, required: true
  attr :workspace, :map, required: true
  attr :project, :map, required: true
  attr :element_type, :string, required: true
  attr :label_fn, :any, required: true
  attr :more_text, :string, required: true

  defp element_leaves(assigns) do
    base =
      ~p"/workspaces/#{assigns.workspace.slug}/projects/#{assigns.project.slug}/maps/#{assigns.map_id}"

    assigns =
      assign(
        assigns,
        :items_with_href,
        Enum.map(assigns.items, fn item ->
          {item, "#{base}?highlight=#{assigns.element_type}:#{item.id}"}
        end)
      )

    ~H"""
    <.tree_leaf
      :for={{item, href} <- @items_with_href}
      label={@label_fn.(item)}
      icon={@icon}
      href={href}
      active={false}
      item_id={"#{@element_type}-#{item.id}"}
      item_name={@label_fn.(item)}
      can_drag={false}
    />
    <div :if={@total_count > length(@items)} class="text-xs text-base-content/40 pl-8 py-0.5">
      {@more_text}
    </div>
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
            {dgettext("maps", "Move to Trash")}
          </button>
        </li>
      </ul>
    </div>
    """
  end
end

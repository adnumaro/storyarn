defmodule StoryarnWeb.Components.Sidebar.GenericTree do
  @moduledoc """
  Generic sidebar tree component shared by sheets, flows, screenplays, and scenes.

  Provides the common structure: search input, sortable container, tree items
  (recursive nodes/leaves), context menu with delete, and create button.

  Each domain-specific tree module (SheetTree, FlowTree, etc.) is a thin wrapper
  that calls these components with the appropriate configuration.
  """

  use Phoenix.Component

  alias Phoenix.LiveView.JS

  import StoryarnWeb.Components.CoreComponents
  import StoryarnWeb.Components.TreeComponents

  alias StoryarnWeb.Components.Sidebar.TreeHelpers

  # ── Section ────────────────────────────────────────────────────────────

  attr :tree, :list, required: true, doc: "the tree data (list of root entities)"
  attr :workspace, :map, required: true
  attr :project, :map, required: true
  attr :selected_id, :string, default: nil, doc: "currently selected entity id"
  attr :can_edit, :boolean, default: false

  attr :entity_type, :string, required: true, doc: "type key: sheets, flows, screenplays, scenes"
  attr :search_placeholder, :string, required: true
  attr :empty_text, :string, required: true
  attr :create_event, :string, required: true
  attr :create_label, :string, required: true
  attr :delete_title, :string, required: true
  attr :delete_message, :string, required: true
  attr :delete_confirm_text, :string, required: true
  attr :confirm_delete_event, :string, required: true

  attr :icon, :string, default: nil, doc: "Lucide icon name for tree items"
  attr :avatar_fn, :any, default: nil, doc: "function (entity) -> url | nil, for sheet avatars"
  attr :href_fn, :any, required: true, doc: "function (workspace, project, entity) -> path"
  attr :link_type, :atom, default: :navigate, values: [:navigate, :patch]
  attr :create_child_event, :string, required: true
  attr :create_child_title, :string, required: true
  attr :set_pending_delete_event, :string, required: true
  attr :delete_label, :string, required: true, doc: "translated label for the delete menu item"

  slot :extra_menu_items, doc: "extra menu items per entity (receives entity via :let)"

  slot :extra_children,
    doc: "extra content inside tree_node after recursive children (receives entity via :let)"

  def entity_tree_section(assigns) do
    singular = String.trim_trailing(assigns.entity_type, "s")
    delete_modal_id = "delete-#{singular}-sidebar-confirm"
    tree_type_attr = if assigns.entity_type != "sheets", do: assigns.entity_type, else: nil

    assigns =
      assigns
      |> assign(:delete_modal_id, delete_modal_id)
      |> assign(:tree_type_attr, tree_type_attr)

    ~H"""
    <div>
      <%!-- Search input --%>
      <div
        :if={@tree != []}
        id={"#{@entity_type}-tree-search"}
        phx-hook="TreeSearch"
        data-tree-id={"#{@entity_type}-tree-container"}
        class="mb-2"
      >
        <input
          type="text"
          data-tree-search-input
          placeholder={@search_placeholder}
          class="input input-sm input-bordered w-full"
        />
      </div>

      <div :if={@tree == []} class="text-sm text-base-content/50 px-4 py-2">
        {@empty_text}
      </div>

      <%!-- Tree container with sortable support --%>
      <div
        :if={@tree != []}
        id={"#{@entity_type}-tree-container"}
        phx-hook={if @can_edit, do: "SortableTree", else: nil}
        data-tree-type={@tree_type_attr}
      >
        <div data-sortable-container data-parent-id="" class="flex flex-col gap-1">
          <.entity_tree_items
            :for={entity <- @tree}
            entity={entity}
            workspace={@workspace}
            project={@project}
            selected_id={@selected_id}
            can_edit={@can_edit}
            entity_type={@entity_type}
            icon={@icon}
            avatar_fn={@avatar_fn}
            href_fn={@href_fn}
            link_type={@link_type}
            create_child_event={@create_child_event}
            create_child_title={@create_child_title}
            set_pending_delete_event={@set_pending_delete_event}
            delete_modal_id={@delete_modal_id}
            delete_label={@delete_label}
            extra_menu_items={@extra_menu_items}
            extra_children={@extra_children}
          />
        </div>
      </div>

      <%!-- Add new button (full width, below tree) --%>
      <button
        :if={@can_edit}
        type="button"
        phx-click={@create_event}
        class="btn btn-ghost btn-sm w-full gap-1.5 mt-1 text-base-content/50 hover:text-base-content"
      >
        <.icon name="plus" class="size-4" />
        {@create_label}
      </button>

      <.confirm_modal
        :if={@can_edit}
        id={@delete_modal_id}
        title={@delete_title}
        message={@delete_message}
        confirm_text={@delete_confirm_text}
        confirm_variant="error"
        icon="alert-triangle"
        on_confirm={JS.push(@confirm_delete_event)}
      />
    </div>
    """
  end

  # ── Tree items (recursive) ────────────────────────────────────────────

  attr :entity, :map, required: true
  attr :workspace, :map, required: true
  attr :project, :map, required: true
  attr :selected_id, :string, default: nil
  attr :can_edit, :boolean, default: false

  attr :entity_type, :string, required: true
  attr :icon, :string, default: nil
  attr :avatar_fn, :any, default: nil
  attr :href_fn, :any, required: true
  attr :link_type, :atom, default: :navigate, values: [:navigate, :patch]
  attr :create_child_event, :string, required: true
  attr :create_child_title, :string, required: true
  attr :set_pending_delete_event, :string, required: true
  attr :delete_modal_id, :string, required: true
  attr :delete_label, :string, required: true
  attr :extra_menu_items, :any, default: [], doc: "slot data for extra menu items"
  attr :extra_children, :any, default: [], doc: "slot data for extra children content"

  def entity_tree_items(assigns) do
    entity = assigns.entity
    has_child_entities = TreeHelpers.has_children?(entity)

    has_extra_children =
      assigns.extra_children != [] and has_extra_children_content?(entity, assigns.entity_type)

    has_children = has_child_entities or has_extra_children
    is_selected = assigns.selected_id == to_string(entity.id)

    is_expanded =
      has_children and
        (has_extra_children or
           TreeHelpers.has_selected_recursive?(
             Map.get(entity, :children, []),
             assigns.selected_id
           ))

    entity_id_str = to_string(entity.id)
    id_prefix = String.trim_trailing(assigns.entity_type, "s")
    href = assigns.href_fn.(assigns.workspace, assigns.project, entity)

    avatar_url =
      if assigns.avatar_fn do
        assigns.avatar_fn.(entity)
      else
        nil
      end

    assigns =
      assigns
      |> assign(:has_children, has_children)
      |> assign(:is_selected, is_selected)
      |> assign(:is_expanded, is_expanded)
      |> assign(:entity_id_str, entity_id_str)
      |> assign(:id_prefix, id_prefix)
      |> assign(:href, href)
      |> assign(:avatar_url, avatar_url)

    ~H"""
    <%= if @has_children do %>
      <.tree_node
        id={"#{@id_prefix}-#{@entity.id}"}
        label={@entity.name}
        icon={@icon}
        avatar_url={@avatar_url}
        active={@is_selected}
        expanded={@is_expanded}
        has_children={true}
        href={@href}
        item_id={@entity_id_str}
        item_name={@entity.name}
        can_drag={@can_edit}
        link_type={@link_type}
      >
        <:actions :if={@can_edit}>
          <button
            type="button"
            phx-click={@create_child_event}
            phx-value-parent-id={@entity.id}
            class="btn btn-ghost btn-xs btn-square"
            title={@create_child_title}
            onclick="event.preventDefault(); event.stopPropagation();"
          >
            <.icon name="plus" class="size-3" />
          </button>
        </:actions>
        <:menu :if={@can_edit}>
          <.entity_menu
            entity_id={@entity_id_str}
            entity={@entity}
            set_pending_delete_event={@set_pending_delete_event}
            delete_modal_id={@delete_modal_id}
            delete_label={@delete_label}
            extra_menu_items={@extra_menu_items}
          />
        </:menu>
        <%!-- Recursive children --%>
        <.entity_tree_items
          :for={child <- Map.get(@entity, :children, [])}
          entity={child}
          workspace={@workspace}
          project={@project}
          selected_id={@selected_id}
          can_edit={@can_edit}
          entity_type={@entity_type}
          icon={@icon}
          avatar_fn={@avatar_fn}
          href_fn={@href_fn}
          link_type={@link_type}
          create_child_event={@create_child_event}
          create_child_title={@create_child_title}
          set_pending_delete_event={@set_pending_delete_event}
          delete_modal_id={@delete_modal_id}
          delete_label={@delete_label}
          extra_menu_items={@extra_menu_items}
          extra_children={@extra_children}
        />
        <%!-- Extra children (e.g. scene zones/pins) --%>
        {render_slot(@extra_children, @entity)}
      </.tree_node>
    <% else %>
      <.tree_leaf
        label={@entity.name}
        icon={@icon}
        avatar_url={@avatar_url}
        href={@href}
        active={@is_selected}
        item_id={@entity_id_str}
        item_name={@entity.name}
        can_drag={@can_edit}
        link_type={@link_type}
      >
        <:actions :if={@can_edit}>
          <button
            type="button"
            phx-click={@create_child_event}
            phx-value-parent-id={@entity.id}
            class="btn btn-ghost btn-xs btn-square"
            title={@create_child_title}
            onclick="event.preventDefault(); event.stopPropagation();"
          >
            <.icon name="plus" class="size-3" />
          </button>
        </:actions>
        <:menu :if={@can_edit}>
          <.entity_menu
            entity_id={@entity_id_str}
            entity={@entity}
            set_pending_delete_event={@set_pending_delete_event}
            delete_modal_id={@delete_modal_id}
            delete_label={@delete_label}
            extra_menu_items={@extra_menu_items}
          />
        </:menu>
      </.tree_leaf>
    <% end %>
    """
  end

  # ── Context menu ───────────────────────────────────────────────────────

  attr :entity_id, :string, required: true
  attr :entity, :map, required: true
  attr :set_pending_delete_event, :string, required: true
  attr :delete_modal_id, :string, required: true
  attr :delete_label, :string, required: true
  attr :extra_menu_items, :any, default: []

  defp entity_menu(assigns) do
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
        {render_slot(@extra_menu_items, @entity)}
        <li>
          <button
            type="button"
            class="text-error"
            phx-click={
              JS.push(@set_pending_delete_event, value: %{id: @entity_id})
              |> show_modal(@delete_modal_id)
            }
            onclick="event.stopPropagation();"
          >
            <.icon name="trash-2" class="size-4" />
            {@delete_label}
          </button>
        </li>
      </ul>
    </div>
    """
  end

  # ── Helpers ────────────────────────────────────────────────────────────

  # Scene entities may have extra children (zones/pins) that expand the tree node
  defp has_extra_children_content?(entity, "scenes") do
    Map.get(entity, :sidebar_zones, []) != [] or
      Map.get(entity, :sidebar_pins, []) != []
  end

  defp has_extra_children_content?(_entity, _type), do: false
end

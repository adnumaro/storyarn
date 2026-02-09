defmodule StoryarnWeb.Components.Sidebar.ScreenplayTree do
  @moduledoc """
  Screenplay tree components for the project sidebar.

  Renders: screenplays section with search, sortable tree, screenplay menu.
  """

  use Phoenix.Component
  use StoryarnWeb, :verified_routes
  use Gettext, backend: StoryarnWeb.Gettext

  import StoryarnWeb.Components.CoreComponents
  import StoryarnWeb.Components.TreeComponents

  alias StoryarnWeb.Components.Sidebar.TreeHelpers

  attr :screenplays_tree, :list, required: true
  attr :workspace, :map, required: true
  attr :project, :map, required: true
  attr :selected_screenplay_id, :string, default: nil
  attr :can_edit, :boolean, default: false

  def screenplays_section(assigns) do
    ~H"""
    <div>
      <div class="flex items-center justify-between mb-1">
        <.tree_section label={gettext("Screenplays")} />
        <button
          :if={@can_edit}
          type="button"
          phx-click="create_screenplay"
          class="btn btn-ghost btn-xs"
          title={gettext("New Screenplay")}
        >
          <.icon name="plus" class="size-3" />
        </button>
      </div>

      <%!-- Search input --%>
      <div
        :if={@screenplays_tree != []}
        id="screenplays-tree-search"
        phx-hook="TreeSearch"
        data-tree-id="screenplays-tree-container"
        class="mb-2"
      >
        <input
          type="text"
          data-tree-search-input
          placeholder={gettext("Filter screenplays...")}
          class="input input-xs input-bordered w-full"
        />
      </div>

      <div :if={@screenplays_tree == []} class="text-sm text-base-content/50 px-4 py-2">
        {gettext("No screenplays yet")}
      </div>

      <%!-- Tree container with sortable support --%>
      <div
        :if={@screenplays_tree != []}
        id="screenplays-tree-container"
        phx-hook={if @can_edit, do: "SortableTree", else: nil}
        data-tree-type="screenplays"
      >
        <div data-sortable-container data-parent-id="">
          <.screenplay_tree_items
            :for={screenplay <- @screenplays_tree}
            screenplay={screenplay}
            workspace={@workspace}
            project={@project}
            selected_screenplay_id={@selected_screenplay_id}
            can_edit={@can_edit}
          />
        </div>
      </div>
    </div>
    """
  end

  attr :screenplay, :map, required: true
  attr :workspace, :map, required: true
  attr :project, :map, required: true
  attr :selected_screenplay_id, :string, default: nil
  attr :can_edit, :boolean, default: false

  def screenplay_tree_items(assigns) do
    has_children = TreeHelpers.has_children?(assigns.screenplay)
    is_selected = assigns.selected_screenplay_id == to_string(assigns.screenplay.id)

    is_expanded =
      has_children and
        TreeHelpers.has_selected_recursive?(
          assigns.screenplay.children,
          assigns.selected_screenplay_id
        )

    assigns =
      assigns
      |> assign(:has_children, has_children)
      |> assign(:is_selected, is_selected)
      |> assign(:is_expanded, is_expanded)
      |> assign(:screenplay_id, to_string(assigns.screenplay.id))

    ~H"""
    <%= if @has_children do %>
      <.tree_node
        id={"screenplay-#{@screenplay.id}"}
        label={@screenplay.name}
        icon="scroll-text"
        expanded={@is_expanded}
        has_children={true}
        href={
          ~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/screenplays/#{@screenplay.id}"
        }
        item_id={@screenplay_id}
        item_name={@screenplay.name}
        can_drag={@can_edit}
      >
        <:actions :if={@can_edit}>
          <button
            type="button"
            phx-click="create_child_screenplay"
            phx-value-parent-id={@screenplay.id}
            class="btn btn-ghost btn-xs btn-square"
            title={gettext("Add child screenplay")}
            onclick="event.preventDefault(); event.stopPropagation();"
          >
            <.icon name="plus" class="size-3" />
          </button>
        </:actions>
        <:menu :if={@can_edit}>
          <.screenplay_menu screenplay_id={@screenplay_id} />
        </:menu>
        <.screenplay_tree_items
          :for={child <- @screenplay.children}
          screenplay={child}
          workspace={@workspace}
          project={@project}
          selected_screenplay_id={@selected_screenplay_id}
          can_edit={@can_edit}
        />
      </.tree_node>
    <% else %>
      <.tree_leaf
        label={@screenplay.name}
        icon="scroll-text"
        href={
          ~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/screenplays/#{@screenplay.id}"
        }
        active={@is_selected}
        item_id={@screenplay_id}
        item_name={@screenplay.name}
        can_drag={@can_edit}
      >
        <:actions :if={@can_edit}>
          <button
            type="button"
            phx-click="create_child_screenplay"
            phx-value-parent-id={@screenplay.id}
            class="btn btn-ghost btn-xs btn-square"
            title={gettext("Add child screenplay")}
            onclick="event.preventDefault(); event.stopPropagation();"
          >
            <.icon name="plus" class="size-3" />
          </button>
        </:actions>
        <:menu :if={@can_edit}>
          <.screenplay_menu screenplay_id={@screenplay_id} />
        </:menu>
      </.tree_leaf>
    <% end %>
    """
  end

  defp screenplay_menu(assigns) do
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
            phx-click="delete_screenplay"
            phx-value-id={@screenplay_id}
            data-confirm={gettext("Are you sure you want to delete this screenplay?")}
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

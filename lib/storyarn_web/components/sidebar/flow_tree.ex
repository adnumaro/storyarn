defmodule StoryarnWeb.Components.Sidebar.FlowTree do
  @moduledoc """
  Flow tree components for the project sidebar.

  Renders: flows section with search, sortable tree, flow menu.
  """

  use Phoenix.Component
  use StoryarnWeb, :verified_routes
  use Gettext, backend: StoryarnWeb.Gettext

  import StoryarnWeb.Components.CoreComponents
  import StoryarnWeb.Components.TreeComponents

  attr :flows_tree, :list, required: true
  attr :workspace, :map, required: true
  attr :project, :map, required: true
  attr :selected_flow_id, :string, default: nil
  attr :can_edit, :boolean, default: false

  def flows_section(assigns) do
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

  attr :flow, :map, required: true
  attr :workspace, :map, required: true
  attr :project, :map, required: true
  attr :selected_flow_id, :string, default: nil
  attr :can_edit, :boolean, default: false

  def flow_tree_items(assigns) do
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
        sheet_id={@flow_id}
        sheet_name={@flow.name}
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
        sheet_id={@flow_id}
        sheet_name={@flow.name}
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
end

defmodule StoryarnWeb.Components.Sidebar.FlowTree do
  @moduledoc """
  Flow tree components for the project sidebar.

  Thin wrapper around `GenericTree` with flow-specific configuration.
  Includes the "Set as main" extra menu item.
  """

  use Phoenix.Component
  use StoryarnWeb, :verified_routes
  use Gettext, backend: StoryarnWeb.Gettext

  import StoryarnWeb.Components.CoreComponents
  import StoryarnWeb.Components.Sidebar.GenericTree

  attr :flows_tree, :list, required: true
  attr :workspace, :map, required: true
  attr :project, :map, required: true
  attr :selected_flow_id, :string, default: nil
  attr :can_edit, :boolean, default: false

  def flows_section(assigns) do
    ~H"""
    <.entity_tree_section
      tree={@flows_tree}
      workspace={@workspace}
      project={@project}
      selected_id={@selected_flow_id}
      can_edit={@can_edit}
      entity_type="flows"
      link_type={:patch}
      search_placeholder={dgettext("flows", "Filter flows...")}
      empty_text={dgettext("flows", "No flows yet")}
      create_event="create_flow"
      create_label={dgettext("flows", "New Flow")}
      delete_title={dgettext("flows", "Delete flow?")}
      delete_message={dgettext("flows", "Are you sure you want to delete this flow?")}
      delete_confirm_text={dgettext("flows", "Delete")}
      confirm_delete_event="confirm_delete_flow"
      icon="git-branch"
      href_fn={&flow_href/3}
      create_child_event="create_child_flow"
      create_child_title={dgettext("flows", "Add child flow")}
      set_pending_delete_event="set_pending_delete_flow"
      delete_label={dgettext("flows", "Move to Trash")}
    >
      <:extra_menu_items :let={flow}>
        <li :if={!flow.is_main}>
          <button
            type="button"
            phx-click="set_main_flow"
            phx-value-id={to_string(flow.id)}
            onclick="event.stopPropagation();"
          >
            <.icon name="star" class="size-4" />
            {dgettext("flows", "Set as main")}
          </button>
        </li>
      </:extra_menu_items>
    </.entity_tree_section>
    """
  end

  def delete_modal(assigns) do
    ~H"""
    <.entity_delete_modal
      entity_type="flows"
      title={dgettext("flows", "Delete flow?")}
      message={dgettext("flows", "Are you sure you want to delete this flow?")}
      confirm_text={dgettext("flows", "Delete")}
      confirm_event="confirm_delete_flow"
    />
    """
  end

  defp flow_href(workspace, project, flow) do
    ~p"/workspaces/#{workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
  end
end

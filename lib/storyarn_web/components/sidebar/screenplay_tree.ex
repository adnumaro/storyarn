defmodule StoryarnWeb.Components.Sidebar.ScreenplayTree do
  @moduledoc """
  Screenplay tree components for the project sidebar.

  Thin wrapper around `GenericTree` with screenplay-specific configuration.
  """

  use Phoenix.Component
  use StoryarnWeb, :verified_routes
  use Gettext, backend: Storyarn.Gettext

  import StoryarnWeb.Components.Sidebar.GenericTree

  attr :screenplays_tree, :list, required: true
  attr :workspace, :map, required: true
  attr :project, :map, required: true
  attr :selected_screenplay_id, :string, default: nil
  attr :can_edit, :boolean, default: false

  def screenplays_section(assigns) do
    ~H"""
    <.entity_tree_section
      tree={@screenplays_tree}
      workspace={@workspace}
      project={@project}
      selected_id={@selected_screenplay_id}
      can_edit={@can_edit}
      entity_type="screenplays"
      search_placeholder={dgettext("screenplays", "Filter screenplays...")}
      empty_text={dgettext("screenplays", "No screenplays yet")}
      create_event="create_screenplay"
      create_label={dgettext("screenplays", "New Screenplay")}
      delete_title={dgettext("screenplays", "Delete screenplay?")}
      delete_message={dgettext("screenplays", "Are you sure you want to delete this screenplay?")}
      delete_confirm_text={dgettext("screenplays", "Delete")}
      confirm_delete_event="confirm_delete_screenplay"
      icon="scroll-text"
      href_fn={&screenplay_href/3}
      link_type={:patch}
      create_child_event="create_child_screenplay"
      create_child_title={dgettext("screenplays", "Add child screenplay")}
      set_pending_delete_event="set_pending_delete_screenplay"
      delete_label={dgettext("screenplays", "Move to Trash")}
    />
    """
  end

  def delete_modal(assigns) do
    ~H"""
    <.entity_delete_modal
      entity_type="screenplays"
      title={dgettext("screenplays", "Delete screenplay?")}
      message={dgettext("screenplays", "Are you sure you want to delete this screenplay?")}
      confirm_text={dgettext("screenplays", "Delete")}
      confirm_event="confirm_delete_screenplay"
    />
    """
  end

  defp screenplay_href(workspace, project, screenplay) do
    ~p"/workspaces/#{workspace.slug}/projects/#{project.slug}/screenplays/#{screenplay.id}"
  end
end

defmodule StoryarnWeb.Components.Sidebar.SheetTree do
  @moduledoc """
  Sheet tree components for the project sidebar.

  Thin wrapper around `GenericTree` with sheet-specific configuration.
  """

  use Phoenix.Component
  use StoryarnWeb, :verified_routes
  use Gettext, backend: StoryarnWeb.Gettext

  import StoryarnWeb.Components.Sidebar.GenericTree

  attr :sheets_tree, :list, required: true
  attr :workspace, :map, required: true
  attr :project, :map, required: true
  attr :selected_sheet_id, :string, default: nil
  attr :can_edit, :boolean, default: false

  def sheets_section(assigns) do
    ~H"""
    <.entity_tree_section
      tree={@sheets_tree}
      workspace={@workspace}
      project={@project}
      selected_id={@selected_sheet_id}
      can_edit={@can_edit}
      entity_type="sheets"
      search_placeholder={dgettext("sheets", "Filter sheets...")}
      empty_text={dgettext("sheets", "No sheets yet")}
      create_event="create_sheet"
      create_label={dgettext("sheets", "New Sheet")}
      delete_title={dgettext("sheets", "Delete sheet?")}
      delete_message={dgettext("sheets", "Are you sure you want to delete this sheet?")}
      delete_confirm_text={dgettext("sheets", "Delete")}
      confirm_delete_event="confirm_delete_sheet"
      avatar_fn={&get_avatar_url/1}
      href_fn={&sheet_href/3}
      create_child_event="create_child_sheet"
      create_child_title={dgettext("sheets", "Add child sheet")}
      set_pending_delete_event="set_pending_delete_sheet"
      delete_label={dgettext("sheets", "Move to Trash")}
    />
    """
  end

  defp sheet_href(workspace, project, sheet) do
    ~p"/workspaces/#{workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}"
  end

  defp get_avatar_url(%{avatar_asset: %{url: url}}) when is_binary(url), do: url
  defp get_avatar_url(_sheet), do: nil
end

defmodule StoryarnWeb.SheetLive.Components.HistoryTab do
  @moduledoc """
  LiveComponent for the History tab in the sheet editor.
  Contains VersionsSection (and future Activity/Comments sections).
  """

  use StoryarnWeb, :live_component

  alias StoryarnWeb.Components.VersionsSection

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-8">
      <%!-- Version History Section --%>
      <.live_component
        module={VersionsSection}
        id="versions-section"
        entity={@sheet}
        entity_type="sheet"
        project_id={@project.id}
        current_user_id={@current_user_id}
        can_edit={@can_edit}
        current_version_id={@sheet.current_version_id}
        workspace_id={@workspace_id}
      />
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end
end

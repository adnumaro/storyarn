defmodule StoryarnWeb.SheetLive.Components.HistoryTab do
  @moduledoc """
  LiveComponent for the History tab in the sheet editor.
  Contains VersionsSection (and future Activity/Comments sections).
  """

  use StoryarnWeb, :live_component

  alias StoryarnWeb.SheetLive.Components.VersionsSection

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-8">
      <%!-- Version History Section --%>
      <.live_component
        module={VersionsSection}
        id="versions-section"
        sheet={@sheet}
        project={@project}
        current_user_id={@current_user_id}
        can_edit={@can_edit}
      />
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end
end

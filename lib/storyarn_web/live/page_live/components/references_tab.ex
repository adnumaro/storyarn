defmodule StoryarnWeb.PageLive.Components.ReferencesTab do
  @moduledoc """
  LiveComponent for the References tab in the page editor.
  Contains BacklinksSection and VersionsSection sub-components.
  """

  use StoryarnWeb, :live_component

  alias StoryarnWeb.PageLive.Components.BacklinksSection
  alias StoryarnWeb.PageLive.Components.VersionsSection

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-8">
      <%!-- Backlinks Section --%>
      <.live_component
        module={BacklinksSection}
        id="backlinks-section"
        page={@page}
        project={@project}
      />

      <%!-- Version History Section --%>
      <.live_component
        module={VersionsSection}
        id="versions-section"
        page={@page}
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

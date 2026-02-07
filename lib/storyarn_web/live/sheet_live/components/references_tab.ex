defmodule StoryarnWeb.SheetLive.Components.ReferencesTab do
  @moduledoc """
  LiveComponent for the References tab in the sheet editor.
  Contains BacklinksSection and VersionsSection sub-components.
  """

  use StoryarnWeb, :live_component

  alias StoryarnWeb.SheetLive.Components.BacklinksSection
  alias StoryarnWeb.SheetLive.Components.VariableUsageSection
  alias StoryarnWeb.SheetLive.Components.VersionsSection

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-8">
      <%!-- Variable Usage Section --%>
      <.live_component
        module={VariableUsageSection}
        id="variable-usage-section"
        sheet={@sheet}
        project={@project}
        blocks={@blocks}
      />

      <%!-- Backlinks Section --%>
      <.live_component
        module={BacklinksSection}
        id="backlinks-section"
        sheet={@sheet}
        project={@project}
      />

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

defmodule StoryarnWeb.SheetLive.V1.Components.ReferencesTab do
  @moduledoc """
  LiveComponent for the References tab in the sheet editor.
  Contains VariableUsageSection and BacklinksSection sub-components.
  """

  use StoryarnWeb, :live_component

  alias StoryarnWeb.SheetLive.V1.Components.BacklinksSection
  alias StoryarnWeb.SheetLive.V1.Components.SceneAppearancesSection
  alias StoryarnWeb.SheetLive.V1.Components.VariableUsageSection

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
        workspace={@workspace}
      />

      <%!-- Map Appearances Section --%>
      <.live_component
        module={SceneAppearancesSection}
        id="map-appearances-section"
        sheet={@sheet}
        project={@project}
        workspace={@workspace}
      />
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end
end

defmodule StoryarnWeb.SheetLive.Components.ReferencesTab do
  @moduledoc """
  LiveComponent for the References tab in the sheet editor.
  Contains VariableUsageSection and BacklinksSection sub-components.
  """

  use StoryarnWeb, :live_component

  alias StoryarnWeb.SheetLive.Components.BacklinksSection
  alias StoryarnWeb.SheetLive.Components.VariableUsageSection

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
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end
end

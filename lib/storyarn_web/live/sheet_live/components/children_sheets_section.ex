defmodule StoryarnWeb.SheetLive.Components.ChildrenSheetsSection do
  @moduledoc """
  Sub-component for rendering the "Subsheets" section at the bottom of the sheet content tab.

  Shows all direct child sheets of the current sheet as navigable links.
  """

  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext
  use StoryarnWeb, :verified_routes

  import StoryarnWeb.Components.SheetComponents, only: [sheet_avatar: 1]

  # ---------------------------------------------------------------------------
  # children_sheets_section/1
  # ---------------------------------------------------------------------------

  attr :children, :list, required: true
  attr :workspace, :map, required: true
  attr :project, :map, required: true

  def children_sheets_section(assigns) do
    ~H"""
    <div class="mt-12 pt-8 border-t border-base-300">
      <h2 class="text-lg font-semibold mb-4">{dgettext("sheets", "Subsheets")}</h2>
      <div class="space-y-2">
        <.link
          :for={child <- @children}
          navigate={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/sheets/#{child.id}"}
          class="flex items-center gap-2 p-2 rounded hover:bg-base-200"
        >
          <.sheet_avatar avatar_asset={child.avatar_asset} name={child.name} size="md" />
          <span>{child.name}</span>
        </.link>
      </div>
    </div>
    """
  end
end

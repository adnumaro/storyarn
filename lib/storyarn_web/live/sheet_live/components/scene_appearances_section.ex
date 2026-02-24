defmodule StoryarnWeb.SheetLive.Components.SceneAppearancesSection do
  @moduledoc """
  LiveComponent for displaying map appearances of a sheet.
  Shows maps where the current sheet is referenced via pins or zones.
  """

  use StoryarnWeb, :live_component

  alias Storyarn.Scenes

  @impl true
  def render(assigns) do
    ~H"""
    <section>
      <h2 class="text-lg font-semibold mb-4 flex items-center gap-2">
        <.icon name="map" class="size-5" />
        {dgettext("sheets", "Appears on Scenes")}
        <%= if @appearances && length(@appearances) > 0 do %>
          <span class="badge badge-sm">{length(@appearances)}</span>
        <% end %>
      </h2>

      <%= if is_nil(@appearances) do %>
        <.loading_placeholder />
      <% else %>
        <%= if @appearances == [] do %>
          <.empty_appearances_state />
        <% else %>
          <div class="space-y-2">
            <.appearance_row
              :for={appearance <- @appearances}
              appearance={appearance}
              workspace={@workspace}
              project={@project}
            />
          </div>
        <% end %>
      <% end %>
    </section>
    """
  end

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:appearances, fn -> nil end)

    socket =
      if is_nil(socket.assigns.appearances) do
        load_appearances(socket)
      else
        socket
      end

    {:ok, socket}
  end

  # ===========================================================================
  # Private: Data Loading
  # ===========================================================================

  defp load_appearances(socket) do
    %{zones: zones, pins: pins} =
      Scenes.get_elements_for_target("sheet", socket.assigns.sheet.id)

    appearances =
      Enum.map(zones, fn zone ->
        %{
          element_type: "zone",
          element_name: zone.name,
          scene_id: zone.scene.id,
          scene_name: zone.scene.name
        }
      end) ++
        Enum.map(pins, fn pin ->
          %{
            element_type: "pin",
            element_name: pin.label,
            scene_id: pin.scene.id,
            scene_name: pin.scene.name
          }
        end)

    assign(socket, :appearances, appearances)
  end

  # ===========================================================================
  # Function Components
  # ===========================================================================

  defp loading_placeholder(assigns) do
    ~H"""
    <div class="flex items-center justify-center p-8">
      <span class="loading loading-spinner loading-md"></span>
    </div>
    """
  end

  defp empty_appearances_state(assigns) do
    ~H"""
    <div class="bg-base-200/50 rounded-lg p-8 text-center">
      <.icon name="map" class="size-12 mx-auto text-base-content/30 mb-4" />
      <p class="text-base-content/70 mb-2">
        {dgettext("sheets", "This sheet doesn't appear on any maps yet.")}
      </p>
      <p class="text-sm text-base-content/50">
        {dgettext("sheets", "Create a pin or zone referencing this sheet to see it here.")}
      </p>
    </div>
    """
  end

  attr :appearance, :map, required: true
  attr :workspace, :map, required: true
  attr :project, :map, required: true

  defp appearance_row(assigns) do
    ~H"""
    <.link
      navigate={
        ~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/scenes/#{@appearance.scene_id}"
      }
      class="flex items-center gap-3 p-3 rounded-lg hover:bg-base-200/50 group cursor-pointer"
    >
      <div class="flex-shrink-0 size-8 rounded flex items-center justify-center bg-info/20 text-info">
        <.icon name="map" class="size-4" />
      </div>

      <div class="flex-1 min-w-0">
        <div class="flex items-center gap-2">
          <span class="font-medium truncate">{@appearance.scene_name}</span>
        </div>
        <div class="text-sm text-base-content/60">
          <span class="badge badge-xs badge-ghost mr-1">{@appearance.element_type}</span>
          <span :if={@appearance.element_name}>{@appearance.element_name}</span>
        </div>
      </div>

      <.icon
        name="arrow-up-right"
        class="size-4 text-base-content/30 group-hover:text-base-content/60"
      />
    </.link>
    """
  end
end

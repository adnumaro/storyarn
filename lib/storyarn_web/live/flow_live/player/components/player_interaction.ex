defmodule StoryarnWeb.FlowLive.Player.Components.PlayerInteraction do
  @moduledoc """
  Renders the interaction slide in the Story Player.

  Passes map background, zone data, and display variable values to the
  `InteractionPlayer` JS hook, which handles zone rendering and click events.
  """

  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext

  attr :slide, :map, required: true

  @doc "Renders the map-based interaction container with zone overlays."
  def player_interaction(assigns) do
    display_variables =
      assigns.slide.zones
      |> Enum.filter(fn zone ->
        zone.action_type == "display" and
          is_binary((zone.action_data || %{})["variable_ref"])
      end)
      |> Map.new(fn zone ->
        ref = zone.action_data["variable_ref"]
        {ref, zone[:display_value]}
      end)

    assigns = Phoenix.Component.assign(assigns, :display_variables, display_variables)

    ~H"""
    <div
      id={"interaction-player-#{@slide.node_id}"}
      phx-hook="InteractionPlayer"
      data-background-url={@slide.background_url}
      data-map-width={@slide.map_width}
      data-map-height={@slide.map_height}
      data-zones={Jason.encode!(@slide.zones)}
      data-variables={Jason.encode!(@display_variables)}
      class="interaction-player-container"
    >
      <p :if={is_nil(@slide.background_url)} class="text-base-content/40 text-center py-8">
        {dgettext("flows", "No map background configured.")}
      </p>
    </div>
    """
  end
end

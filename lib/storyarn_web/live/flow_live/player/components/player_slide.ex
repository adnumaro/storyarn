defmodule StoryarnWeb.FlowLive.Player.Components.PlayerSlide do
  @moduledoc false

  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext

  import StoryarnWeb.FlowLive.Player.Components.PlayerInteraction

  attr :slide, :map, required: true

  def player_slide(%{slide: %{type: :dialogue}} = assigns) do
    ~H"""
    <div class="player-slide player-slide-dialogue">
      <div class="player-speaker">
        <div
          class="player-speaker-avatar"
          style={if @slide.speaker_color, do: "background-color: #{@slide.speaker_color}"}
        >
          {@slide.speaker_initials}
        </div>
        <div :if={@slide.speaker_name} class="player-speaker-name">
          {@slide.speaker_name}
        </div>
      </div>
      <div class="player-text">
        {Phoenix.HTML.raw(@slide.text)}
      </div>
      <div :if={@slide.stage_directions != ""} class="player-stage-directions">
        {@slide.stage_directions}
      </div>
    </div>
    """
  end

  def player_slide(%{slide: %{type: :scene}} = assigns) do
    ~H"""
    <div class="player-slide player-slide-scene">
      <div class="player-scene-slug">
        {@slide.setting}. {@slide.location_name}
        <span :if={@slide.sub_location != ""}>{" — #{@slide.sub_location}"}</span>
        <span :if={@slide.time_of_day != ""}>{" — #{String.upcase(@slide.time_of_day)}"}</span>
      </div>
      <div :if={@slide.description != ""} class="player-scene-description">
        {Phoenix.HTML.raw(@slide.description)}
      </div>
    </div>
    """
  end

  def player_slide(%{slide: %{type: :interaction}} = assigns) do
    ~H"""
    <div class="player-slide player-slide-interaction">
      <.player_interaction slide={@slide} />
    </div>
    """
  end

  def player_slide(%{slide: %{type: :empty}} = assigns) do
    ~H"""
    <div class="player-slide player-slide-empty">
      <p class="text-base-content/40">{dgettext("flows", "No content to display.")}</p>
    </div>
    """
  end

  def player_slide(assigns) do
    ~H"""
    <div class="player-slide"></div>
    """
  end
end

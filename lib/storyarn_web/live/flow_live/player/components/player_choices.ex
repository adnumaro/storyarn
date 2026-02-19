defmodule StoryarnWeb.FlowLive.Player.Components.PlayerChoices do
  @moduledoc false

  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext

  import StoryarnWeb.Components.CoreComponents, only: [icon: 1]

  attr :responses, :list, required: true
  attr :player_mode, :atom, required: true

  def player_choices(assigns) do
    visible =
      if assigns.player_mode == :player do
        Enum.filter(assigns.responses, & &1.valid)
      else
        assigns.responses
      end

    assigns = Phoenix.Component.assign(assigns, :visible_responses, visible)

    ~H"""
    <div :if={@visible_responses != []} class="player-choices">
      <button
        :for={resp <- @visible_responses}
        type="button"
        class={[
          "player-response",
          !resp.valid && "player-response-invalid"
        ]}
        phx-click="choose_response"
        phx-value-id={resp.id}
        disabled={!resp.valid && @player_mode == :analysis}
      >
        <span class="player-response-number">{resp.number}</span>
        <span class="player-response-text">{resp.text}</span>
        <span :if={resp.has_condition && @player_mode == :analysis} class="player-response-badge">
          <.icon name="shield-question" class="size-3" />
        </span>
      </button>
    </div>
    """
  end
end

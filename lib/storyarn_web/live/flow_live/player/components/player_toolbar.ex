defmodule StoryarnWeb.FlowLive.Player.Components.PlayerToolbar do
  @moduledoc false

  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext
  use StoryarnWeb, :verified_routes

  import StoryarnWeb.Components.CoreComponents, only: [icon: 1]

  attr :can_go_back, :boolean, required: true
  attr :show_continue, :boolean, required: true
  attr :player_mode, :atom, required: true
  attr :is_finished, :boolean, required: true
  attr :workspace, :map, required: true
  attr :project, :map, required: true
  attr :flow, :map, required: true

  def player_toolbar(assigns) do
    ~H"""
    <div class="player-toolbar">
      <div class="player-toolbar-left">
        <button
          type="button"
          class="player-toolbar-btn"
          phx-click="go_back"
          disabled={!@can_go_back}
          title={dgettext("flows", "Back (←)")}
        >
          <.icon name="arrow-left" class="size-4" />
        </button>
        <button
          :if={@show_continue && !@is_finished}
          type="button"
          class="player-toolbar-btn player-toolbar-btn-primary"
          phx-click="continue"
          title={dgettext("flows", "Continue (Space)")}
        >
          {dgettext("flows", "Continue")}
          <.icon name="arrow-right" class="size-4" />
        </button>
      </div>

      <div class="player-toolbar-center">
        <button
          type="button"
          class={[
            "player-toolbar-btn player-toolbar-btn-mode",
            @player_mode == :analysis && "player-toolbar-btn-active"
          ]}
          phx-click="toggle_mode"
          title={dgettext("flows", "Toggle mode (P)")}
        >
          <.icon name={if @player_mode == :player, do: "eye", else: "scan-eye"} class="size-4" />
          <span class="hidden sm:inline">
            {if @player_mode == :player,
              do: dgettext("flows", "Player"),
              else: dgettext("flows", "Analysis")}
          </span>
        </button>
      </div>

      <div class="player-toolbar-right">
        <button
          type="button"
          class="player-toolbar-btn"
          phx-click="restart"
          title={dgettext("flows", "Restart")}
        >
          <.icon name="rotate-ccw" class="size-4" />
        </button>
        <.link
          navigate={
            ~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/flows/#{@flow.id}"
          }
          class="player-toolbar-btn"
          title={dgettext("flows", "Back to editor (Esc)")}
        >
          <.icon name="x" class="size-4" />
        </.link>
      </div>
    </div>
    """
  end
end

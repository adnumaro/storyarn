defmodule StoryarnWeb.FlowLive.Player.Components.PlayerOutcome do
  @moduledoc false

  use Phoenix.Component
  use Gettext, backend: Storyarn.Gettext
  use StoryarnWeb, :verified_routes

  import StoryarnWeb.Components.CoreComponents, only: [icon: 1]

  attr :slide, :map, required: true
  attr :workspace, :map, required: true
  attr :project, :map, required: true
  attr :flow, :map, required: true

  def player_outcome(assigns) do
    ~H"""
    <div class="player-slide player-slide-outcome">
      <div
        class="player-outcome-accent"
        style={if @slide.outcome_color, do: "background-color: #{@slide.outcome_color}"}
      >
      </div>

      <h2 class="player-outcome-title">
        {@slide.label}
      </h2>

      <div :if={@slide.outcome_tags != []} class="player-outcome-tags">
        <span
          :for={tag <- @slide.outcome_tags}
          class="text-xs px-1.5 py-0.5 rounded border border-border text-muted-foreground badge-sm"
        >
          {tag}
        </span>
      </div>

      <div class="player-outcome-stats">
        <div class="player-outcome-stat">
          <.icon name="footprints" class="size-4" />
          <span>{dgettext("flows", "Steps: %{count}", count: @slide.step_count)}</span>
        </div>
        <div class="player-outcome-stat">
          <.icon name="mouse-pointer-click" class="size-4" />
          <span>{dgettext("flows", "Choices: %{count}", count: @slide.choices_made)}</span>
        </div>
        <div class="player-outcome-stat">
          <.icon name="variable" class="size-4" />
          <span>
            {dgettext("flows", "Variables changed: %{count}", count: @slide.variables_changed)}
          </span>
        </div>
      </div>

      <div class="player-outcome-actions">
        <button
          type="button"
          class="inline-flex items-center justify-center h-8 px-3 text-sm font-medium rounded-md bg-primary text-primary-foreground hover:bg-primary/90 transition-colors gap-2"
          phx-click="restart"
        >
          <.icon name="rotate-ccw" class="size-4" />
          {dgettext("flows", "Play again")}
        </button>
        <.link
          navigate={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/flows/#{@flow.id}"}
          class="inline-flex items-center justify-center h-8 px-3 text-sm rounded-md hover:bg-accent transition-colors gap-2"
        >
          <.icon name="arrow-left" class="size-4" />
          {dgettext("flows", "Back to editor")}
        </.link>
      </div>
    </div>
    """
  end
end

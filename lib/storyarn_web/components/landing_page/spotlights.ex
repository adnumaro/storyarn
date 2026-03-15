defmodule StoryarnWeb.Components.LandingPage.Spotlights do
  @moduledoc """
  Exploration mode and version history spotlight sections for the landing page.
  """
  use StoryarnWeb, :html

  import StoryarnWeb.Components.TextComponents, only: [widont: 1]

  def exploration_spotlight(assigns) do
    ~H"""
    <section class="py-16 lg:py-20 scroll-mt-32" id="exploration-mode">
      <div class="mx-auto w-[min(calc(100%-48px),1280px)]">
        <div class="p-8 rounded-[2rem] border border-base-content/8 bg-base-200/60" data-reveal>
          <div class="grid grid-cols-1 lg:grid-cols-[1.1fr_minmax(320px,0.72fr)] gap-6 items-start">
            <div class="grid gap-4">
              <span class="text-base-content/70 text-xs font-bold tracking-widest uppercase">
                {gettext("Exploration Mode")}
              </span>
              <h3 class="text-[clamp(2rem,4vw,3.6rem)] leading-[0.94] tracking-[-0.05em] font-bold text-base-content">
                {widont(gettext("Turn scene design into a playable prototype."))}
              </h3>
              <p class="text-base-content/60 leading-relaxed">
                {widont(
                  gettext(
                    "Zones, pins, camera behavior, state, and flow triggers come together in one surface — explore it, test it, and show it to the team."
                  )
                )}
              </p>
              <ul class="grid gap-3 list-none p-0">
                <li class="p-3.5 rounded-2xl border border-base-content/8 bg-base-content/3 text-base-content/70 leading-relaxed">
                  {gettext(
                    "Replace static documents and slide decks with something the team can actually walk through."
                  )}
                </li>
                <li class="p-3.5 rounded-2xl border border-base-content/8 bg-base-content/3 text-base-content/70 leading-relaxed">
                  {gettext(
                    "A natural fit for any genre that relies on spatial narrative and world exploration."
                  )}
                </li>
                <li class="p-3.5 rounded-2xl border border-base-content/8 bg-base-content/3 text-base-content/70 leading-relaxed">
                  {gettext("Useful for internal demos, publisher pitches, and early playtest loops.")}
                </li>
              </ul>
            </div>
            <div class="flex justify-end items-start">
              <span class="badge badge-ghost badge-sm">
                {gettext("Playable prototyping")}
              </span>
            </div>
          </div>

          <div class="lp-exploration-shell mt-6">
            <div class="lp-screenshot-placeholder">
              <.icon name="image" class="size-8 opacity-40" />
              <strong>{gettext("Scene exploration mode")}</strong>
              <span>
                {gettext(
                  "Screenshot: Scene canvas with background image, drawn zones, interactive pins, and open side panel. Dark mode, ~1280×436px."
                )}
              </span>
            </div>
          </div>
        </div>
      </div>
    </section>
    """
  end

  def version_spotlight(assigns) do
    ~H"""
    <section class="py-16 lg:py-20 scroll-mt-32" id="version-history">
      <div class="mx-auto w-[min(calc(100%-48px),1280px)]">
        <div class="p-8 rounded-[2rem] border border-base-content/8 bg-base-200/60" data-reveal>
          <div class="grid grid-cols-1 lg:grid-cols-[minmax(320px,0.72fr)_1.1fr] gap-6 items-start">
            <.version_visual />
            <.version_copy />
          </div>
        </div>
      </div>
    </section>
    """
  end

  defp version_visual(assigns) do
    ~H"""
    <div class="lp-screenshot-placeholder" style="min-height: 360px;">
      <.icon name="image" class="size-8 opacity-40" />
      <strong>{gettext("Version history panel")}</strong>
      <span>
        {gettext(
          "Screenshot: Version history panel open over a flow or scene editor, showing named versions (v11, v10, Draft), restore actions, and timestamps. Dark mode, ~480×360px."
        )}
      </span>
    </div>
    """
  end

  defp version_copy(assigns) do
    ~H"""
    <div class="grid gap-4">
      <span class="text-base-content/70 text-xs font-bold tracking-widest uppercase">
        {gettext("Version History")}
      </span>
      <h3 class="text-[clamp(2rem,4vw,3.6rem)] leading-[0.94] tracking-[-0.05em] font-bold text-base-content">
        {widont(gettext("Versioning that feels safe, not technical."))}
      </h3>
      <p class="text-base-content/60 leading-relaxed">
        {widont(
          gettext(
            "Version history for sheets, flows, and scenes — designed for narrative teams, not engineers. The goal is simple: experiment without fear."
          )
        )}
      </p>
      <ul class="grid gap-3 list-none p-0">
        <li class="p-3.5 rounded-2xl border border-base-content/8 bg-base-content/3 text-base-content/70 leading-relaxed">
          {gettext("Named versions, safe restore, and private drafts for experimentation.")}
        </li>
        <li class="p-3.5 rounded-2xl border border-base-content/8 bg-base-content/3 text-base-content/70 leading-relaxed">
          {gettext("Built around one feeling: \"I can always go back.\"")}
        </li>
        <li class="p-3.5 rounded-2xl border border-base-content/8 bg-base-content/3 text-base-content/70 leading-relaxed">
          {gettext("A capability almost no other narrative tool offers.")}
        </li>
      </ul>
    </div>
    """
  end
end

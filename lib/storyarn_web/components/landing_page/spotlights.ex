defmodule StoryarnWeb.Components.LandingPage.Spotlights do
  @moduledoc """
  Exploration mode and version history spotlight sections for the landing page.
  """
  use StoryarnWeb, :html

  def exploration_spotlight(assigns) do
    ~H"""
    <section class="py-16 lg:py-20 scroll-mt-32" id="exploration-mode">
      <div class="mx-auto w-[min(calc(100%-48px),1280px)]">
        <div class="p-8 rounded-[2rem] border border-base-content/8 bg-base-200/60">
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
                    "This is where Storyarn stops feeling like documentation and starts feeling like a game. Zones, pins, camera behavior, state and flow triggers come together in a surface that teams can explore, test and show."
                  )
                )}
              </p>
              <ul class="grid gap-3 list-none p-0">
                <li class="p-3.5 rounded-2xl border border-base-content/8 bg-base-content/3 text-base-content/70 leading-relaxed">
                  {gettext("Built to compete with dead documents, slide decks and unread GDDs.")}
                </li>
                <li class="p-3.5 rounded-2xl border border-base-content/8 bg-base-content/3 text-base-content/70 leading-relaxed">
                  {gettext(
                    "Strong fit for CRPG, point-and-click and narrative exploration workflows."
                  )}
                </li>
                <li class="p-3.5 rounded-2xl border border-base-content/8 bg-base-content/3 text-base-content/70 leading-relaxed">
                  {gettext("Useful for internal demos, publisher pitches and early playtest loops.")}
                </li>
              </ul>
            </div>
            <div class="flex justify-end items-start">
              <span class="badge badge-ghost badge-sm">
                {gettext("Playable prototype engine")}
              </span>
            </div>
          </div>

          <div class="lp-exploration-shell mt-6">
            <div class="lp-exploration-map">
              <div class="lp-exploration-zone"></div>
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
        <div class="p-8 rounded-[2rem] border border-base-content/8 bg-base-200/60">
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
    <div class="lp-version-shot">
      <div class="lp-version-overlay">
        <div class="w-full max-w-[360px] p-4 rounded-2xl border border-base-content/8 bg-base-300/90 backdrop-blur">
          <div class="flex items-center justify-between gap-3 mb-3.5">
            <strong class="text-base text-base-content">{gettext("Version History")}</strong>
          </div>
          <div class="grid gap-3">
            <.version_entry
              title={gettext("Restored from v8")}
              tag="v11"
              line1={gettext("Mar 12, 2026 at 15:59")}
            />
            <.version_entry
              title={gettext("Before restore to v8")}
              tag="v10"
              line1={gettext("Auto snapshot before destructive restore")}
              line2={gettext("Safe rollback path preserved")}
            />
            <.version_entry
              title={gettext("Draft checkpoint")}
              tag={gettext("Draft")}
              line1={gettext("Private branch for scene edits and experimentation")}
              line2={gettext("Ready to compare, keep or discard")}
            />
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :tag, :string, required: true
  attr :line1, :string, required: true
  attr :line2, :string, default: nil

  defp version_entry(assigns) do
    ~H"""
    <div class="grid gap-2 p-3.5 rounded-2xl border border-base-content/6 bg-base-content/3">
      <div class="flex items-center gap-2.5">
        <span class="w-3.5 h-3.5 rounded-full bg-accent/20 shadow-[0_0_0_1px_var(--color-accent)/22]">
        </span>
        <strong class="text-sm text-base-content">{@title}</strong>
        <span class="badge badge-xs badge-outline border-accent/30 text-accent">{@tag}</span>
      </div>
      <span class="text-base-content/50 text-xs">{@line1}</span>
      <small :if={@line2} class="text-base-content/40 text-xs">{@line2}</small>
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
        {widont(gettext("Versioning that feels safe without feeling technical."))}
      </h3>
      <p class="text-base-content/60 leading-relaxed">
        {widont(
          gettext(
            "Storyarn brings version history to sheets, flows and scenes in a way that feels native to narrative teams. The goal is not to teach Git. The goal is to let people experiment without fear."
          )
        )}
      </p>
      <ul class="grid gap-3 list-none p-0">
        <li class="p-3.5 rounded-2xl border border-base-content/8 bg-base-content/3 text-base-content/70 leading-relaxed">
          {gettext("Named versions, safe restore and private drafts for exploration.")}
        </li>
        <li class="p-3.5 rounded-2xl border border-base-content/8 bg-base-content/3 text-base-content/70 leading-relaxed">
          {gettext("Designed around the feeling of \"I can always go back.\"")}
        </li>
        <li class="p-3.5 rounded-2xl border border-base-content/8 bg-base-content/3 text-base-content/70 leading-relaxed">
          {gettext("A rare capability in narrative tooling and a strong differentiator.")}
        </li>
      </ul>
    </div>
    """
  end
end

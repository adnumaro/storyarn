defmodule StoryarnWeb.Components.LandingPage.Hero do
  @moduledoc """
  Hero section for the landing page.
  """
  use StoryarnWeb, :html

  def hero(assigns) do
    ~H"""
    <section id="hero-section" class="relative isolate min-h-[100svh] overflow-hidden">
      <%!-- Full-bleed portal stage --%>
      <div id="portal-wrap" class="lp-portal-wrap">
        <div class="lp-portal-backdrop" aria-hidden="true"></div>
        <canvas id="portal-canvas" aria-hidden="true"></canvas>

        <button
          id="portal-trigger"
          class="lp-portal-trigger"
          type="button"
          aria-label={gettext("Watch demo video")}
        >
          <span class="lp-portal-trigger-badge">
            <.icon name="play" class="size-4" />
            <span>{gettext("Watch demo")}</span>
          </span>

          <div id="portal-video-frame" class="lp-portal-video-frame">
            <video
              id="portal-video"
              class="lp-portal-video"
              autoplay
              muted
              loop
              playsinline
              src={~p"/videos/demo.mp4"}
            >
            </video>
          </div>
        </button>
      </div>

      <%!-- Hero content --%>
      <div
        id="hero-content"
        class="pointer-events-none relative z-10 mx-auto flex min-h-[100svh] w-full max-w-[1180px] flex-col items-center place-content-center px-6 pb-20 pt-28 text-center sm:px-8 sm:pb-24 sm:pt-32 lg:pt-40"
        style="transform: translateY(-10%);"
      >
        <div class="pointer-events-auto">
          <%!-- Eyebrow badge --%>
          <div class="inline-flex items-center gap-1.5 sm:gap-2.5 px-3 sm:px-4 py-1.5 sm:py-2.5 rounded-full border border-primary/20 bg-primary/10 text-primary text-[0.65rem] sm:text-xs tracking-widest uppercase">
            <span class="lp-badge-dot w-2 sm:w-2.5 h-2 sm:h-2.5 rounded-full bg-primary"></span>
            {gettext("Private beta")}
          </div>

          <div class="mt-5 sm:mt-7">
            <h1 class="text-[clamp(2.6rem,7.2vw,5.8rem)] leading-[0.88] tracking-[-0.07em] font-bold text-base-content">
              {gettext("Craft worlds.")}
              <span class="block mt-1.5 brand-logotype text-[1em]">
                {gettext("Weave stories.")}
              </span>
            </h1>
          </div>

          <p class="mx-auto mt-6 max-w-[46rem] text-base-content/60 text-sm sm:text-lg leading-relaxed">
            {gettext(
              "The narrative design platform where characters, dialogue, worlds, and localization live in one connected project — from first draft to engine-ready export."
            )}
          </p>

          <div class="mt-8 flex flex-wrap justify-center gap-3.5">
            <a href="#discover" class="btn btn-primary btn-lg">
              {gettext("Explore Storyarn")}
            </a>
            <a
              href="#workflow"
              class="btn btn-ghost btn-lg border border-base-content/10"
            >
              {gettext("See workflow")}
            </a>
          </div>
        </div>
      </div>
    </section>

    <%!-- Fullscreen video overlay (below topbar z-index: 120) --%>
    <div id="portal-fullscreen" class="lp-portal-fullscreen" aria-hidden="true">
      <button
        id="portal-fullscreen-close"
        class="lp-portal-fullscreen-close"
        aria-label={gettext("Close video")}
      >
        <.icon name="x" class="size-5" />
      </button>
    </div>
    """
  end
end

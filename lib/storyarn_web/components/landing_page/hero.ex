defmodule StoryarnWeb.Components.LandingPage.Hero do
  @moduledoc """
  Hero section for the landing page.
  """
  use StoryarnWeb, :html

  def hero(assigns) do
    ~H"""
    <section class="relative min-w-screen overflow-hidden pb-20 lg:pb-28">
      <div class="relative">
        <div class="relative mx-auto mt-[80px] w-[min(calc(100%-48px),1280px)] lg:mt-[150px]">
          <div class="relative z-3 w-full max-w-[1100px] mx-auto pt-12 lg:pt-20 text-center">
            <%!-- Eyebrow badge --%>
            <div class="inline-flex items-center gap-2.5 px-4 py-2.5 rounded-full border border-primary/20 bg-primary/10 text-primary text-xs tracking-widest uppercase">
              <span class="lp-badge-dot w-2.5 h-2.5 rounded-full bg-primary"></span>
              {gettext("Private beta")}
            </div>

            <div class="mt-7">
              <h1 class="text-[clamp(4rem,7.2vw,5.8rem)] leading-[0.88] tracking-[-0.07em] font-bold text-base-content">
                {gettext("Craft worlds.")}
                <span class="block mt-1.5 brand-logotype text-[1em]">
                  {gettext("Weave stories.")}
                </span>
              </h1>
            </div>

            <p class="mx-auto mt-6 max-w-[46rem] text-base-content/60 text-lg leading-relaxed">
              {gettext(
                "The narrative design platform where characters, dialogue, worlds, and localization live in one connected project — from first draft to engine-ready export."
              )}
            </p>

            <div class="flex flex-wrap justify-center gap-3.5 mt-8">
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
      </div>
    </section>
    """
  end
end

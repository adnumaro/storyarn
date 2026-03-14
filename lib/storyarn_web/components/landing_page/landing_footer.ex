defmodule StoryarnWeb.Components.LandingPage.LandingFooter do
  @moduledoc """
  Footer for the landing page.
  """
  use StoryarnWeb, :html

  attr :current_scope, :map, default: nil

  def landing_footer(assigns) do
    assigns = assign(assigns, :year, Date.utc_today().year)

    ~H"""
    <footer class="pb-10 pt-6">
      <div class="mx-auto w-[min(calc(100%-48px),1280px)]">
        <div class="rounded-[2rem] border border-base-content/8 bg-base-200/60 px-6 py-8 shadow-[0_24px_80px_rgba(0,0,0,0.16)] sm:px-8 lg:px-10">
          <div class="grid gap-8 lg:grid-cols-[1.35fr_0.95fr_0.85fr] lg:items-start">
            <div class="grid gap-4 max-w-[30rem]">
              <.link navigate="/" class="flex items-center gap-3 text-base-content">
                <img
                  src={~p"/images/logo-light-64.png"}
                  alt="Storyarn"
                  class="h-10 w-10 dark:hidden"
                />
                <img
                  src={~p"/images/logo-dark-64.png"}
                  alt="Storyarn"
                  class="hidden h-10 w-10 dark:block"
                />
                <div>
                  <strong class="block text-2xl brand-logotype leading-none">Storyarn</strong>
                  <span class="mt-1 block text-sm text-base-content/55">
                    {gettext("Open narrative design tool")}
                  </span>
                </div>
              </.link>

              <p class="max-w-[28rem] text-sm leading-relaxed text-base-content/58">
                {gettext(
                  "Storyarn brings sheets, flows, scenes, screenplays, and localization into a single platform for interactive narrative. Everything connected: characters, variables, branches, maps, and export for your engine."
                )}
              </p>

              <div class="flex flex-wrap items-center gap-3 text-sm text-base-content/55">
                <span class="badge badge-ghost badge-sm">{gettext("Private beta")}</span>
                <span>{gettext("Realtime collaboration")}</span>
                <span>{gettext("Version snapshots")}</span>
              </div>
            </div>

            <nav class="grid gap-3 text-sm text-base-content/62">
              <a href="#features" class="transition-colors hover:text-base-content">
                {gettext("Features")}
              </a>
              <a href="#discover" class="transition-colors hover:text-base-content">
                {gettext("Discover")}
              </a>
              <a href="#workflow" class="transition-colors hover:text-base-content">
                {gettext("Workflow")}
              </a>
              <.link navigate={~p"/docs"} class="transition-colors hover:text-base-content">
                {gettext("Docs")}
              </.link>
              <.link navigate={~p"/contact"} class="transition-colors hover:text-base-content">
                {gettext("Contact")}
              </.link>
            </nav>

          </div>

          <div class="mt-8 flex flex-col gap-3 border-t border-base-content/8 pt-4 text-sm text-base-content/42 sm:flex-row sm:items-center sm:justify-between">
            <span>Storyarn · {@year}</span>
            <span>{gettext("Private beta")}</span>
          </div>
        </div>
      </div>
    </footer>
    """
  end
end

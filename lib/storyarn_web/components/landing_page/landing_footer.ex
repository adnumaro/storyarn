defmodule StoryarnWeb.Components.LandingPage.LandingFooter do
  @moduledoc """
  Footer for the landing page.
  """
  use StoryarnWeb, :html

  attr :current_scope, :map, default: nil

  def landing_footer(assigns) do
    assigns = assign(assigns, :year, Date.utc_today().year)

    ~H"""
    <footer>
      <div class="border-t border-base-content/8 bg-base-200/60 px-6 py-8 shadow-[0_24px_80px_rgba(0,0,0,0.16)] sm:px-8 lg:px-10">
        <div class="grid gap-8 lg:grid-cols-[1.35fr_0.95fr_0.85fr] lg:items-start">
          <div class="grid gap-4 max-w-[30rem]">
            <.link navigate="/" class="flex items-center text-base-content">
              <img
                src={~p"/images/logos/logo-name-white.png"}
                alt="Storyarn"
                class="h-[42px] w-auto"
              />
            </.link>

            <p class="max-w-[28rem] text-sm leading-relaxed text-base-content/58">
              {gettext(
                "Design characters, dialogue, worlds, and localization in one connected project. Built for narrative teams shipping interactive stories."
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
    </footer>
    """
  end
end

defmodule StoryarnWeb.Components.PublicFooter do
  @moduledoc false

  use StoryarnWeb, :html

  alias Phoenix.LiveView.JS
  alias StoryarnWeb.Components.PublicNavigation

  attr :landing, :boolean, required: true
  attr :urls, :map, required: true

  def footer(assigns) do
    assigns = assign(assigns, :year, Date.utc_today().year)

    ~H"""
    <footer
      id="public-footer"
      class="dark landing-footer w-full border-t border-border/10 bg-[#111318] pb-8 pt-16 text-foreground"
    >
      <div class="mx-auto w-[min(calc(100%-48px),1280px)]">
        <div class="mb-16 flex flex-col gap-12 sm:flex-row sm:justify-between">
          <div class="flex max-w-104 flex-col items-start gap-5">
            <div class="flex items-center gap-3">
              <img
                src={~p"/images/logos/logo-name-white.png"}
                alt="Storyarn"
                class="h-7 w-auto mix-blend-screen opacity-90"
              />
              <span class="rounded-full border border-border/20 bg-muted/30 px-3 py-1 text-[11px] font-semibold uppercase tracking-wide text-foreground/70">
                {dgettext("public", "Open beta")}
              </span>
            </div>
            <p class="text-sm leading-relaxed text-muted-foreground/80">
              {dgettext(
                "public",
                "Design characters, dialogues, worlds, and localization in a single connected project. Built for narrative teams shipping interactive stories."
              )}
            </p>
          </div>

          <nav
            class="flex flex-col gap-3 pt-2 text-sm font-medium text-muted-foreground/80 lg:mr-24"
            aria-label={dgettext("public", "Footer navigation")}
          >
            <PublicNavigation.section_link
              landing={@landing}
              home_url={@urls.home}
              section="features-section"
              class={footer_link_class()}
            >
              {dgettext("public", "Features")}
            </PublicNavigation.section_link>
            <PublicNavigation.section_link
              landing={@landing}
              home_url={@urls.home}
              section="discover"
              class={footer_link_class()}
            >
              {dgettext("public", "Discover")}
            </PublicNavigation.section_link>
            <PublicNavigation.section_link
              landing={@landing}
              home_url={@urls.home}
              section="workflow"
              class={footer_link_class()}
            >
              {dgettext("public", "Workflow")}
            </PublicNavigation.section_link>
            <.link navigate={@urls.docs} class={footer_link_class()}>
              {dgettext("public", "Docs")}
            </.link>
            <.link navigate={@urls.blog} class={footer_link_class()}>
              {dgettext("public", "Blog")}
            </.link>
            <.link navigate={@urls.contact} class={footer_link_class()}>
              {dgettext("public", "Contact")}
            </.link>
          </nav>
        </div>

        <div class="flex flex-col gap-4 border-t border-border/10 pt-6 text-sm text-muted-foreground/50 sm:flex-row sm:items-center sm:justify-between">
          <span>Storyarn &middot; {@year}</span>
          <div class="flex flex-wrap items-center gap-x-4 gap-y-2">
            <.link navigate={@urls.privacy} class={footer_link_class()}>
              {dgettext("public", "Privacy")}
            </.link>
            <.link navigate={@urls.terms} class={footer_link_class()}>
              {dgettext("public", "Terms")}
            </.link>
            <.link navigate={@urls.privacy <> "#cookies"} class={footer_link_class()}>
              {dgettext("public", "Cookies")}
            </.link>
            <button
              id="public-manage-cookies"
              type="button"
              class={footer_link_class()}
              phx-click={JS.dispatch("storyarn:open-cookie-settings")}
            >
              {dgettext("public", "Manage cookies")}
            </button>
          </div>
        </div>
      </div>
    </footer>
    """
  end

  defp footer_link_class, do: "transition-colors hover:text-foreground"
end

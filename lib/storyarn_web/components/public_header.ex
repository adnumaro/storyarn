defmodule StoryarnWeb.Components.PublicHeader do
  @moduledoc false

  use StoryarnWeb, :html

  alias StoryarnWeb.Components.PublicLanguageSwitcher
  alias StoryarnWeb.Components.PublicMobileNavigation
  alias StoryarnWeb.Components.PublicNavigation

  attr :dark, :boolean, required: true
  attr :landing, :boolean, required: true
  attr :signed_in, :boolean, required: true
  attr :urls, :map, required: true
  attr :current_locale, :string, required: true
  attr :language_links, :list, default: []

  def header(assigns) do
    ~H"""
    <header
      id="public-header"
      class={[
        "flex h-16 w-[min(calc(100%-48px),1280px)] items-center",
        @dark &&
          "fixed left-1/2 top-5 z-[120] -translate-x-1/2 rounded-full border border-border bg-background/70 px-5 shadow-[0_20px_80px_rgba(0,0,0,0.28)] backdrop-blur-xl",
        !@dark && "mx-auto"
      ]}
    >
      <div class="flex w-full items-center gap-4 px-4 sm:px-5 lg:px-6">
        <.link
          navigate={@urls.home}
          class="flex flex-none items-center"
          aria-label={dgettext("public", "Storyarn home")}
        >
          <img
            src={~p"/images/logos/logo-name-black.png"}
            alt="Storyarn"
            class="h-10.5 w-auto dark:hidden"
          />
          <img
            src={~p"/images/logos/logo-name-white.png"}
            alt="Storyarn"
            class="hidden h-10.5 w-auto dark:block"
          />
        </.link>

        <div class="hidden min-w-0 flex-1 items-center justify-between gap-6 xl:flex">
          <nav
            class="flex min-w-0 items-center gap-2"
            aria-label={dgettext("public", "Primary navigation")}
          >
            <PublicNavigation.section_link
              landing={@landing}
              home_url={@urls.home}
              section="features-section"
              class={nav_link_class()}
            >
              {dgettext("public", "Features")}
            </PublicNavigation.section_link>
            <PublicNavigation.section_link
              landing={@landing}
              home_url={@urls.home}
              section="discover"
              class={nav_link_class()}
            >
              {dgettext("public", "Discover")}
            </PublicNavigation.section_link>
            <.link navigate={@urls.docs} class={nav_link_class()}>{dgettext("public", "Docs")}</.link>
            <.link navigate={@urls.blog} class={nav_link_class()}>{dgettext("public", "Blog")}</.link>
            <.link navigate={@urls.contact} class={nav_link_class()}>
              {dgettext("public", "Contact")}
            </.link>
          </nav>

          <div class="flex flex-none items-center gap-2">
            <PublicLanguageSwitcher.switcher
              id="public-language-switcher"
              current_locale={@current_locale}
              links={@language_links}
              compact
            />
            <.link :if={@signed_in} navigate={@urls.workspaces} class={nav_link_class()}>
              {dgettext("public", "Dashboard")}
            </.link>
            <%= unless @signed_in do %>
              <.link navigate={@urls.register} class={registration_link_class()}>
                {dgettext("public", "Create account")}
              </.link>
              <.link navigate={@urls.login} class={nav_link_class()}>
                {dgettext("public", "Log in")}
              </.link>
            <% end %>
          </div>
        </div>

        <button
          id="public-mobile-menu-button"
          type="button"
          class="ml-auto inline-flex size-8 flex-none items-center justify-center rounded-md text-muted-foreground transition-colors hover:bg-accent hover:text-foreground xl:hidden"
          aria-label={dgettext("public", "Menu")}
          aria-controls="public-mobile-navigation"
          aria-expanded="false"
          phx-click={PublicMobileNavigation.open()}
        >
          <.icon name="menu" class="size-5" />
        </button>
      </div>
    </header>

    <PublicMobileNavigation.navigation
      dark={@dark}
      landing={@landing}
      signed_in={@signed_in}
      urls={@urls}
      current_locale={@current_locale}
      language_links={@language_links}
    />
    """
  end

  defp nav_link_class do
    "inline-flex items-center justify-center rounded-md px-4 py-2.5 text-sm font-medium " <>
      "text-foreground/80 transition-colors hover:bg-accent hover:text-foreground"
  end

  defp registration_link_class do
    "inline-flex items-center justify-center rounded-md bg-gradient-to-br from-cyan-300 to-cyan-500 " <>
      "px-5 py-2.5 text-sm font-bold text-teal-950 shadow-[0_0_20px_rgba(34,211,238,0.4),inset_0_1px_0_rgba(255,255,255,0.3)] " <>
      "transition-all hover:scale-105"
  end
end

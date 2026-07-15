defmodule StoryarnWeb.Components.PublicMobileNavigation do
  @moduledoc false

  use StoryarnWeb, :html

  alias Phoenix.LiveView.JS
  alias StoryarnWeb.Components.PublicLanguageSwitcher
  alias StoryarnWeb.Components.PublicNavigation

  attr :dark, :boolean, required: true
  attr :landing, :boolean, required: true
  attr :signed_in, :boolean, required: true
  attr :urls, :map, required: true
  attr :current_locale, :string, required: true
  attr :language_links, :list, default: []

  def navigation(assigns) do
    ~H"""
    <div
      id="public-mobile-navigation"
      class={[
        "fixed inset-0 z-[140] hidden w-screen max-w-none xl:hidden",
        @dark && "bg-background/96 backdrop-blur-xl"
      ]}
      role="dialog"
      aria-modal="true"
      aria-hidden="true"
      aria-label={dgettext("public", "Mobile navigation")}
      phx-window-keydown={close()}
      phx-key="Escape"
    >
      <.focus_wrap
        id="public-mobile-navigation-focus-wrap"
        class="min-h-screen w-full"
      >
        <aside class="flex min-h-screen w-full justify-center bg-background/98 px-5 pb-8 pt-5">
          <div class="flex min-h-full w-full max-w-105 flex-col">
            <div class="flex items-center justify-between gap-4">
              <.link
                navigate={@urls.home}
                class="flex items-center text-foreground"
                phx-click={close()}
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
              <button
                id="public-mobile-menu-close"
                type="button"
                class="inline-flex size-8 items-center justify-center rounded-md text-muted-foreground transition-colors hover:bg-accent hover:text-foreground"
                aria-label={dgettext("public", "Close")}
                phx-click={close()}
              >
                <.icon name="x" class="size-5" />
              </button>
            </div>

            <nav class="mt-8 grid gap-2" aria-label={dgettext("public", "Mobile navigation links")}>
              <PublicNavigation.section_link
                landing={@landing}
                home_url={@urls.home}
                section="features-section"
                class={mobile_link_class()}
                phx-click={close()}
              >
                <.icon name="sparkles" class="size-5 text-foreground/45" />
                {dgettext("public", "Features")}
              </PublicNavigation.section_link>
              <PublicNavigation.section_link
                landing={@landing}
                home_url={@urls.home}
                section="discover"
                class={mobile_link_class()}
                phx-click={close()}
              >
                <.icon name="panels-top-left" class="size-5 text-foreground/45" />
                {dgettext("public", "Discover")}
              </PublicNavigation.section_link>
              <.link navigate={@urls.docs} class={mobile_link_class()} phx-click={close()}>
                <.icon name="book-open" class="size-5 text-foreground/45" />
                {dgettext("public", "Docs")}
              </.link>
              <.link navigate={@urls.blog} class={mobile_link_class()} phx-click={close()}>
                <.icon name="newspaper" class="size-5 text-foreground/45" />
                {dgettext("public", "Blog")}
              </.link>
              <.link navigate={@urls.contact} class={mobile_link_class()} phx-click={close()}>
                <.icon name="mail" class="size-5 text-foreground/45" />
                {dgettext("public", "Contact")}
              </.link>
            </nav>

            <div class="mt-auto grid gap-3 border-t border-border pt-5">
              <PublicLanguageSwitcher.switcher
                id="public-mobile-language-switcher"
                current_locale={@current_locale}
                links={@language_links}
                on_navigate={close()}
              />
              <.link
                :if={@signed_in}
                navigate={@urls.workspaces}
                class="inline-flex w-full items-center justify-center rounded-2xl bg-primary px-4 py-2 text-sm font-medium text-primary-foreground transition-colors hover:bg-primary/90"
                phx-click={close()}
              >
                {dgettext("public", "Dashboard")}
              </.link>
              <%= unless @signed_in do %>
                <.link
                  navigate={@urls.register}
                  class={registration_link_class()}
                  phx-click={close()}
                >
                  {dgettext("public", "Create account")}
                </.link>
                <.link
                  navigate={@urls.login}
                  class="inline-flex w-full items-center justify-center rounded-2xl px-3 py-2 text-sm transition-colors hover:bg-accent"
                  phx-click={close()}
                >
                  {dgettext("public", "Log in")}
                </.link>
              <% end %>
            </div>
          </div>
        </aside>
      </.focus_wrap>
    </div>
    """
  end

  def open(js \\ %JS{}) do
    js
    |> JS.push_focus()
    |> JS.remove_class("hidden", to: "#public-mobile-navigation")
    |> JS.set_attribute({"aria-hidden", "false"}, to: "#public-mobile-navigation")
    |> JS.set_attribute({"aria-expanded", "true"}, to: "#public-mobile-menu-button")
    |> JS.set_attribute({"inert", ""}, to: "#public-header")
    |> JS.set_attribute({"inert", ""}, to: "#public-main")
    |> JS.set_attribute({"inert", ""}, to: "#public-footer")
    |> JS.set_attribute({"inert", ""}, to: "#flash-group")
    |> JS.add_class("overflow-hidden", to: "body")
    |> JS.focus(to: "#public-mobile-menu-close")
  end

  def close(js \\ %JS{}) do
    js
    |> JS.add_class("hidden", to: "#public-mobile-navigation")
    |> JS.set_attribute({"aria-hidden", "true"}, to: "#public-mobile-navigation")
    |> JS.set_attribute({"aria-expanded", "false"}, to: "#public-mobile-menu-button")
    |> JS.remove_attribute("inert", to: "#public-header")
    |> JS.remove_attribute("inert", to: "#public-main")
    |> JS.remove_attribute("inert", to: "#public-footer")
    |> JS.remove_attribute("inert", to: "#flash-group")
    |> JS.remove_class("overflow-hidden", to: "body")
    |> JS.pop_focus()
  end

  defp mobile_link_class do
    "flex items-center gap-3 rounded-2xl px-4 py-3 text-base font-medium text-foreground " <>
      "transition-colors hover:bg-accent"
  end

  defp registration_link_class do
    "inline-flex w-full items-center justify-center rounded-xl bg-gradient-to-br from-cyan-300 to-cyan-500 " <>
      "px-4 py-2.5 text-sm font-bold text-teal-950 shadow-[0_0_20px_rgba(34,211,238,0.4),inset_0_1px_0_rgba(255,255,255,0.3)] " <>
      "transition-all hover:scale-105"
  end
end

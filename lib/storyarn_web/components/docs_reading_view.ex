defmodule StoryarnWeb.Components.DocsReadingView do
  @moduledoc """
  Complete public documentation content for the initial HTTP response.

  Uses the same guide and navigation data as the connected Vue layout, so
  readers can follow the documentation before JavaScript or LiveView connects.
  """

  use StoryarnWeb, :html

  alias Storyarn.Platform.Shared.HtmlSanitizer
  alias Storyarn.Public.Publication.Locales, as: PublicLocales
  alias StoryarnWeb.Components.PublicLanguageSwitcher

  attr :docs, :map, required: true
  attr :guide, :map, default: nil
  attr :language_links, :list, default: []

  def reading(assigns) do
    ~H"""
    <div id="docs-reading-view" class="flex h-full min-h-0 flex-col bg-background">
      <header class="flex min-h-12 shrink-0 items-center justify-between gap-4 border-b border-border px-4 py-2 sm:px-6">
        <.link
          id="docs-reading-home"
          navigate={@docs.urls.home}
          aria-label={dgettext("public", "Storyarn home")}
          class="min-w-0 shrink"
        >
          <img
            src={~p"/images/logos/logo-name-black-docs.png"}
            alt="Storyarn docs"
            class="h-auto w-40 dark:hidden"
          />
          <img
            src={~p"/images/logos/logo-name-white-docs.png"}
            alt="Storyarn docs"
            class="hidden h-auto w-40 dark:block"
          />
        </.link>

        <div class="flex shrink-0 items-center gap-3">
          <PublicLanguageSwitcher.switcher
            id="docs-reading-language-switcher"
            current_locale={@docs.currentLocale}
            links={@language_links}
            compact
          />
          <.link
            id="docs-reading-account-link"
            navigate={if @docs.signedIn, do: @docs.urls.workspaces, else: @docs.urls.login}
            class="rounded-md px-3 py-1.5 text-sm font-medium transition-colors hover:bg-accent"
          >
            {if @docs.signedIn, do: dgettext("public", "Dashboard"), else: dgettext("public", "Log in")}
          </.link>
        </div>
      </header>

      <div class="flex min-h-0 flex-1">
        <aside class="hidden w-64 shrink-0 overflow-y-auto border-r border-border bg-surface px-4 py-6 lg:block">
          <.guide_navigation id="docs-reading-navigation" docs={@docs} />
        </aside>

        <main id="docs-main" class="min-w-0 flex-1 overflow-y-auto px-4 sm:px-8 lg:px-12">
          <div class="mx-auto w-full max-w-4xl py-8">
            <details class="mb-8 rounded-lg border border-border p-4 lg:hidden">
              <summary class="cursor-pointer text-sm font-semibold">
                {dgettext("docs", "Documentation")}
              </summary>
              <div class="mt-4">
                <.guide_navigation id="docs-reading-mobile-navigation" docs={@docs} />
              </div>
            </details>

            <article :if={@guide} id="docs-reading-article" lang={PublicLocales.language_tag(@docs.currentLocale)}>
              <header class="mb-8">
                <p class="mb-1 text-xs font-semibold uppercase tracking-wider text-primary">
                  {@guide.category_label}
                </p>
                <h1 id="docs-reading-title" class="text-3xl font-bold">{@guide.title}</h1>
                <p :if={@guide.description} class="mt-2 text-muted-foreground">{@guide.description}</p>
              </header>

              <div id="docs-reading-body" class="docs-content max-w-none">
                {raw(HtmlSanitizer.sanitize_html(@guide.body))}
              </div>
            </article>

            <h1 :if={!@guide} class="text-3xl font-bold">{dgettext("docs", "Documentation")}</h1>

            <nav
              :if={@docs.prev || @docs.next}
              id="docs-reading-sequence"
              aria-label={dgettext("docs", "Documentation")}
              class="mt-12 flex items-start justify-between gap-6 border-t border-border pt-8"
            >
              <div>
                <.link
                  :if={@docs.prev}
                  id="docs-reading-prev-link"
                  navigate={@docs.prev.url}
                  rel="prev"
                  class="inline-flex items-center gap-2 text-sm font-medium text-primary transition-colors hover:text-foreground"
                >
                  <.icon name="arrow-left" class="size-4 shrink-0" />
                  {@docs.prev.title}
                </.link>
              </div>
              <div class="text-right">
                <.link
                  :if={@docs.next}
                  id="docs-reading-next-link"
                  navigate={@docs.next.url}
                  rel="next"
                  class="inline-flex items-center gap-2 text-sm font-medium text-primary transition-colors hover:text-foreground"
                >
                  {@docs.next.title}
                  <.icon name="arrow-right" class="size-4 shrink-0" />
                </.link>
              </div>
            </nav>
          </div>
        </main>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :docs, :map, required: true

  defp guide_navigation(assigns) do
    ~H"""
    <nav id={@id} aria-label={dgettext("docs", "Documentation")}>
      <section :for={category <- @docs.categories} class="mb-5">
        <h2 class="mb-2 px-3 text-sm font-semibold">{category.label}</h2>
        <ul class="ml-3 space-y-0.5 border-l border-border">
          <li :for={guide <- Enum.filter(@docs.guides, &(&1.category == category.id))}>
            <.link
              navigate={guide.url}
              aria-current={if @docs.guide && @docs.guide.url == guide.url, do: "page"}
              class={[
                "-ml-px block border-l-2 px-3 py-1.5 text-sm transition-colors",
                if(@docs.guide && @docs.guide.url == guide.url,
                  do: "border-primary font-medium text-primary",
                  else: "border-transparent text-muted-foreground hover:border-border hover:text-foreground"
                )
              ]}
            >
              {guide.title}
            </.link>
          </li>
        </ul>
      </section>
    </nav>
    """
  end
end

defmodule StoryarnWeb.DocsLive.Show do
  @moduledoc false
  use StoryarnWeb, :live_view

  alias Storyarn.Docs
  alias Storyarn.Publication.Locales, as: PublicLocales
  alias Storyarn.Shared.HtmlSanitizer
  alias StoryarnWeb.PublicURLs

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       docs_locale: nil,
       categories: [],
       guides: [],
       search_query: "",
       search_results: nil,
       sidebar_open: true,
       expanded_categories: MapSet.new()
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    socket = prepare_locale(socket, socket.assigns.locale)
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    case Docs.first_guide(socket.assigns.locale) do
      nil ->
        assign(socket,
          page_title: dgettext("docs", "Documentation"),
          seo_description:
            dgettext(
              "docs",
              "Learn how to use Storyarn for narrative design, branching dialogue, worldbuilding, scenes, localization, and game engine export."
            ),
          guide: nil,
          prev: nil,
          next: nil
        )

      guide ->
        push_navigate(socket, to: PublicURLs.docs_path(socket.assigns.locale, guide))
    end
  end

  defp apply_action(socket, :show, %{"category" => category, "path" => path}) do
    locale = socket.assigns.locale
    slug = Enum.join(path, "/")

    case Docs.get_guide(category, slug, locale) do
      nil ->
        raise Ecto.NoResultsError, queryable: "docs_guides"

      guide ->
        {prev, next} = Docs.prev_next(category, slug, locale)
        canonical_url = Layouts.absolute_url(PublicURLs.docs_path(locale, guide))
        description = guide.description || docs_description()
        locale_paths = guide_locale_paths(category, slug)

        assign(socket,
          page_title: guide.title,
          canonical_url: canonical_url,
          seo_description: description,
          seo_type: "article",
          seo_alternate_links: PublicURLs.alternate_links(locale_paths),
          seo_json_ld: structured_data(guide, locale, canonical_url, description),
          language_links: PublicURLs.language_links(locale_paths),
          guide: guide,
          prev: prev,
          next: next
        )
    end
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    query = String.trim(query)

    results =
      if String.length(query) >= 2 do
        Docs.search(query, socket.assigns.locale)
      end

    {:noreply, assign(socket, search_query: query, search_results: results)}
  end

  def handle_event("clear_search", _, socket) do
    {:noreply, assign(socket, search_query: "", search_results: nil)}
  end

  def handle_event("toggle_sidebar", _, socket) do
    {:noreply, assign(socket, sidebar_open: !socket.assigns.sidebar_open)}
  end

  def handle_event("toggle_category", %{"category" => category}, socket) do
    expanded = socket.assigns.expanded_categories

    expanded =
      if MapSet.member?(expanded, category),
        do: MapSet.delete(expanded, category),
        else: MapSet.put(expanded, category)

    {:noreply, assign(socket, expanded_categories: expanded)}
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :seo_metadata, Layouts.live_seo_metadata(assigns))

    ~H"""
    <StoryarnWeb.Components.DocsLayout.docs
      flash={@flash}
      socket={@socket}
      seo_metadata={@seo_metadata}
      current_scope={@current_scope}
      categories={@categories}
      guides={@guides}
      guide={@guide}
      expanded_categories={@expanded_categories}
      search_query={@search_query}
      search_results={@search_results}
      prev={@prev}
      next={@next}
      sidebar_open={@sidebar_open}
      locale={@locale}
      language_links={@language_links}
    >
      <.vue
        v-component="live/docs/show/DocsContent"
        v-socket={@socket}
        v-inject="docs-layout"
        id="docs-show-vue"
        guide-body={if @guide, do: HtmlSanitizer.sanitize_html(@guide.body)}
      />
    </StoryarnWeb.Components.DocsLayout.docs>
    """
  end

  defp prepare_locale(socket, locale) do
    if socket.assigns.docs_locale == locale do
      socket
    else
      categories = Docs.list_categories(locale)

      if categories == [] do
        raise Ecto.NoResultsError, queryable: "docs_locales"
      end

      assign(socket,
        docs_locale: locale,
        categories: categories,
        guides: Docs.list_guides(locale),
        search_query: "",
        search_results: nil,
        expanded_categories: MapSet.new(categories, fn {category, _label} -> category end)
      )
    end
  end

  defp guide_locale_paths(category, slug) do
    Enum.flat_map(PublicLocales.locales(), fn locale ->
      case Docs.get_guide(category, slug, locale) do
        nil -> []
        guide -> [{locale, PublicURLs.docs_path(locale, guide)}]
      end
    end)
  end

  defp structured_data(guide, locale, canonical_url, description) do
    %{
      "@context" => "https://schema.org",
      "@type" => "TechArticle",
      "description" => description,
      "headline" => guide.title,
      "inLanguage" => PublicLocales.language_tag(locale),
      "mainEntityOfPage" => %{"@id" => canonical_url, "@type" => "WebPage"},
      "publisher" => %{
        "@type" => "Organization",
        "name" => "Storyarn",
        "url" => Layouts.absolute_url(PublicURLs.home_path(PublicLocales.default_locale()))
      },
      "url" => canonical_url
    }
  end

  defp docs_description do
    dgettext(
      "docs",
      "Storyarn documentation for game narrative workflows, branching dialogue, worldbuilding, scenes, localization, and export."
    )
  end
end

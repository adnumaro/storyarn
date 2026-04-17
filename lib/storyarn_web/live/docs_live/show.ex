defmodule StoryarnWeb.DocsLive.Show do
  @moduledoc false
  use StoryarnWeb, :live_view

  alias Storyarn.Docs
  alias Storyarn.Shared.HtmlSanitizer

  @impl true
  def mount(_params, _session, socket) do
    locale = docs_locale()
    categories = Docs.list_categories(locale)
    guides = Docs.list_guides(locale)

    # All categories start expanded
    expanded =
      MapSet.new(categories, fn {cat, _label} -> cat end)

    {:ok,
     assign(socket,
       locale: locale,
       categories: categories,
       guides: guides,
       search_query: "",
       search_results: nil,
       sidebar_open: false,
       expanded_categories: expanded
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    case Docs.first_guide(socket.assigns.locale) do
      nil ->
        assign(socket, page_title: gettext("Documentation"), guide: nil, prev: nil, next: nil)

      guide ->
        push_navigate(socket, to: ~p"/docs/#{guide.category}/#{guide.slug}")
    end
  end

  defp apply_action(socket, :show, %{"category" => category, "slug" => slug}) do
    locale = socket.assigns.locale

    case Docs.get_guide(category, slug, locale) do
      nil ->
        socket
        |> put_flash(:error, gettext("Guide not found"))
        |> push_navigate(to: ~p"/docs")

      guide ->
        {prev, next} = Docs.prev_next(category, slug, locale)

        assign(socket,
          page_title: guide.title,
          guide: guide,
          prev: prev,
          next: next,
          sidebar_open: false
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
    ~H"""
    <Layouts.docs
      flash={@flash}
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
    >
      <.vue
        v-component="docs/DocsShow"
        v-socket={@socket}
        id="docs-show-vue"
        guide-body={if @guide, do: HtmlSanitizer.sanitize_html(@guide.body)}
      />
    </Layouts.docs>
    """
  end

  # Use current Gettext locale if docs exist for it, otherwise fall back to English.
  defp docs_locale do
    locale = Gettext.get_locale(Storyarn.Gettext)
    if Docs.list_guides(locale) == [], do: "en", else: locale
  end
end

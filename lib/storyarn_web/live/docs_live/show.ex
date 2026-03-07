defmodule StoryarnWeb.DocsLive.Show do
  use StoryarnWeb, :live_view

  alias Storyarn.Docs

  @impl true
  def mount(_params, _session, socket) do
    categories = Docs.list_categories()
    guides = Docs.list_guides()

    # All categories start expanded
    expanded =
      categories
      |> Enum.map(fn {cat, _label} -> cat end)
      |> MapSet.new()

    {:ok,
     assign(socket,
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
    case Docs.first_guide() do
      nil ->
        assign(socket, page_title: gettext("Documentation"), guide: nil, prev: nil, next: nil)

      guide ->
        push_navigate(socket, to: ~p"/docs/#{guide.category}/#{guide.slug}")
    end
  end

  defp apply_action(socket, :show, %{"category" => category, "slug" => slug}) do
    case Docs.get_guide(category, slug) do
      nil ->
        socket
        |> put_flash(:error, gettext("Guide not found"))
        |> push_navigate(to: ~p"/docs")

      guide ->
        {prev, next} = Docs.prev_next(category, slug)

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
        Docs.search(query)
      else
        nil
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
      <div :if={@guide} class="docs-content">
        {Phoenix.HTML.raw(@guide.body)}
      </div>

      <div :if={!@guide} class="text-center py-20">
        <.icon name="book-open" class="size-12 text-base-content/30 mx-auto mb-4" />
        <p class="text-base-content/50">{gettext("No documentation available yet.")}</p>
      </div>
    </Layouts.docs>
    """
  end
end

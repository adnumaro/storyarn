defmodule StoryarnWeb.DocsLive.Components.DocsSidebar do
  @moduledoc """
  Sidebar navigation for the documentation pages.
  """
  use StoryarnWeb, :html

  attr :categories, :list, required: true
  attr :guides, :list, required: true
  attr :guide, :map, default: nil
  attr :expanded_categories, :any, default: nil
  attr :search_query, :string, default: ""
  attr :search_results, :list, default: nil

  def docs_sidebar(assigns) do
    ~H"""
    <nav class="px-4 space-y-1">
      <div class="mb-5">
        <form phx-change="search" phx-submit="search" class="relative">
          <.icon
            name="search"
            class="size-4 absolute left-3 top-1/2 -translate-y-1/2 text-muted-foreground"
          />
          <input
            type="text"
            value={@search_query}
            placeholder={gettext("Search docs...")}
            name="query"
            class="h-8 rounded-md border border-input bg-background px-2 text-sm input-bordered w-full pl-9 pr-8"
            autocomplete="off"
          />
          <button
            :if={@search_query != ""}
            type="button"
            phx-click="clear_search"
            class="absolute right-2 top-1/2 -translate-y-1/2 text-muted-foreground hover:text-foreground"
          >
            <.icon name="x" class="size-4" />
          </button>
        </form>
      </div>

      <div :if={@search_results} class="mb-4">
        <p class="text-xs text-muted-foreground mb-2 px-3">
          {ngettext("%{count} result", "%{count} results", length(@search_results),
            count: length(@search_results)
          )}
        </p>
        <ul class="space-y-0.5">
          <li :for={result <- @search_results}>
            <.link
              navigate={~p"/docs/#{result.category}/#{result.slug}"}
              class="block px-3 py-2 rounded-lg text-sm hover:bg-muted truncate"
            >
              <span class="text-foreground">{result.title}</span>
              <span class="text-xs text-muted-foreground ml-1">{result.category_label}</span>
            </.link>
          </li>
        </ul>
      </div>

      <div :for={{category, label} <- @categories} :if={!@search_results} class="mb-1">
        <button
          phx-click="toggle_category"
          phx-value-category={category}
          class="flex items-center justify-between w-full px-3 py-2 rounded-lg text-sm font-semibold text-foreground hover:bg-muted transition-colors"
        >
          <span>{label}</span>
          <.icon
            name={
              if expanded?(category, @expanded_categories), do: "chevron-down", else: "chevron-right"
            }
            class="size-4 text-muted-foreground"
          />
        </button>
        <ul
          :if={expanded?(category, @expanded_categories)}
          class="mt-0.5 ml-3 border-l border-border space-y-0.5"
        >
          <li :for={g <- guides_for(@guides, category)}>
            <.link
              navigate={~p"/docs/#{g.category}/#{g.slug}"}
              class={[
                "block px-3 py-1.5 text-sm transition-colors -ml-px border-l-2",
                if(active?(@guide, g),
                  do: "border-primary text-primary font-medium",
                  else:
                    "border-transparent text-muted-foreground hover:text-foreground hover:border-border"
                )
              ]}
            >
              {g.title}
            </.link>
          </li>
        </ul>
      </div>
    </nav>
    """
  end

  defp guides_for(guides, category) do
    Enum.filter(guides, &(&1.category == category))
  end

  defp expanded?(category, expanded_categories) do
    expanded_categories && MapSet.member?(expanded_categories, category)
  end

  defp active?(nil, _g), do: false
  defp active?(guide, g), do: guide.slug == g.slug && guide.category == g.category
end

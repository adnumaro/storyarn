defmodule StoryarnWeb.SceneLive.Components.SceneSearchPanel do
  @moduledoc """
  Search panel component for the map editor.

  Renders the search input, type filter tabs, search results list, and no-results state.
  """

  use Phoenix.Component
  use Gettext, backend: Storyarn.Gettext

  import StoryarnWeb.Components.CoreComponents
  import StoryarnWeb.SceneLive.Helpers.SceneHelpers, only: [search_result_icon: 1]

  attr :search_query, :string, required: true
  attr :search_filter, :string, required: true
  attr :search_results, :list, required: true

  def map_search_panel(assigns) do
    ~H"""
    <div class="relative">
      <%!-- Input pill — matches surface-panel toolbar style --%>
      <div class="surface-panel">
        <form id="search-form" phx-change="search_elements" phx-submit="search_elements">
          <div class="flex items-center gap-2 px-3 py-1.5">
            <.icon name="search" class="size-4 text-base-content/40 shrink-0" />
            <input
              type="text"
              name="query"
              value={@search_query}
              placeholder={dgettext("scenes", "Search elements...")}
              phx-debounce="300"
              autocomplete="off"
              class="flex-1 bg-transparent text-sm border-none outline-none placeholder:text-base-content/30 p-0 w-40 h-8"
            />
            <button
              :if={@search_query != ""}
              type="button"
              phx-click="clear_search"
              class="btn btn-ghost btn-xs btn-square"
            >
              <.icon name="x" class="size-3" />
            </button>
          </div>
        </form>
      </div>

      <%!-- Dropdown: filter tabs + results (appears below the pill) --%>
      <div
        :if={@search_query != ""}
        class="absolute top-full left-0 mt-1 w-full min-w-56 bg-base-100 rounded-xl border border-base-300 shadow-md z-10"
      >
        <%!-- Type filter tabs --%>
        <div class="flex gap-1 px-2 py-1.5 flex-wrap">
          <button
            :for={
              {label, value} <- [
                {dgettext("scenes", "All"), "all"},
                {dgettext("scenes", "Pins"), "pin"},
                {dgettext("scenes", "Zones"), "zone"},
                {dgettext("scenes", "Notes"), "annotation"},
                {dgettext("scenes", "Lines"), "connection"}
              ]
            }
            type="button"
            phx-click="set_search_filter"
            phx-value-filter={value}
            class={"btn btn-xs #{if @search_filter == value, do: "btn-primary", else: "btn-ghost"}"}
          >
            {label}
          </button>
        </div>

        <%!-- Search results --%>
        <div
          :if={@search_results != []}
          class="max-h-48 overflow-y-auto border-t border-base-300"
        >
          <button
            :for={result <- @search_results}
            type="button"
            phx-click="focus_search_result"
            phx-value-type={result.type}
            phx-value-id={result.id}
            class="w-full flex items-center gap-2 px-3 py-1.5 hover:bg-base-200 text-left"
          >
            <.icon name={search_result_icon(result.type)} class="size-3.5 text-base-content/50" />
            <span class="text-xs truncate">{result.label}</span>
          </button>
        </div>

        <%!-- No results --%>
        <div
          :if={@search_results == []}
          class="px-3 py-2 text-xs text-base-content/50 border-t border-base-300"
        >
          {dgettext("scenes", "No results found")}
        </div>
      </div>
    </div>
    """
  end
end

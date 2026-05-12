defmodule StoryarnWeb.Components.DocsLayout do
  @moduledoc """
  LiveVue layout boundary for documentation pages.

  Docs content remains owned by the docs context and DocsLive. This wrapper only
  serializes the docs navigation/search state and mounts the public Vue layout
  boundary.
  """

  use StoryarnWeb, :html

  attr :flash, :map, required: true
  attr :socket, :any, required: true
  attr :current_scope, :map, default: nil
  attr :categories, :list, required: true
  attr :guides, :list, required: true
  attr :guide, :map, default: nil
  attr :expanded_categories, :any, default: nil
  attr :search_query, :string, default: ""
  attr :search_results, :list, default: nil
  attr :prev, :map, default: nil
  attr :next, :map, default: nil
  attr :sidebar_open, :boolean, default: false

  slot :inner_block, required: true

  def docs(assigns) do
    assigns = assign(assigns, :docs_layout, docs_layout_props(assigns))

    ~H"""
    <div id="docs-layout-wrapper">
      <.vue
        v-component="live/layouts/docs/Layout"
        v-socket={@socket}
        id="docs-layout"
        docs={@docs_layout}
      />

      {render_slot(@inner_block)}

      <Layouts.flash_group flash={@flash} />
    </div>
    """
  end

  defp docs_layout_props(assigns) do
    search_results =
      if is_nil(assigns.search_results) do
        nil
      else
        Enum.map(assigns.search_results, &docs_guide_nav/1)
      end

    %{
      signedIn: signed_in?(assigns.current_scope),
      urls: %{
        home: ~p"/",
        docs: ~p"/docs",
        workspaces: ~p"/workspaces",
        login: ~p"/users/log-in"
      },
      sidebarOpen: assigns.sidebar_open,
      categories: Enum.map(assigns.categories, &docs_category(&1, assigns.expanded_categories)),
      guides: Enum.map(assigns.guides, &docs_guide_nav/1),
      guide: docs_guide(assigns.guide),
      search: %{
        query: assigns.search_query,
        results: search_results
      },
      prev: docs_guide_nav(assigns.prev),
      next: docs_guide_nav(assigns.next)
    }
  end

  defp signed_in?(%{user: user}) when not is_nil(user), do: true
  defp signed_in?(_), do: false

  defp docs_category({id, label}, expanded_categories) do
    %{
      id: id,
      label: label,
      expanded: expanded?(id, expanded_categories)
    }
  end

  defp expanded?(id, %MapSet{} = expanded_categories), do: MapSet.member?(expanded_categories, id)
  defp expanded?(_id, _expanded_categories), do: false

  defp docs_guide(nil), do: nil

  defp docs_guide(guide) do
    guide
    |> docs_guide_nav()
    |> Map.merge(%{
      description: Map.get(guide, :description),
      toc: Enum.map(Map.get(guide, :toc, []), &docs_toc_entry/1)
    })
  end

  defp docs_guide_nav(nil), do: nil

  defp docs_guide_nav(guide) do
    category = Map.fetch!(guide, :category)
    slug = Map.fetch!(guide, :slug)

    %{
      category: category,
      categoryLabel: Map.get(guide, :category_label),
      slug: slug,
      title: Map.fetch!(guide, :title),
      url: ~p"/docs/#{category}/#{slug}"
    }
  end

  defp docs_toc_entry(entry) do
    %{
      level: Map.get(entry, :level),
      id: Map.get(entry, :id),
      text: Map.get(entry, :text)
    }
  end
end

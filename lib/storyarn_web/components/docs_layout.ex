defmodule StoryarnWeb.Components.DocsLayout do
  @moduledoc """
  LiveVue layout boundary for documentation pages.

  Docs content remains owned by the docs context and DocsLive. This wrapper only
  serializes the docs navigation/search state and mounts the public Vue layout
  boundary.
  """

  use StoryarnWeb, :html

  alias Storyarn.Localization.Languages
  alias StoryarnWeb.PublicURLs

  attr :flash, :map, required: true
  attr :socket, :any, required: true
  attr :seo_metadata, :map, required: true
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
  attr :locale, :string, required: true
  attr :language_links, :list, default: []

  slot :inner_block, required: true

  def docs(assigns) do
    assigns = assign(assigns, :docs_layout, docs_layout_props(assigns))

    ~H"""
    <div id="docs-layout-wrapper" class="h-screen overflow-hidden bg-surface text-foreground">
      <Layouts.live_seo metadata={@seo_metadata} />
      <.vue
        v-component="live/layouts/docs/Layout"
        v-socket={@socket}
        id="docs-layout"
        docs={@docs_layout}
      />

      {render_slot(@inner_block)}

      <Layouts.flash_group
        flash={@flash}
        socket={@socket}
        privacy_url={PublicURLs.privacy_path(@locale) <> "#cookies"}
        terms_url={PublicURLs.terms_path(@locale)}
      />
    </div>
    """
  end

  defp docs_layout_props(assigns) do
    search_results =
      if is_nil(assigns.search_results) do
        nil
      else
        Enum.map(assigns.search_results, &docs_guide_nav(&1, assigns.locale))
      end

    %{
      signedIn: signed_in?(assigns.current_scope),
      currentLocale: assigns.locale,
      languageLinks: Enum.map(assigns.language_links, &language_link/1),
      urls: %{
        home: PublicURLs.home_path(assigns.locale),
        docs: PublicURLs.docs_index_path(assigns.locale),
        workspaces: ~p"/workspaces",
        login: PublicURLs.locale_handoff_path(~p"/users/log-in", assigns.locale)
      },
      sidebarOpen: assigns.sidebar_open,
      categories: Enum.map(assigns.categories, &docs_category(&1, assigns.expanded_categories)),
      guides: Enum.map(assigns.guides, &docs_guide_nav(&1, assigns.locale)),
      guide: docs_guide(assigns.guide, assigns.locale),
      search: %{
        query: assigns.search_query,
        results: search_results
      },
      prev: docs_guide_nav(assigns.prev, assigns.locale),
      next: docs_guide_nav(assigns.next, assigns.locale)
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

  defp docs_guide(nil, _locale), do: nil

  defp docs_guide(guide, locale) do
    guide
    |> docs_guide_nav(locale)
    |> Map.merge(%{
      description: Map.get(guide, :description),
      toc: Enum.map(Map.get(guide, :toc, []), &docs_toc_entry/1)
    })
  end

  defp docs_guide_nav(nil, _locale), do: nil

  defp docs_guide_nav(guide, locale) do
    category = Map.fetch!(guide, :category)

    %{
      category: category,
      categoryLabel: Map.get(guide, :category_label),
      section: Map.get(guide, :section),
      sectionLabel: Map.get(guide, :section_label),
      sectionOrder: Map.get(guide, :section_order),
      slug: Map.fetch!(guide, :slug),
      path: Map.fetch!(guide, :path),
      title: Map.fetch!(guide, :title),
      url: PublicURLs.docs_path(locale, guide)
    }
  end

  defp language_link(link) do
    %{
      locale: link.locale,
      languageTag: link.language_tag,
      label: link.label,
      flagCode: Languages.flag_code(link.language_tag),
      shortLabel: Languages.short_label(link.language_tag),
      path: link.path
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

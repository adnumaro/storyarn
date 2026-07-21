defmodule Storyarn.Docs do
  @moduledoc """
  Public API for the documentation system.

  Content is compiled from Markdown files in `priv/docs/` at build time.
  This facade is the ONLY entry point for consumers (docs LiveView, sitemap,
  llms.txt) and enforces feature-flag visibility at runtime: a guide with a
  `feature_flag` frontmatter attribute is invisible on every surface — direct
  URL, indexes, search, prev/next navigation, sitemap, llms.txt — until the
  flag is globally enabled. Docs render for unauthenticated visitors, so
  gating uses global flag state, never a per-user actor.
  """

  alias Storyarn.Docs.Guide
  alias Storyarn.FeatureFlags

  def list_guides(locale \\ "en") do
    locale |> Guide.list_guides() |> Enum.filter(&visible?/1)
  end

  def list_categories(locale \\ "en") do
    locale
    |> list_guides()
    |> Enum.map(fn guide -> {guide.category, guide.category_label} end)
    |> Enum.uniq_by(fn {category, _label} -> category end)
  end

  def list_by_category(category, locale \\ "en") do
    category |> Guide.list_by_category(locale) |> Enum.filter(&visible?/1)
  end

  def get_guide(category, slug, locale \\ "en") do
    with %{} = guide <- Guide.get_guide(category, slug, locale),
         true <- visible?(guide) do
      guide
    else
      _hidden_or_missing -> nil
    end
  end

  def search(query, locale \\ "en") do
    query |> Guide.search(locale) |> Enum.filter(&visible?/1)
  end

  def first_guide(locale \\ "en") do
    locale |> list_guides() |> List.first()
  end

  @doc """
  Previous and next guides for navigation, computed over the VISIBLE list so
  navigation can never land on a flag-hidden guide.
  """
  def prev_next(category, slug, locale \\ "en") do
    path = String.split(slug, "/", trim: true)
    guides = list_guides(locale)

    index =
      Enum.find_index(guides, &(&1.category == category && (&1.path == path || &1.slug == slug)))

    prev = if index && index > 0, do: Enum.at(guides, index - 1)
    next = if index, do: Enum.at(guides, index + 1)

    {prev, next}
  end

  defp visible?(%{feature_flag: nil}), do: true
  defp visible?(%{feature_flag: flag}), do: FeatureFlags.enabled?(flag)
end

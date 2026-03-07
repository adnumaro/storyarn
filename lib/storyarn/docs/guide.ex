defmodule Storyarn.Docs.Guide do
  @moduledoc """
  Represents a documentation guide parsed from Markdown files at compile time.

  Guides are organized by category and ordered within each category.
  No database, no external dependencies — pure compile-time content.
  """

  use NimblePublisher,
    build: Storyarn.Docs.GuideBuilder,
    from: "priv/docs/**/*.md",
    as: :guides,
    highlighters: [:makeup_elixir]

  @doc "List all guides sorted by category order then guide order."
  def list_guides do
    @guides
    |> Enum.sort_by(fn g ->
      {category_order(g.category), g.order}
    end)
  end

  @doc "List categories in display order with their labels."
  def list_categories do
    list_guides()
    |> Enum.map(fn g -> {g.category, g.category_label} end)
    |> Enum.uniq_by(fn {cat, _} -> cat end)
  end

  @doc "Get a single guide by category and slug."
  def get_guide(category, slug) do
    Enum.find(@guides, &(&1.category == category && &1.slug == slug))
  end

  @doc "Get all guides in a category."
  def list_by_category(category) do
    @guides
    |> Enum.filter(&(&1.category == category))
    |> Enum.sort_by(& &1.order)
  end

  @doc "Simple text search across title and body."
  def search(query) when is_binary(query) and byte_size(query) > 0 do
    q = String.downcase(query)

    @guides
    |> Enum.filter(fn g ->
      String.contains?(String.downcase(g.title), q) ||
        String.contains?(String.downcase(g.body), q)
    end)
    |> Enum.sort_by(fn g ->
      if String.contains?(String.downcase(g.title), q), do: 0, else: 1
    end)
  end

  def search(_), do: []

  @doc "Get the first guide (for index redirect)."
  def first_guide do
    list_guides() |> List.first()
  end

  @doc "Get previous and next guides for navigation."
  def prev_next(category, slug) do
    guides = list_guides()
    index = Enum.find_index(guides, &(&1.category == category && &1.slug == slug))

    prev = if index && index > 0, do: Enum.at(guides, index - 1)
    next = if index, do: Enum.at(guides, index + 1)

    {prev, next}
  end

  defp category_order("welcome"), do: 0
  defp category_order("quick-start"), do: 1
  defp category_order("world-building"), do: 2
  defp category_order("narrative-design"), do: 3
  defp category_order("screenwriting"), do: 4
  defp category_order("scene-design"), do: 5
  defp category_order("localization"), do: 6
  defp category_order("collaboration"), do: 7
  defp category_order("import-export"), do: 8
  defp category_order(_), do: 99
end

defmodule Storyarn.Docs do
  @moduledoc """
  Public API for the documentation system.

  This context is fully isolated — it has zero dependencies on other Storyarn contexts.
  Content is compiled from Markdown files in `priv/docs/` at build time.
  """

  alias Storyarn.Docs.Guide

  defdelegate list_guides(locale \\ "en"), to: Guide
  defdelegate list_categories(locale \\ "en"), to: Guide
  defdelegate list_by_category(category, locale \\ "en"), to: Guide
  defdelegate get_guide(category, slug, locale \\ "en"), to: Guide
  defdelegate search(query, locale \\ "en"), to: Guide
  defdelegate first_guide(locale \\ "en"), to: Guide
  defdelegate prev_next(category, slug, locale \\ "en"), to: Guide
end

defmodule Storyarn.Docs do
  @moduledoc """
  Public API for the documentation system.

  This context is fully isolated — it has zero dependencies on other Storyarn contexts.
  Content is compiled from Markdown files in `priv/docs/` at build time.
  """

  alias Storyarn.Docs.Guide

  defdelegate list_guides(), to: Guide
  defdelegate list_categories(), to: Guide
  defdelegate list_by_category(category), to: Guide
  defdelegate get_guide(category, slug), to: Guide
  defdelegate search(query), to: Guide
  defdelegate first_guide(), to: Guide
  defdelegate prev_next(category, slug), to: Guide
end

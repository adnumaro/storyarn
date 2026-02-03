defmodule Storyarn.Shortcuts do
  @moduledoc """
  Utilities for generating and managing shortcuts for pages and flows.

  Shortcuts are unique identifiers within a project that can be used to
  reference pages and flows (e.g., #mc.jaime, #chapter-1).
  """

  import Ecto.Query, warn: false

  alias Storyarn.Flows.Flow
  alias Storyarn.Pages.Page
  alias Storyarn.Repo

  @doc """
  Generates a unique shortcut for a page based on its name.

  Returns a slugified version of the name, with a numeric suffix if needed
  to ensure uniqueness within the project (e.g., "page", "page-1", "page-2").
  """
  def generate_page_shortcut(name, project_id, exclude_page_id \\ nil) do
    base_shortcut = slugify(name)

    if base_shortcut == "" do
      nil
    else
      existing = list_page_shortcuts(project_id, exclude_page_id)
      find_unique_shortcut(base_shortcut, existing)
    end
  end

  @doc """
  Generates a unique shortcut for a flow based on its name.

  Returns a slugified version of the name, with a numeric suffix if needed
  to ensure uniqueness within the project (e.g., "flow", "flow-1", "flow-2").
  """
  def generate_flow_shortcut(name, project_id, exclude_flow_id \\ nil) do
    base_shortcut = slugify(name)

    if base_shortcut == "" do
      nil
    else
      existing = list_flow_shortcuts(project_id, exclude_flow_id)
      find_unique_shortcut(base_shortcut, existing)
    end
  end

  @doc """
  Slugifies a name into a valid shortcut format.

  - Converts to lowercase
  - Replaces spaces and underscores with hyphens
  - Removes invalid characters (keeps alphanumeric, dots, hyphens)
  - Removes leading/trailing dots and hyphens
  - Collapses multiple hyphens into one

  ## Examples

      iex> Storyarn.Shortcuts.slugify("My Character")
      "my-character"

      iex> Storyarn.Shortcuts.slugify("Chapter 1: The Beginning")
      "chapter-1-the-beginning"

      iex> Storyarn.Shortcuts.slugify("MC.Jaime")
      "mc.jaime"
  """
  def slugify(nil), do: ""
  def slugify(""), do: ""

  def slugify(name) when is_binary(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[\s_]+/, "-")
    |> String.replace(~r/[^a-z0-9.\-]/, "")
    |> String.replace(~r/-+/, "-")
    |> String.replace(~r/^[.\-]+/, "")
    |> String.replace(~r/[.\-]+$/, "")
  end

  # Private functions

  defp list_page_shortcuts(project_id, exclude_page_id) do
    query =
      from(p in Page,
        where:
          p.project_id == ^project_id and
            is_nil(p.deleted_at) and
            not is_nil(p.shortcut),
        select: p.shortcut
      )

    query =
      if exclude_page_id do
        where(query, [p], p.id != ^exclude_page_id)
      else
        query
      end

    Repo.all(query)
  end

  defp list_flow_shortcuts(project_id, exclude_flow_id) do
    query =
      from(f in Flow,
        where:
          f.project_id == ^project_id and
            not is_nil(f.shortcut),
        select: f.shortcut
      )

    query =
      if exclude_flow_id do
        where(query, [f], f.id != ^exclude_flow_id)
      else
        query
      end

    Repo.all(query)
  end

  defp find_unique_shortcut(base_shortcut, existing_shortcuts) do
    if base_shortcut in existing_shortcuts do
      find_unique_with_suffix(base_shortcut, existing_shortcuts, 1)
    else
      base_shortcut
    end
  end

  defp find_unique_with_suffix(base_shortcut, existing_shortcuts, counter) do
    candidate = "#{base_shortcut}-#{counter}"

    if candidate in existing_shortcuts do
      find_unique_with_suffix(base_shortcut, existing_shortcuts, counter + 1)
    else
      candidate
    end
  end
end

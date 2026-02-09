defmodule Storyarn.Shortcuts do
  @moduledoc """
  Utilities for generating and managing shortcuts for sheets and flows.

  Shortcuts are unique identifiers within a project that can be used to
  reference sheets and flows (e.g., #mc.jaime, #chapter-1).
  """

  import Ecto.Query, warn: false

  alias Storyarn.Flows.Flow
  alias Storyarn.Repo
  alias Storyarn.Screenplays.Screenplay
  alias Storyarn.Sheets.Sheet

  @doc """
  Generates a unique shortcut for a sheet based on its name.

  Returns a slugified version of the name, with a numeric suffix if needed
  to ensure uniqueness within the project (e.g., "sheet", "sheet-1", "sheet-2").
  """
  def generate_sheet_shortcut(name, project_id, exclude_sheet_id \\ nil) do
    base_shortcut = slugify(name)

    if base_shortcut == "" do
      nil
    else
      existing = list_sheet_shortcuts(project_id, exclude_sheet_id)
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
  Generates a unique shortcut for a screenplay based on its name.

  Returns a slugified version of the name, with a numeric suffix if needed
  to ensure uniqueness within the project (e.g., "screenplay", "screenplay-1").
  """
  def generate_screenplay_shortcut(name, project_id, exclude_screenplay_id \\ nil) do
    base_shortcut = slugify(name)

    if base_shortcut == "" do
      nil
    else
      existing = list_screenplay_shortcuts(project_id, exclude_screenplay_id)
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
    |> String.replace(~r/\.+/, ".")
    |> String.replace(~r/^[.\-]+/, "")
    |> String.replace(~r/[.\-]+$/, "")
  end

  # Private functions

  defp list_sheet_shortcuts(project_id, exclude_sheet_id) do
    query =
      from(s in Sheet,
        where:
          s.project_id == ^project_id and
            is_nil(s.deleted_at) and
            not is_nil(s.shortcut),
        select: s.shortcut
      )

    query =
      if exclude_sheet_id do
        where(query, [s], s.id != ^exclude_sheet_id)
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

  defp list_screenplay_shortcuts(project_id, exclude_screenplay_id) do
    query =
      from(s in Screenplay,
        where:
          s.project_id == ^project_id and
            is_nil(s.deleted_at) and
            not is_nil(s.shortcut),
        select: s.shortcut
      )

    query =
      if exclude_screenplay_id do
        where(query, [s], s.id != ^exclude_screenplay_id)
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

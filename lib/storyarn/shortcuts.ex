defmodule Storyarn.Shortcuts do
  @moduledoc """
  Utilities for generating and managing shortcuts for sheets and flows.

  Shortcuts are unique identifiers within a project that can be used to
  reference sheets and flows (e.g., #mc.jaime, #chapter-1).
  """

  import Ecto.Query, warn: false

  alias Storyarn.Flows.Flow
  alias Storyarn.Repo
  alias Storyarn.Scenes.Scene
  alias Storyarn.Screenplays.Screenplay
  alias Storyarn.Shared.NameNormalizer
  alias Storyarn.Sheets.Sheet

  @doc """
  Generates a unique shortcut for a sheet based on its name.

  Returns a slugified version of the name, with a numeric suffix if needed
  to ensure uniqueness within the project (e.g., "sheet", "sheet-1", "sheet-2").
  """
  def generate_sheet_shortcut(name, project_id, exclude_id \\ nil),
    do: generate_unique(name, &list_entity_shortcuts(Sheet, project_id, &1), exclude_id)

  def generate_flow_shortcut(name, project_id, exclude_id \\ nil),
    do: generate_unique(name, &list_entity_shortcuts(Flow, project_id, &1), exclude_id)

  def generate_screenplay_shortcut(name, project_id, exclude_id \\ nil),
    do: generate_unique(name, &list_entity_shortcuts(Screenplay, project_id, &1), exclude_id)

  def generate_scene_shortcut(name, project_id, exclude_id \\ nil),
    do: generate_unique(name, &list_entity_shortcuts(Scene, project_id, &1), exclude_id)

  defp generate_unique(name, list_fn, exclude_id) do
    base_shortcut = NameNormalizer.shortcutify(name)

    if base_shortcut == "" do
      nil
    else
      existing = list_fn.(exclude_id)
      find_unique_shortcut(base_shortcut, existing)
    end
  end

  # Private functions

  defp list_entity_shortcuts(schema, project_id, exclude_id) do
    query =
      from(e in schema,
        where:
          e.project_id == ^project_id and
            is_nil(e.deleted_at) and
            not is_nil(e.shortcut),
        select: e.shortcut
      )

    query =
      if exclude_id do
        where(query, [e], e.id != ^exclude_id)
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

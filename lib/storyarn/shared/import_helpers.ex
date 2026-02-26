defmodule Storyarn.Shared.ImportHelpers do
  @moduledoc """
  Shared import/export helper functions for hierarchical entities.
  Consolidates duplicated detect_shortcut_conflicts, soft_delete_by_shortcut,
  and bulk_insert functions across contexts.
  """

  import Ecto.Query
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers

  @doc """
  Detects which shortcuts from the given list already exist in the database
  for the given schema and project.
  Returns a list of conflicting shortcut strings.
  """
  def detect_shortcut_conflicts(_schema, _project_id, []), do: []

  def detect_shortcut_conflicts(schema, project_id, shortcuts) when is_list(shortcuts) do
    from(e in schema,
      where: e.project_id == ^project_id and e.shortcut in ^shortcuts and is_nil(e.deleted_at),
      select: e.shortcut
    )
    |> Repo.all()
  end

  @doc """
  Soft-deletes existing entities with the given shortcut (for overwrite import strategy).
  """
  def soft_delete_by_shortcut(schema, project_id, shortcut) do
    now = TimeHelpers.now()

    from(e in schema,
      where: e.project_id == ^project_id and e.shortcut == ^shortcut and is_nil(e.deleted_at)
    )
    |> Repo.update_all(set: [deleted_at: now])
  end

  @doc """
  Bulk-inserts records from a list of attr maps, chunked to avoid oversized queries.
  Returns a flat list of maps with :id keys from all inserted records.
  """
  def bulk_insert(schema, attrs_list, chunk_size \\ 500) do
    attrs_list
    |> Enum.chunk_every(chunk_size)
    |> Enum.flat_map(fn chunk ->
      {_count, inserted} = Repo.insert_all(schema, chunk, returning: [:id])
      inserted
    end)
  end
end

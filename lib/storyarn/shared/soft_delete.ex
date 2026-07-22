defmodule Storyarn.Shared.SoftDelete do
  @moduledoc """
  Shared recursive soft-delete logic for hierarchical entities.

  Extracts the common `soft_delete_children` pattern from flow_crud, scene_crud,
  and screenplay_crud. Accepts an optional `:pre_delete` callback for
  context-specific side effects (e.g., cleaning up localization texts).
  """

  import Ecto.Query, warn: false

  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers

  @doc """
  Lists soft-deleted entities for a project, ordered by deletion time (most recent first).
  """
  def list_deleted(schema, project_id) do
    Repo.all(
      from(s in schema, where: s.project_id == ^project_id and not is_nil(s.deleted_at), order_by: [desc: s.deleted_at])
    )
  end

  @doc """
  Recursively soft-deletes all children of a parent entity.

  Finds all non-deleted children of the given schema matching `project_id` and
  `parent_id`, sets their `deleted_at`, and recurses into each child's subtree.

  Returns the ids of every soft-deleted descendant — the authoritative cascade
  set, collected by the deletion itself (callers broadcasting about the delete
  must use THIS, never a separate pre-delete traversal, or concurrent tree
  changes desync the broadcast from the committed cascade).

  ## Options

    * `:pre_delete` - A function called with each child before soft-deleting it.
      Called as `pre_delete.(child)`. Use for side effects like cleaning up
      associated data (e.g., localization texts).
  """
  def soft_delete_children(schema, project_id, parent_id, opts \\ []) do
    pre_delete = Keyword.get(opts, :pre_delete)
    now = TimeHelpers.now()

    children =
      Repo.all(
        from(s in schema, where: s.project_id == ^project_id and s.parent_id == ^parent_id and is_nil(s.deleted_at))
      )

    Enum.flat_map(children, fn child ->
      if pre_delete, do: pre_delete.(child)

      Repo.update_all(from(s in schema, where: s.id == ^child.id), set: [deleted_at: now])
      [child.id | soft_delete_children(schema, project_id, child.id, opts)]
    end)
  end
end

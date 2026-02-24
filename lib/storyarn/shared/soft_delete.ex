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
    from(s in schema,
      where: s.project_id == ^project_id and not is_nil(s.deleted_at),
      order_by: [desc: s.deleted_at]
    )
    |> Repo.all()
  end

  @doc """
  Recursively soft-deletes all children of a parent entity.

  Finds all non-deleted children of the given schema matching `project_id` and
  `parent_id`, sets their `deleted_at`, and recurses into each child's subtree.

  ## Options

    * `:pre_delete` - A function called with each child before soft-deleting it.
      Called as `pre_delete.(child)`. Use for side effects like cleaning up
      associated data (e.g., localization texts).
  """
  def soft_delete_children(schema, project_id, parent_id, opts \\ []) do
    pre_delete = Keyword.get(opts, :pre_delete)
    now = TimeHelpers.now()

    children =
      from(s in schema,
        where:
          s.project_id == ^project_id and
            s.parent_id == ^parent_id and
            is_nil(s.deleted_at)
      )
      |> Repo.all()

    Enum.each(children, fn child ->
      if pre_delete, do: pre_delete.(child)

      from(s in schema, where: s.id == ^child.id)
      |> Repo.update_all(set: [deleted_at: now])

      soft_delete_children(schema, project_id, child.id, opts)
    end)
  end
end

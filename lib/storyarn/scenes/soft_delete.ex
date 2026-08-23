defmodule Storyarn.Scenes.SoftDelete do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers

  def list_deleted(schema, project_id) do
    Repo.all(
      from entity in schema,
        where: entity.project_id == ^project_id and not is_nil(entity.deleted_at),
        order_by: [desc: entity.deleted_at]
    )
  end

  def soft_delete_children(schema, project_id, parent_id) do
    now = TimeHelpers.now()

    children =
      Repo.all(
        from entity in schema,
          where:
            entity.project_id == ^project_id and entity.parent_id == ^parent_id and
              is_nil(entity.deleted_at)
      )

    Enum.flat_map(children, fn child ->
      Repo.update_all(from(entity in schema, where: entity.id == ^child.id), set: [deleted_at: now])
      [child.id | soft_delete_children(schema, project_id, child.id)]
    end)
  end
end

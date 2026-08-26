defmodule Storyarn.Scenes.Editor.Commands.SoftDelete do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Repo

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

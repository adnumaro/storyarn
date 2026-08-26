defmodule Storyarn.Flows.ExitTargetScenes do
  @moduledoc """
  Consumer-owned scene lookup for Exit node targets.

  This read model intentionally maps the shared `scenes` table without using
  another bounded context or leaking its Ecto schema. Callers receive only the
  fields the Exit node picker consumes.
  """

  import Ecto.Query

  alias Storyarn.Flows.Editor.Data.SceneRecord
  alias Storyarn.Platform.Shared.SearchHelpers
  alias Storyarn.Repo

  @default_search_limit 20

  @type scene_option :: %{id: integer(), name: String.t() | nil}

  @doc """
  Searches active scenes in one project for the Exit node target picker.

  Empty and whitespace-only queries return the most recently updated scenes.
  Non-empty queries match name or shortcut and sort by name, preserving the
  picker behavior that predates this local read model.
  """
  @spec search(integer(), String.t(), keyword()) :: [scene_option()]
  def search(project_id, query, opts \\ []) when is_binary(query) do
    limit = Keyword.get(opts, :limit, @default_search_limit)
    offset = Keyword.get(opts, :offset, 0)
    query_str = String.trim(query)

    if query_str == "" do
      Repo.all(
        from(scene in SceneRecord,
          where: scene.project_id == ^project_id and is_nil(scene.deleted_at),
          order_by: [desc: scene.updated_at],
          limit: ^limit,
          offset: ^offset,
          select: %{id: scene.id, name: scene.name}
        ),
        log: false
      )
    else
      search_term = "%#{SearchHelpers.sanitize_like_query(query_str)}%"

      Repo.all(
        from(scene in SceneRecord,
          where: scene.project_id == ^project_id and is_nil(scene.deleted_at),
          where: ilike(scene.name, ^search_term) or ilike(scene.shortcut, ^search_term),
          order_by: [asc: scene.name],
          limit: ^limit,
          offset: ^offset,
          select: %{id: scene.id, name: scene.name}
        ),
        log: false
      )
    end
  end
end

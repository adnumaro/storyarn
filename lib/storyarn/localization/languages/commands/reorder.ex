defmodule Storyarn.Localization.Languages.Commands.Reorder do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Localization.Languages.Adapters.Positions.Postgres
  alias Storyarn.Localization.Languages.Commands.Locks
  alias Storyarn.Localization.ProjectLanguage
  alias Storyarn.Repo

  def run(project_id, language_ids) when is_list(language_ids) do
    Repo.transaction(fn ->
      Locks.lock_project!(project_id)

      active_ids =
        Repo.all(
          from(language in ProjectLanguage,
            where:
              language.project_id == ^project_id and
                is_nil(language.archived_at),
            order_by: [asc: language.id],
            lock: "FOR UPDATE",
            select: language.id
          )
        )

      if Enum.all?(language_ids, &is_integer/1) and
           length(language_ids) == length(Enum.uniq(language_ids)) and
           Enum.sort(language_ids) == active_ids do
        Postgres.set_positions(project_id, Enum.with_index(language_ids))
      else
        Repo.rollback(:invalid_language_order)
      end
    end)
  end
end

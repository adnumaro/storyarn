defmodule Storyarn.Localization.Languages.Commands.Locks do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Localization.Languages.Data.ProjectRecord
  alias Storyarn.Localization.ProjectLanguage
  alias Storyarn.Repo

  def lock_project!(project_id) do
    case Repo.one(
           from(project in ProjectRecord,
             where: project.id == ^project_id,
             lock: "FOR UPDATE"
           )
         ) do
      %ProjectRecord{deleted_at: nil} = project -> project
      %ProjectRecord{} -> Repo.rollback(:project_not_active)
      nil -> Repo.rollback(:project_not_found)
    end
  end

  def lock_language!(project_id, language_id) do
    Repo.one!(
      from(language in ProjectLanguage,
        where: language.project_id == ^project_id and language.id == ^language_id,
        lock: "FOR UPDATE"
      )
    )
  end
end

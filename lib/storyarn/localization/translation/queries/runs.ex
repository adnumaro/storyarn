defmodule Storyarn.Localization.Translation.Queries.Runs do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Localization.TranslationRun
  alias Storyarn.Repo

  def get(run_id), do: Repo.get(TranslationRun, run_id)

  def get_for_project(project_id, run_id) do
    Repo.one(from(run in TranslationRun, where: run.id == ^run_id and run.project_id == ^project_id))
  end

  def get_active(_project_id, nil), do: nil

  def get_active(project_id, target_locale) do
    Repo.one(
      from(run in TranslationRun,
        where:
          run.project_id == ^project_id and run.target_locale == ^target_locale and
            run.status in ["queued", "running"],
        order_by: [desc: run.id],
        limit: 1
      )
    )
  end

  def cancelled?(run_id) do
    Repo.exists?(from(run in TranslationRun, where: run.id == ^run_id and run.status == "cancelled"))
  end
end

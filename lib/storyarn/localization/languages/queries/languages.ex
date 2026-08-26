defmodule Storyarn.Localization.Languages.Queries.Languages do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Localization.Languages.Data.LocalizedTextRecord
  alias Storyarn.Localization.LocaleCode
  alias Storyarn.Localization.ProjectLanguage
  alias Storyarn.Repo

  def list(project_id) do
    Repo.all(
      from(language in ProjectLanguage,
        where: language.project_id == ^project_id and is_nil(language.archived_at),
        order_by: [asc: language.position, asc: language.name]
      )
    )
  end

  def list_for_backup(project_id) do
    Repo.all(
      from(language in ProjectLanguage,
        where: language.project_id == ^project_id,
        order_by: [asc: language.position, asc: language.name]
      )
    )
  end

  def get(project_id, language_id) do
    Repo.one(
      from(language in ProjectLanguage,
        where:
          language.project_id == ^project_id and language.id == ^language_id and
            is_nil(language.archived_at)
      )
    )
  end

  def get_by_locale(project_id, locale_code) do
    locale_code = LocaleCode.normalize(locale_code)

    Repo.one(
      from(language in ProjectLanguage,
        where:
          language.project_id == ^project_id and language.locale_code == ^locale_code and
            is_nil(language.archived_at)
      )
    )
  end

  def get_source(project_id) do
    Repo.one(
      from(language in ProjectLanguage,
        where:
          language.project_id == ^project_id and language.is_source == true and
            is_nil(language.archived_at)
      )
    )
  end

  def get_targets(project_id) do
    Repo.all(
      from(language in ProjectLanguage,
        where:
          language.project_id == ^project_id and language.is_source == false and
            is_nil(language.archived_at),
        order_by: [asc: language.position, asc: language.name]
      )
    )
  end

  def get_archived_by_locale(_project_id, nil), do: nil

  def get_archived_by_locale(project_id, locale_code) do
    locale_code = LocaleCode.normalize(locale_code)

    Repo.one(
      from(language in ProjectLanguage,
        where:
          language.project_id == ^project_id and language.locale_code == ^locale_code and
            not is_nil(language.archived_at),
        order_by: [desc: language.archived_at, desc: language.id],
        limit: 1
      )
    )
  end

  def next_position(project_id) do
    ProjectLanguage
    |> where([language], language.project_id == ^project_id)
    |> select([language], coalesce(max(language.position), -1))
    |> Repo.one!()
    |> Kernel.+(1)
  end

  def translations_exist?(project_id) do
    Repo.exists?(from(text in LocalizedTextRecord, where: text.project_id == ^project_id))
  end
end

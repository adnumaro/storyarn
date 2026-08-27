defmodule Storyarn.Projects.Persistence.ProjectLanguageRecord do
  @moduledoc """
  Writable Project content record for source-language configuration and exact
  reconstitution. It is not a passive consumer projection.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Storyarn.Projects.LocalizationLocaleCode
  alias Storyarn.Projects.Project

  schema "project_languages" do
    field :locale_code, :string
    field :name, :string
    field :is_source, :boolean, default: false
    field :position, :integer, default: 0
    field :archived_at, :utc_datetime

    belongs_to :project, Project

    timestamps(type: :utc_datetime)
  end

  def create_changeset(language, attrs) do
    language
    |> cast(attrs, [:locale_code, :name, :is_source, :position, :archived_at])
    |> update_change(:locale_code, &LocalizationLocaleCode.normalize/1)
    |> validate_required([:locale_code, :name])
    |> validate_length(:locale_code, min: 2, max: LocalizationLocaleCode.max_length())
    |> validate_format(:locale_code, LocalizationLocaleCode.format())
    |> validate_length(:name, min: 1, max: 100)
    |> unique_constraint([:project_id, :locale_code],
      name: :project_languages_project_id_locale_code_index
    )
    |> unique_constraint(:project_id,
      name: :project_languages_one_source,
      message: "already has a source language"
    )
    |> foreign_key_constraint(:project_id)
  end

  def update_changeset(language, attrs) do
    language
    |> cast(attrs, [:name, :is_source, :position, :archived_at])
    |> validate_length(:name, min: 1, max: 100)
    |> unique_constraint([:project_id, :locale_code],
      name: :project_languages_project_id_locale_code_index
    )
    |> unique_constraint(:project_id,
      name: :project_languages_one_source,
      message: "already has a source language"
    )
  end
end

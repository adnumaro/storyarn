defmodule Storyarn.Localization.ProjectLanguage do
  @moduledoc """
  Schema for project languages.

  Each project can have multiple languages configured for localization.
  One language is marked as the source language (`is_source: true`).

  Fields:
  - `locale_code` - BCP 47 code (e.g., "en", "es", "ja", "zh-CN")
  - `name` - Display name (e.g., "English", "Spanish")
  - `is_source` - Whether this is the source/original language
  - `position` - Sort order in the UI
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Storyarn.Projects.Project

  @type t :: %__MODULE__{
          id: integer() | nil,
          locale_code: String.t() | nil,
          name: String.t() | nil,
          is_source: boolean(),
          position: integer(),
          project_id: integer() | nil,
          project: Project.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "project_languages" do
    field :locale_code, :string
    field :name, :string
    field :is_source, :boolean, default: false
    field :position, :integer, default: 0

    belongs_to :project, Project

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a new project language.
  """
  def create_changeset(language, attrs) do
    language
    |> cast(attrs, [:locale_code, :name, :is_source, :position])
    |> validate_required([:locale_code, :name])
    |> validate_length(:locale_code, min: 2, max: 10)
    |> validate_length(:name, min: 1, max: 100)
    |> unique_constraint([:project_id, :locale_code])
    |> unique_constraint(:project_id,
      name: :project_languages_one_source,
      message: "already has a source language"
    )
    |> foreign_key_constraint(:project_id)
  end

  @doc """
  Changeset for updating a project language.
  """
  def update_changeset(language, attrs) do
    language
    |> cast(attrs, [:name, :is_source, :position])
    |> validate_length(:name, min: 1, max: 100)
    |> unique_constraint(:project_id,
      name: :project_languages_one_source,
      message: "already has a source language"
    )
  end
end

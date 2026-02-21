defmodule Storyarn.Localization.GlossaryEntry do
  @moduledoc """
  Schema for localization glossary entries.

  Stores per-language-pair term mappings for a project. Designed to match
  the DeepL glossary API structure (source term → target term for a pair).

  Fields:
  - `source_term` - The term in the source language (e.g., "Eldoria")
  - `source_locale` - The source language code (e.g., "en")
  - `target_term` - The translated term (e.g., "Eldoria" for proper nouns)
  - `target_locale` - The target language code (e.g., "es")
  - `context` - Usage notes for translators
  - `do_not_translate` - If true, term should be kept as-is (proper nouns)
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Storyarn.Projects.Project

  @type t :: %__MODULE__{
          id: integer() | nil,
          project_id: integer() | nil,
          project: Project.t() | Ecto.Association.NotLoaded.t() | nil,
          source_term: String.t() | nil,
          source_locale: String.t() | nil,
          target_term: String.t() | nil,
          target_locale: String.t() | nil,
          context: String.t() | nil,
          do_not_translate: boolean(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "localization_glossary_entries" do
    field :source_term, :string
    field :source_locale, :string
    field :target_term, :string
    field :target_locale, :string
    field :context, :string
    field :do_not_translate, :boolean, default: false

    belongs_to :project, Project

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a glossary entry.
  """
  def create_changeset(entry, attrs) do
    entry
    |> cast(attrs, [
      :source_term,
      :source_locale,
      :target_term,
      :target_locale,
      :context,
      :do_not_translate
    ])
    |> validate_required([:source_term, :source_locale, :target_locale])
    |> validate_length(:source_locale, min: 2, max: 10)
    |> validate_length(:target_locale, min: 2, max: 10)
    |> unique_constraint([:project_id, :source_term, :source_locale, :target_locale],
      name: :glossary_entries_unique
    )
    |> foreign_key_constraint(:project_id)
  end

  @doc """
  Changeset for updating a glossary entry.
  """
  def update_changeset(entry, attrs) do
    entry
    |> cast(attrs, [:target_term, :context, :do_not_translate])
  end
end

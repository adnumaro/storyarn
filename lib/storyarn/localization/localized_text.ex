defmodule Storyarn.Localization.LocalizedText do
  @moduledoc """
  Schema for localized texts.

  Stores translations for all localizable content in a project. Each row represents
  one translation of one field in one locale.

  The composite key `(source_type, source_id, source_field, locale_code)` uniquely
  identifies a translation. The `source_type` + `source_id` point to the origin entity,
  and `source_field` identifies which field within that entity.

  Source types: `"flow_node"`, `"block"`, `"sheet"`, `"flow"`, `"screenplay"`

  Status workflow: pending → draft → in_progress → review → final
  When source text changes on a `final` entry, status downgrades to `review`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Storyarn.Accounts.User
  alias Storyarn.Assets.Asset
  alias Storyarn.Projects.Project
  alias Storyarn.Sheets.Sheet

  @valid_statuses ~w(pending draft in_progress review final)
  @valid_vo_statuses ~w(none needed recorded approved)
  @valid_source_types ~w(flow_node block sheet flow screenplay)

  @type t :: %__MODULE__{
          id: integer() | nil,
          project_id: integer() | nil,
          project: Project.t() | Ecto.Association.NotLoaded.t() | nil,
          source_type: String.t() | nil,
          source_id: integer() | nil,
          source_field: String.t() | nil,
          source_text: String.t() | nil,
          source_text_hash: String.t() | nil,
          locale_code: String.t() | nil,
          translated_text: String.t() | nil,
          status: String.t(),
          vo_status: String.t(),
          vo_asset_id: integer() | nil,
          vo_asset: Asset.t() | Ecto.Association.NotLoaded.t() | nil,
          translator_notes: String.t() | nil,
          reviewer_notes: String.t() | nil,
          speaker_sheet_id: integer() | nil,
          speaker_sheet: Sheet.t() | Ecto.Association.NotLoaded.t() | nil,
          word_count: integer() | nil,
          machine_translated: boolean(),
          last_translated_at: DateTime.t() | nil,
          last_reviewed_at: DateTime.t() | nil,
          translated_by_id: integer() | nil,
          translated_by: User.t() | Ecto.Association.NotLoaded.t() | nil,
          reviewed_by_id: integer() | nil,
          reviewed_by: User.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "localized_texts" do
    field :source_type, :string
    field :source_id, :integer
    field :source_field, :string
    field :source_text, :string
    field :source_text_hash, :string
    field :locale_code, :string
    field :translated_text, :string
    field :status, :string, default: "pending"
    field :vo_status, :string, default: "none"
    field :translator_notes, :string
    field :reviewer_notes, :string
    field :word_count, :integer
    field :machine_translated, :boolean, default: false
    field :last_translated_at, :utc_datetime
    field :last_reviewed_at, :utc_datetime

    belongs_to :project, Project
    belongs_to :vo_asset, Asset
    belongs_to :speaker_sheet, Sheet
    belongs_to :translated_by, User
    belongs_to :reviewed_by, User

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a new localized text (typically via auto-extraction).
  """
  def create_changeset(text, attrs) do
    text
    |> cast(attrs, [
      :source_type,
      :source_id,
      :source_field,
      :source_text,
      :source_text_hash,
      :locale_code,
      :translated_text,
      :status,
      :vo_status,
      :speaker_sheet_id,
      :word_count,
      :machine_translated
    ])
    |> validate_required([:source_type, :source_id, :source_field, :locale_code])
    |> validate_inclusion(:source_type, @valid_source_types)
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_inclusion(:vo_status, @valid_vo_statuses)
    |> validate_length(:locale_code, min: 2, max: 10)
    |> unique_constraint([:source_type, :source_id, :source_field, :locale_code],
      name: :localized_texts_source_locale_unique
    )
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:vo_asset_id)
    |> foreign_key_constraint(:speaker_sheet_id)
  end

  @doc """
  Changeset for updating a translation (manual editing).
  """
  def update_changeset(text, attrs) do
    text
    |> cast(attrs, [
      :translated_text,
      :status,
      :vo_status,
      :vo_asset_id,
      :translator_notes,
      :reviewer_notes,
      :speaker_sheet_id,
      :word_count,
      :machine_translated,
      :last_translated_at,
      :last_reviewed_at,
      :translated_by_id,
      :reviewed_by_id
    ])
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_inclusion(:vo_status, @valid_vo_statuses)
    |> foreign_key_constraint(:vo_asset_id)
    |> foreign_key_constraint(:speaker_sheet_id)
    |> foreign_key_constraint(:translated_by_id)
    |> foreign_key_constraint(:reviewed_by_id)
  end

  @doc """
  Changeset for updating the source text (via auto-extraction).
  Only updates source_text, source_text_hash, word_count, and possibly status.
  """
  def source_update_changeset(text, attrs) do
    text
    |> cast(attrs, [:source_text, :source_text_hash, :word_count, :status, :speaker_sheet_id])
  end
end

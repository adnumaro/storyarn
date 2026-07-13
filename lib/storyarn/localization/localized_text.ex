defmodule Storyarn.Localization.LocalizedText do
  @moduledoc """
  Schema for localized texts.

  Stores translations for all localizable content in a project. Each row represents
  one translation of one field in one locale.

  The composite key `(source_type, source_id, source_field, locale_code)` uniquely
  identifies a translation. The `source_type` + `source_id` point to the origin entity,
  and `source_field` identifies which field within that entity.

  Source types: `"flow_node"`, `"block"`, and runtime speaker `"sheet"` names. The accepted fields and their
  runtime roles are defined by `Storyarn.Localization.SourceContract`.

  Status workflow: pending → draft → in_progress → review → final
  When source text changes on a `final` entry, status downgrades to `review`.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Ecto.Association.NotLoaded
  alias Storyarn.Accounts.User
  alias Storyarn.Assets.Asset
  alias Storyarn.Localization.HtmlHandler
  alias Storyarn.Localization.LocaleCode
  alias Storyarn.Localization.SourceContract
  alias Storyarn.Projects.Project
  alias Storyarn.Sheets.Sheet

  @valid_statuses ~w(pending draft in_progress review final)
  @valid_vo_statuses ~w(none needed recorded approved)
  @valid_source_types SourceContract.source_types()
  @valid_content_roles SourceContract.content_roles()

  @type t :: %__MODULE__{
          id: integer() | nil,
          project_id: integer() | nil,
          project: Project.t() | NotLoaded.t() | nil,
          source_type: String.t() | nil,
          source_id: integer() | nil,
          source_field: String.t() | nil,
          source_text: String.t() | nil,
          source_text_hash: String.t() | nil,
          translated_source_hash: String.t() | nil,
          locale_code: String.t() | nil,
          translated_text: String.t() | nil,
          status: String.t(),
          vo_status: String.t(),
          vo_asset_id: integer() | nil,
          vo_asset: Asset.t() | NotLoaded.t() | nil,
          translator_notes: String.t() | nil,
          reviewer_notes: String.t() | nil,
          speaker_sheet_id: integer() | nil,
          speaker_sheet: Sheet.t() | NotLoaded.t() | nil,
          word_count: integer() | nil,
          content_role: String.t(),
          vo_eligible: boolean(),
          machine_translated: boolean(),
          last_translated_at: DateTime.t() | nil,
          last_reviewed_at: DateTime.t() | nil,
          translated_by_id: integer() | nil,
          translated_by: User.t() | NotLoaded.t() | nil,
          reviewed_by_id: integer() | nil,
          reviewed_by: User.t() | NotLoaded.t() | nil,
          lock_version: integer(),
          archived_at: DateTime.t() | nil,
          archive_reason: String.t() | nil,
          localization_key: String.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "localized_texts" do
    field :source_type, :string
    field :source_id, :integer
    field :source_field, :string
    field :source_text, :string
    field :source_text_hash, :string
    field :translated_source_hash, :string
    field :locale_code, :string
    field :translated_text, :string
    field :status, :string, default: "pending"
    field :vo_status, :string, default: "none"
    field :translator_notes, :string
    field :reviewer_notes, :string
    field :word_count, :integer
    field :content_role, :string, default: "runtime_value"
    field :vo_eligible, :boolean, default: false
    field :machine_translated, :boolean, default: false
    field :last_translated_at, :utc_datetime
    field :last_reviewed_at, :utc_datetime
    field :lock_version, :integer, default: 1
    field :archived_at, :utc_datetime
    field :archive_reason, :string
    field :localization_key, :string, virtual: true

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
      :translated_source_hash,
      :locale_code,
      :translated_text,
      :status,
      :vo_status,
      :speaker_sheet_id,
      :word_count,
      :content_role,
      :vo_eligible,
      :machine_translated,
      :last_translated_at
    ])
    |> update_change(:locale_code, &LocaleCode.normalize/1)
    |> validate_required([:source_type, :source_id, :source_field, :locale_code])
    |> validate_inclusion(:source_type, @valid_source_types)
    |> validate_runtime_source_field()
    |> validate_inclusion(:content_role, @valid_content_roles)
    |> validate_runtime_source_metadata()
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_inclusion(:vo_status, @valid_vo_statuses)
    |> validate_vo_eligibility()
    |> validate_length(:locale_code, min: 2, max: LocaleCode.max_length())
    |> validate_format(:locale_code, LocaleCode.format())
    |> unique_constraint([:source_type, :source_id, :source_field, :locale_code],
      name: :localized_texts_source_locale_unique
    )
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:vo_asset_id)
    |> foreign_key_constraint(:speaker_sheet_id)
    |> validate_translation_present_when_final()
    |> validate_translation_is_current_when_final()
    |> validate_placeholders()
    |> check_constraint(:status, name: :localized_texts_final_requires_current_translation)
    |> check_constraint(:content_role, name: :localized_texts_source_metadata_runtime)
    |> check_constraint(:vo_status, name: :localized_texts_vo_requires_eligible_source)
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
      :reviewed_by_id,
      :translated_source_hash
    ])
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_inclusion(:vo_status, @valid_vo_statuses)
    |> validate_vo_eligibility()
    |> foreign_key_constraint(:vo_asset_id)
    |> foreign_key_constraint(:speaker_sheet_id)
    |> foreign_key_constraint(:translated_by_id)
    |> foreign_key_constraint(:reviewed_by_id)
    |> validate_translation_present_when_final()
    |> validate_translation_is_current_when_final()
    |> validate_placeholders()
    |> check_constraint(:status, name: :localized_texts_final_requires_current_translation)
    |> check_constraint(:vo_status, name: :localized_texts_vo_requires_eligible_source)
    |> optimistic_lock(:lock_version)
  end

  @doc """
  Changeset for updating the source text (via auto-extraction).
  Only updates source_text, source_text_hash, word_count, and possibly status.
  """
  def source_update_changeset(text, attrs) do
    text
    |> cast(attrs, [
      :source_text,
      :source_text_hash,
      :word_count,
      :status,
      :speaker_sheet_id,
      :content_role,
      :vo_eligible,
      :vo_status,
      :archived_at,
      :archive_reason
    ])
    |> validate_inclusion(:content_role, @valid_content_roles)
    |> validate_runtime_source_metadata()
    |> validate_vo_eligibility()
    |> check_constraint(:content_role, name: :localized_texts_source_metadata_runtime)
    |> check_constraint(:vo_status, name: :localized_texts_vo_requires_eligible_source)
    |> optimistic_lock(:lock_version)
  end

  @doc "Returns true when a non-empty translation belongs to an older source revision."
  @spec stale?(t()) :: boolean()
  def stale?(%__MODULE__{} = text) do
    present?(text.translated_text) and
      (is_nil(text.translated_source_hash) or is_nil(text.source_text_hash) or
         text.translated_source_hash != text.source_text_hash)
  end

  defp validate_translation_present_when_final(changeset) do
    if get_field(changeset, :status) == "final" and not present?(get_field(changeset, :translated_text)) do
      add_error(changeset, :translated_text, "can't be blank when status is final")
    else
      changeset
    end
  end

  defp validate_runtime_source_field(changeset) do
    source_type = get_field(changeset, :source_type)
    source_field = get_field(changeset, :source_field)

    if SourceContract.field?(source_type, source_field) do
      changeset
    else
      add_error(changeset, :source_field, "is not part of the runtime localization contract")
    end
  end

  defp validate_runtime_source_metadata(changeset) do
    metadata =
      SourceContract.field_metadata(
        get_field(changeset, :source_type),
        get_field(changeset, :source_field)
      )

    if metadata &&
         (get_field(changeset, :content_role) != metadata.content_role or
            get_field(changeset, :vo_eligible) != metadata.vo_eligible) do
      changeset
      |> add_error(:content_role, "does not match the runtime source field")
      |> add_error(:vo_eligible, "does not match the runtime source field")
    else
      changeset
    end
  end

  defp validate_vo_eligibility(changeset) do
    if get_field(changeset, :vo_eligible) == false do
      changeset
      |> maybe_add_ineligible_vo_error(:vo_status, get_field(changeset, :vo_status) != "none")
      |> maybe_add_ineligible_vo_error(:vo_asset_id, not is_nil(get_field(changeset, :vo_asset_id)))
    else
      changeset
    end
  end

  defp maybe_add_ineligible_vo_error(changeset, _field, false), do: changeset

  defp maybe_add_ineligible_vo_error(changeset, field, true) do
    add_error(changeset, field, "is only available for spoken dialogue and responses")
  end

  defp validate_translation_is_current_when_final(changeset) do
    source_hash = get_field(changeset, :source_text_hash)
    translated_hash = get_field(changeset, :translated_source_hash)

    if get_field(changeset, :status) == "final" and
         (is_nil(source_hash) or is_nil(translated_hash) or translated_hash != source_hash) do
      add_error(changeset, :status, "cannot be final until the current source text is translated")
    else
      changeset
    end
  end

  defp validate_placeholders(changeset) do
    source_text = get_field(changeset, :source_text)
    translated_text = get_field(changeset, :translated_text)

    if present?(translated_text) do
      case HtmlHandler.validate_placeholders(source_text, translated_text) do
        :ok ->
          changeset

        {:error, %{missing: missing, extra: extra}} ->
          add_error(changeset, :translated_text, placeholder_error(missing, extra))
      end
    else
      changeset
    end
  end

  defp placeholder_error(missing, extra) do
    [
      if(missing != [], do: "missing #{Enum.join(missing, ", ")}"),
      if(extra != [], do: "unexpected #{Enum.join(extra, ", ")}")
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("; ")
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_value), do: false
end

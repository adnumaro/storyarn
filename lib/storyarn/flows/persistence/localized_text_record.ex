defmodule Storyarn.Flows.Persistence.LocalizedTextRecord do
  @moduledoc false

  use Ecto.Schema

  schema "localized_texts" do
    field :project_id, :id
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
    field :vo_asset_id, :id
    field :translator_notes, :string
    field :reviewer_notes, :string
    field :speaker_sheet_id, :id
    field :word_count, :integer
    field :content_role, :string, default: "runtime_value"
    field :vo_eligible, :boolean, default: false
    field :machine_translated, :boolean, default: false
    field :last_translated_at, :utc_datetime
    field :last_reviewed_at, :utc_datetime
    field :translated_by_id, :id
    field :reviewed_by_id, :id
    field :lock_version, :integer, default: 1
    field :archived_at, :utc_datetime
    field :archive_reason, :string

    timestamps(type: :utc_datetime)
  end
end

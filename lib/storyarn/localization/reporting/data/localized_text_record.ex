defmodule Storyarn.Localization.Reporting.Data.LocalizedTextRecord do
  @moduledoc """
  Read-only Reporting projection over Localization-owned localized text rows.

  It contains only the columns required to aggregate progress and voice-over
  metrics. Persistence I/O belongs to `Reporting.Queries`.
  """

  use Ecto.Schema

  schema "localized_texts" do
    field :project_id, :id
    field :locale_code, :string
    field :status, :string
    field :translated_text, :string
    field :translated_source_hash, :string
    field :source_text_hash, :string
    field :speaker_sheet_id, :id
    field :word_count, :integer
    field :vo_eligible, :boolean
    field :vo_status, :string
    field :source_type, :string
    field :archived_at, :utc_datetime
  end
end

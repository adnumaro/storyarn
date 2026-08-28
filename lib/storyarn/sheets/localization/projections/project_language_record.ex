defmodule Storyarn.Sheets.Localization.Projections.ProjectLanguageRecord do
  @moduledoc """
  Sheets-local projection of active target locales for inventory extraction.

  It is read-only here: language configuration remains owned by Localization.
  """

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "project_languages" do
    field :project_id, :id
    field :locale_code, :string
    field :name, :string
    field :is_source, :boolean, default: false
    field :position, :integer, default: 0
    field :archived_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end
end

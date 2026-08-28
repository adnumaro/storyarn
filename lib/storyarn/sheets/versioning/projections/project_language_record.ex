defmodule Storyarn.Sheets.Versioning.Projections.ProjectLanguageRecord do
  @moduledoc "Versioning-owned consumer-local SQL projection used to capture and restore Sheet versions without importing another context's schema."

  use Ecto.Schema

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

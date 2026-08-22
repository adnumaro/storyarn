defmodule Storyarn.Sheets.Persistence.ProjectLanguageRecord do
  @moduledoc false

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

defmodule Storyarn.Localization.Texts.Data.LanguageRecord do
  @moduledoc """
  Read-only projection of a project language used to select Texts target locales.

  Language configuration remains owned by Localization.Languages.
  """
  use Ecto.Schema

  schema "project_languages" do
    field :locale_code, :string
    field :name, :string
    field :is_source, :boolean, default: false
    field :position, :integer, default: 0
    field :archived_at, :utc_datetime
    field :project_id, :id
    timestamps(type: :utc_datetime)
  end
end

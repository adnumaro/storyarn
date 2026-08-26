defmodule Storyarn.Localization.Reporting.Data.ProjectLanguageRecord do
  @moduledoc """
  Read-only Reporting projection over Localization-owned project languages.

  It deliberately omits changesets and associations; report queries own the
  persistence access while Languages owns ordinary writes.
  """

  use Ecto.Schema

  schema "project_languages" do
    field :project_id, :id
    field :locale_code, :string
    field :name, :string
    field :is_source, :boolean
    field :position, :integer
    field :archived_at, :utc_datetime
  end
end

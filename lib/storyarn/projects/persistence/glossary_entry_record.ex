defmodule Storyarn.Projects.Persistence.GlossaryEntryRecord do
  @moduledoc false

  use Ecto.Schema

  schema "localization_glossary_entries" do
    field :project_id, :id
    field :source_term, :string
    field :source_locale, :string
    field :target_term, :string
    field :target_locale, :string
    field :context, :string
    field :do_not_translate, :boolean, default: false

    timestamps(type: :utc_datetime)
  end
end

defmodule Storyarn.Ideation.Ideas.Idea do
  @moduledoc false
  use Ecto.Schema

  schema "ideation_ideas" do
    field :session_id, :id
    field :author_id, :id
    field :author_kind, Ecto.Enum, values: [:human, :ai], default: :human
    field :creation_key, Ecto.UUID
    field :revision, :integer, default: 1
    field :published_revision, :integer
    field :state, Ecto.Enum, values: [:active, :parked, :discarded], default: :active
    field :publication_consent, Ecto.Enum, values: [:author_only, :facilitator_assisted], default: :author_only
    field :configuration_version, :integer
    field :source_idea_id, :id
    field :source_revision, :integer
    timestamps(type: :utc_datetime_usec)
  end
end

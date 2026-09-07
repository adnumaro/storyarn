defmodule Storyarn.Ideation.Ideas.Idea do
  @moduledoc false
  use Ecto.Schema

  schema "ideation_ideas" do
    field :recovery_identity, Ecto.UUID, read_after_writes: true, redact: true
    field :session_id, :id
    field :author_id, :id
    field :author_kind, Ecto.Enum, values: [:human, :ai], default: :human
    field :canvas, :map, default: %{}
    field :deleted_at, :utc_datetime_usec
    field :creation_key, Ecto.UUID
    field :revision, :integer, default: 1
    field :published_revision, :integer
    field :state, Ecto.Enum, values: [:active, :parked, :discarded], default: :active
    field :publication_consent, Ecto.Enum, values: [:author_only, :facilitator_assisted], default: :author_only
    field :configuration_version, :integer
    # Immutable request identity, distinct from the remapped provenance link.
    field :creation_source_id, :integer
    field :source_idea_id, :id
    field :source_revision, :integer
    timestamps(type: :utc_datetime_usec)
  end
end

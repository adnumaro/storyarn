defmodule Storyarn.Ideation.Ideas.Publication do
  @moduledoc false
  use Ecto.Schema

  schema "ideation_idea_publications" do
    field :recovery_identity, Ecto.UUID, read_after_writes: true, redact: true
    field :idea_id, :id
    field :revision, :integer
    field :operation_id, :id
    field :actor_id, :id
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end

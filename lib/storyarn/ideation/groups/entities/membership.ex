defmodule Storyarn.Ideation.Groups.Membership do
  @moduledoc false
  use Ecto.Schema

  schema "ideation_group_memberships" do
    field :recovery_identity, Ecto.UUID, read_after_writes: true, redact: true
    field :session_id, :id
    field :group_id, :id
    field :idea_id, :id
    field :source_revision, :integer
    field :actor_id, :id
    field :removed_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end

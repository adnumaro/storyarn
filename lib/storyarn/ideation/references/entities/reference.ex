defmodule Storyarn.Ideation.References.Reference do
  @moduledoc false
  use Ecto.Schema

  schema "ideation_references" do
    field :recovery_identity, Ecto.UUID, read_after_writes: true, redact: true
    field :session_id, :id
    field :idea_id, :id
    field :created_by_id, :id
    field :target_type, :string
    field :target_id, :integer
    field :target_identity, :string
    field :relation, :string
    field :version, :integer, default: 1
    field :context, :map, redact: true
    field :deleted_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end
end

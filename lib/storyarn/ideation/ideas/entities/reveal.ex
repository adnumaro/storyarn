defmodule Storyarn.Ideation.Ideas.Reveal do
  @moduledoc false
  use Ecto.Schema

  schema "ideation_reveal_operations" do
    field :recovery_identity, Ecto.UUID, read_after_writes: true, redact: true
    field :session_id, :id
    field :actor_id, :id
    field :request_key, Ecto.UUID
    field :selection, :map
    field :manifest, {:array, :map}, default: []
    field :status, Ecto.Enum, values: [:prepared, :completed], default: :prepared
    field :completed_at, :utc_datetime
    timestamps(type: :utc_datetime_usec)
  end
end

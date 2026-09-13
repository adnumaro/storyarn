defmodule Storyarn.Ideation.Decisions.Decision do
  @moduledoc false
  use Ecto.Schema

  schema "ideation_decisions" do
    field :recovery_identity, Ecto.UUID, read_after_writes: true, redact: true
    field :session_id, :id
    field :author_id, :id
    field :version, :integer, default: 1
    field :status, Ecto.Enum, values: [:proposed, :accepted], default: :proposed
    field :accepted_version, :integer
    timestamps(type: :utc_datetime_usec)
  end
end

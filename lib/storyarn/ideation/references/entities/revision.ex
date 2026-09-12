defmodule Storyarn.Ideation.References.Revision do
  @moduledoc false
  use Ecto.Schema

  schema "ideation_reference_revisions" do
    field :recovery_identity, Ecto.UUID, read_after_writes: true, redact: true
    field :session_id, :id
    field :reference_id, :id
    field :actor_id, :id
    field :number, :integer
    field :operation, :string
    field :request_key, Ecto.UUID
    field :fingerprint, :binary, redact: true
    field :context, :map, redact: true
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end

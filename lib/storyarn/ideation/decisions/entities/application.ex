defmodule Storyarn.Ideation.Decisions.Application do
  @moduledoc false
  use Ecto.Schema

  alias Storyarn.Platform.Shared.EncryptedBinary

  # A person's statement about one target of one agreement. Never a verification.
  schema "ideation_decision_applications" do
    field :recovery_identity, Ecto.UUID, read_after_writes: true, redact: true
    field :session_id, :id
    field :decision_id, :id
    field :agreement, :integer
    field :target_key, Ecto.UUID
    field :state, :string
    field :note, EncryptedBinary, redact: true
    field :actor_id, :id
    field :request_key, Ecto.UUID
    field :fingerprint, :binary, redact: true
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end

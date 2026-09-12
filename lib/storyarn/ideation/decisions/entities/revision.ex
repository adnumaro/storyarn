defmodule Storyarn.Ideation.Decisions.Revision do
  @moduledoc false
  use Ecto.Schema

  alias Storyarn.Platform.Shared.EncryptedBinary

  schema "ideation_decision_revisions" do
    field :recovery_identity, Ecto.UUID, read_after_writes: true, redact: true
    field :session_id, :id
    field :decision_id, :id
    field :number, :integer
    field :operation, :string
    field :actor_id, :id
    field :responsible_id, :id
    field :title, EncryptedBinary, redact: true
    field :conclusion, EncryptedBinary, redact: true
    field :reason, EncryptedBinary, redact: true
    field :sources, :map, default: %{}
    field :source_context, EncryptedBinary, redact: true
    field :request_key, Ecto.UUID
    field :fingerprint, :binary, redact: true
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end

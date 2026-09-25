defmodule Storyarn.Ideation.Decisions.TaskLink do
  @moduledoc false
  use Ecto.Schema

  alias Storyarn.Platform.Shared.EncryptedBinary

  # One change to a link from a decision to an external task. The latest row
  # per link key is the link; an unlinked key keeps its history.
  schema "ideation_decision_task_links" do
    field :recovery_identity, Ecto.UUID, read_after_writes: true, redact: true
    field :session_id, :id
    field :decision_id, :id
    field :link_key, Ecto.UUID
    field :operation, :string
    field :kind, :string
    field :url, EncryptedBinary, redact: true
    field :title, EncryptedBinary, redact: true
    field :actor_id, :id
    field :request_key, Ecto.UUID
    field :fingerprint, :binary, redact: true
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end

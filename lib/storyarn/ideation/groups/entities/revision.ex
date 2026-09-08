defmodule Storyarn.Ideation.Groups.Revision do
  @moduledoc false
  use Ecto.Schema

  alias Storyarn.Platform.Shared.EncryptedBinary

  schema "ideation_group_revisions" do
    field :recovery_identity, Ecto.UUID, read_after_writes: true, redact: true
    field :session_id, :id
    field :group_id, :id
    field :actor_id, :id
    field :number, :integer
    field :operation, :string
    field :request_key, Ecto.UUID
    field :fingerprint, :binary, redact: true
    field :title, EncryptedBinary, redact: true
    field :synthesis, EncryptedBinary, redact: true
    field :canvas, :map, default: %{}
    field :idea_ids, {:array, :id}, default: []
    field :sources, :map, default: %{}
    field :deleted_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end

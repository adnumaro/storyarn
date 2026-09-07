defmodule Storyarn.Ideation.Ideas.Edit do
  @moduledoc false
  use Ecto.Schema

  alias Storyarn.Platform.Shared.EncryptedBinary

  schema "ideation_idea_edits" do
    field :idea_id, :id
    field :actor_id, :id
    field :request_key, Ecto.UUID
    field :fingerprint, :binary, redact: true
    field :outcome, Ecto.Enum, values: [:saved, :conflict]
    field :base_revision, :integer
    field :result_revision, :integer
    field :title, EncryptedBinary, redact: true
    field :body, EncryptedBinary, redact: true
    field :state, Ecto.Enum, values: [:active, :parked, :discarded]
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end

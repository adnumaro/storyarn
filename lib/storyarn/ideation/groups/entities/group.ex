defmodule Storyarn.Ideation.Groups.Group do
  @moduledoc false
  use Ecto.Schema

  alias Storyarn.Platform.Shared.EncryptedBinary

  schema "ideation_groups" do
    field :recovery_identity, Ecto.UUID, read_after_writes: true, redact: true
    field :session_id, :id
    field :author_id, :id
    field :title, EncryptedBinary, redact: true
    field :synthesis, EncryptedBinary, redact: true
    field :version, :integer, default: 1
    field :canvas, :map, default: %{}
    field :deleted_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end
end

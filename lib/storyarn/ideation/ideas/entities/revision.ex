defmodule Storyarn.Ideation.Ideas.Revision do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  alias Storyarn.Ideation.Ideas.Rules.Content
  alias Storyarn.Platform.Shared.EncryptedBinary

  schema "ideation_idea_revisions" do
    field :recovery_identity, Ecto.UUID, read_after_writes: true, redact: true
    field :idea_id, :id
    field :number, :integer
    field :actor_id, :id
    field :title, EncryptedBinary, redact: true
    field :body, EncryptedBinary, redact: true
    field :state, Ecto.Enum, values: [:active, :parked, :discarded], default: :active
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(revision, attrs) do
    revision
    |> cast(attrs, [:title, :body, :state])
    |> Content.validate_title()
    |> validate_length(:title, max: 160)
    |> Content.validate_body()
    |> validate_required([:body, :state])
  end
end

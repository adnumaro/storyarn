defmodule Storyarn.Ideation.Sessions.Session do
  @moduledoc "Session metadata and embedded collaboration settings."
  use Ecto.Schema

  import Ecto.Changeset

  alias Storyarn.Ideation.Sessions.Configuration

  # `defaults_to_struct` bakes `%Configuration{}` into this module at compile
  # time through a call the compiler cannot see, so an incremental build kept
  # the old struct after the embed changed. Building it here makes the
  # dependency explicit: this module recompiles with its configuration.
  @default_configuration %Configuration{}

  schema "ideation_sessions" do
    field :recovery_identity, Ecto.UUID, read_after_writes: true, redact: true
    field :project_id, :id
    field :created_by_id, :id
    field :facilitator_id, :id
    field :decision_owner_id, :id
    field :title, :string
    field :objective, :string
    field :context, :string
    field :status, Ecto.Enum, values: [:open, :archived], default: :open
    field :deleted_at, :utc_datetime_usec
    field :archived_at, :utc_datetime
    field :revision, :integer, default: 1
    field :configuration_version, :integer, default: 1
    field :contributions_open, :boolean, default: true
    embeds_one :configuration, Configuration, on_replace: :update, defaults_to_struct: true

    timestamps(type: :utc_datetime_usec)
  end

  def default_configuration, do: @default_configuration

  def changeset(session, attrs) do
    session
    |> cast(attrs, [:title, :objective, :context])
    |> update_change(:title, fn
      title when is_binary(title) -> String.trim(title)
      other -> other
    end)
    |> validate_required([:title])
    |> validate_length(:title, max: 160)
    |> validate_length(:objective, max: 4000)
    |> validate_length(:context, max: 12_000)
    |> cast_embed(:configuration, required: true, with: &Configuration.changeset/2)
  end
end

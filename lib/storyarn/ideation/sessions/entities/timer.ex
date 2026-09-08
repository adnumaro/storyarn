defmodule Storyarn.Ideation.Sessions.Timer do
  @moduledoc "Session-owned countdown with a durable deadline and fenced expiration effects."
  use Ecto.Schema

  schema "ideation_timers" do
    field :recovery_identity, Ecto.UUID, read_after_writes: true, redact: true
    field :session_id, :id
    field :actor_id, :id
    field :version, :integer, default: 1
    field :status, Ecto.Enum, values: [:running, :paused, :elapsed, :cancelled]
    field :deadline_at, :utc_datetime_usec
    field :remaining_seconds, :integer
    field :duration_seconds, :integer
    field :started_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec
    field :reveal_on_expiry, :boolean, default: false
    field :close_contributions_on_expiry, :boolean, default: false
    field :configuration_version, :integer

    field :expiry_outcome, Ecto.Enum,
      values: [:completed, :skipped_authorization, :skipped_configuration, :skipped_session]

    timestamps(type: :utc_datetime_usec)
  end
end

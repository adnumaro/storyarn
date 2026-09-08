defmodule Storyarn.Ideation.Sessions.Revision do
  @moduledoc "Session-owned revision record, persisted atomically by the session mutation workflow."
  use Ecto.Schema

  schema "ideation_session_revisions" do
    field :recovery_identity, Ecto.UUID, read_after_writes: true, redact: true
    field :session_id, :id
    field :actor_id, :id
    field :number, :integer

    field :action, Ecto.Enum,
      values: [
        :created,
        :updated,
        :responsibilities_assigned,
        :archived,
        :reopened,
        :recovered,
        :round_created,
        :round_updated,
        :round_cancelled,
        :round_started,
        :round_closed,
        :timer_started,
        :timer_paused,
        :timer_resumed,
        :timer_extended,
        :timer_cancelled,
        :timer_elapsed,
        :contributions_opened,
        :contributions_closed
      ]

    field :snapshot, :map

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end

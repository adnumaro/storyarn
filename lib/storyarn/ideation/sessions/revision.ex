defmodule Storyarn.Ideation.Sessions.Revision do
  @moduledoc false
  use Ecto.Schema

  schema "ideation_session_revisions" do
    field :session_id, :id
    field :actor_id, :id
    field :number, :integer
    field :action, Ecto.Enum, values: [:created, :updated, :responsibilities_assigned, :archived, :reopened]
    field :snapshot, :map

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end

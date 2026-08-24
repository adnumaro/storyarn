defmodule Storyarn.Billing.Persistence.ProjectInvitationRecord do
  @moduledoc false

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "project_invitations" do
    field :email, :string
    field :project_id, :id
    field :accepted_at, :utc_datetime
    field :expires_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end
end

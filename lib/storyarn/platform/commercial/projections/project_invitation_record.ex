defmodule Storyarn.Platform.Billing.Persistence.ProjectInvitationRecord do
  @moduledoc "Consumer-owned read-only SQL projection for this Platform capability."

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

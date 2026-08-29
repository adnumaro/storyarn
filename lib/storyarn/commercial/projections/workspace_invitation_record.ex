defmodule Storyarn.Commercial.Billing.Persistence.WorkspaceInvitationRecord do
  @moduledoc "Consumer-owned read-only SQL projection for this Commercial capability."

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "workspace_invitations" do
    field :email, :string
    field :role, :string
    field :expires_at, :utc_datetime
    field :accepted_at, :utc_datetime
    field :workspace_id, :id

    timestamps(type: :utc_datetime)
  end
end

defmodule Storyarn.Commercial.Billing.Persistence.WorkspaceMembershipRecord do
  @moduledoc "Consumer-owned read-only SQL projection for this Commercial capability."

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "workspace_memberships" do
    field :role, :string
    field :workspace_id, :id

    belongs_to :user, Storyarn.Commercial.Billing.Persistence.UserRecord

    timestamps(type: :utc_datetime)
  end
end

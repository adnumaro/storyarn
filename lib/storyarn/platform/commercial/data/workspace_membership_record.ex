defmodule Storyarn.Platform.Billing.Persistence.WorkspaceMembershipRecord do
  @moduledoc false

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "workspace_memberships" do
    field :role, :string
    field :workspace_id, :id

    belongs_to :user, Storyarn.Platform.Billing.Persistence.UserRecord

    timestamps(type: :utc_datetime)
  end
end

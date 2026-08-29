defmodule Storyarn.Commercial.Billing.Persistence.ProjectMembershipRecord do
  @moduledoc "Consumer-owned read-only SQL projection for this Commercial capability."

  use Ecto.Schema

  alias Storyarn.Commercial.Billing.Persistence.UserRecord

  @type t :: %__MODULE__{}

  schema "project_memberships" do
    field :role, :string
    field :project_id, :id

    belongs_to :user, UserRecord

    timestamps(type: :utc_datetime)
  end
end

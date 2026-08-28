defmodule Storyarn.Platform.Notifications.Projections.ProjectMembershipRecord do
  @moduledoc """
  Notification-owned projection of direct project access.

  Only the fields required to resolve recipients and effective access are
  mapped from the shared `project_memberships` table.
  """

  use Ecto.Schema

  alias Storyarn.Platform.Notifications.Projections.UserRecord

  @type t :: %__MODULE__{}

  schema "project_memberships" do
    field :role, :string
    field :project_id, :id

    belongs_to :user, UserRecord

    timestamps(type: :utc_datetime)
  end
end

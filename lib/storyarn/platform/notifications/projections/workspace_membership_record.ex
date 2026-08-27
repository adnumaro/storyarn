defmodule Storyarn.Platform.Notifications.Projections.WorkspaceMembershipRecord do
  @moduledoc """
  Notification-owned projection of workspace-inherited project access.

  It is intentionally local to notification delivery even though the SQL table
  is shared with Workspaces during this migration phase.
  """

  use Ecto.Schema

  alias Storyarn.Platform.Notifications.Projections.UserRecord

  @type t :: %__MODULE__{}

  schema "workspace_memberships" do
    field :role, :string
    field :workspace_id, :id

    belongs_to :user, UserRecord

    timestamps(type: :utc_datetime)
  end
end

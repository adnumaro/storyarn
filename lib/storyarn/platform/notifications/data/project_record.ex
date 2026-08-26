defmodule Storyarn.Platform.Notifications.Data.ProjectRecord do
  @moduledoc """
  Notification-owned projection of project visibility and workspace identity.

  It deliberately duplicates the shared `projects` mapping needed by delivery
  and inbox reads instead of importing a Billing or Projects model.
  """

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "projects" do
    field :workspace_id, :id
    field :owner_id, :id
    field :deleted_at, :utc_datetime
    field :deleted_by_id, :id

    timestamps(type: :utc_datetime)
  end
end

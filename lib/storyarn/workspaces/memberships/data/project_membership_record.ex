defmodule Storyarn.Workspaces.Memberships.Data.ProjectMembershipRecord do
  @moduledoc """
  Consumer-local SQL projection of project-membership access facts.

  Projects owns project membership behavior and writes. Memberships reads this
  minimal record when deriving a user's access to a Workspace.
  """

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "project_memberships" do
    field :role, :string
    field :project_id, :id
    field :user_id, :id

    timestamps(type: :utc_datetime)
  end
end

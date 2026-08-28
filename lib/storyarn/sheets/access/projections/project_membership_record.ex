defmodule Storyarn.Sheets.Access.Projections.ProjectMembershipRecord do
  @moduledoc "Access-owned projection of a user's direct project membership."

  use Ecto.Schema

  schema "project_memberships" do
    field :project_id, :id
    field :user_id, :id
    field :role, :string

    timestamps(type: :utc_datetime)
  end
end

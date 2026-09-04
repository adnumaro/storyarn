defmodule Storyarn.Projects.Comments.Projections.ProjectMembershipRecord do
  @moduledoc false
  use Ecto.Schema

  schema "project_memberships" do
    field :project_id, :integer
    field :user_id, :integer
    field :role, :string
  end
end

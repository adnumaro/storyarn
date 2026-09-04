defmodule Storyarn.Projects.Comments.Projections.WorkspaceMembershipRecord do
  @moduledoc false
  use Ecto.Schema

  schema "workspace_memberships" do
    field :workspace_id, :integer
    field :user_id, :integer
    field :role, :string
  end
end

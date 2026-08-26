defmodule Storyarn.Scenes.Access.Data.ProjectMembershipRecord do
  @moduledoc "Access-owned consumer-local SQL projection used to authorize Scene project reads without importing another context's schema."

  use Ecto.Schema

  schema "project_memberships" do
    field :project_id, :id
    field :user_id, :id
    field :role, :string

    timestamps(type: :utc_datetime)
  end
end

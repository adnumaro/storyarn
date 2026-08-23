defmodule Storyarn.Sheets.Persistence.ProjectMembershipRecord do
  @moduledoc false

  use Ecto.Schema

  schema "project_memberships" do
    field :project_id, :id
    field :user_id, :id
    field :role, :string

    timestamps(type: :utc_datetime)
  end
end

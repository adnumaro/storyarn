defmodule Storyarn.AI.Persistence.ProjectMembershipRecord do
  @moduledoc false

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "project_memberships" do
    field :role, :string
    field :project_id, :id
    field :user_id, :id

    timestamps(type: :utc_datetime)
  end
end

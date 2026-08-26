defmodule Storyarn.AI.Governance.Data.ProjectMembershipRecord do
  @moduledoc "Governance-owned projection of project membership used only for AI authorization."

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "project_memberships" do
    field :role, :string
    field :project_id, :id
    field :user_id, :id

    timestamps(type: :utc_datetime)
  end
end

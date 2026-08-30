defmodule Storyarn.Flows.References.Projections.ProjectMembershipRecord do
  @moduledoc "Flow-reference-owned projection used to validate Project ownership before maintenance writes."

  use Ecto.Schema

  @type t :: %__MODULE__{
          id: integer() | nil,
          project_id: integer() | nil,
          user_id: integer() | nil,
          role: String.t() | nil
        }

  schema "project_memberships" do
    field :project_id, :id
    field :user_id, :id
    field :role, :string

    timestamps(type: :utc_datetime)
  end
end

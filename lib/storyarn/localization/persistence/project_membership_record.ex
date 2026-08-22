defmodule Storyarn.Localization.Persistence.ProjectMembershipRecord do
  @moduledoc false

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

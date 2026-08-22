defmodule Storyarn.Localization.Persistence.WorkspaceMembershipRecord do
  @moduledoc false

  use Ecto.Schema

  @type t :: %__MODULE__{
          id: integer() | nil,
          workspace_id: integer() | nil,
          user_id: integer() | nil,
          role: String.t() | nil
        }

  schema "workspace_memberships" do
    field :workspace_id, :id
    field :user_id, :id
    field :role, :string

    timestamps(type: :utc_datetime)
  end
end

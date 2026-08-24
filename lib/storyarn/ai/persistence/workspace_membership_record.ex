defmodule Storyarn.AI.Persistence.WorkspaceMembershipRecord do
  @moduledoc false

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "workspace_memberships" do
    field :role, :string
    field :workspace_id, :id
    field :user_id, :id

    timestamps(type: :utc_datetime)
  end
end

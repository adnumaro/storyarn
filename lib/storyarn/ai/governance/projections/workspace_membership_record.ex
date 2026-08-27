defmodule Storyarn.AI.Governance.Projections.WorkspaceMembershipRecord do
  @moduledoc "Governance-owned projection of workspace membership used only for AI authorization."

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "workspace_memberships" do
    field :role, :string
    field :workspace_id, :id
    field :user_id, :id

    timestamps(type: :utc_datetime)
  end
end

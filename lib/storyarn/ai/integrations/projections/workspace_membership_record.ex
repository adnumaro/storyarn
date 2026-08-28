defmodule Storyarn.AI.Integrations.Projections.WorkspaceMembershipRecord do
  @moduledoc """
  Read-only Integrations projection of workspace membership eligibility.

  It carries only the role and foreign keys needed to prove that a personal
  assignment still belongs to a current workspace member.
  """

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "workspace_memberships" do
    field :role, :string
    field :workspace_id, :id
    field :user_id, :id

    timestamps(type: :utc_datetime)
  end
end

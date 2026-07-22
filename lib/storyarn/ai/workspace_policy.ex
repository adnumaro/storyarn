defmodule Storyarn.AI.WorkspacePolicy do
  @moduledoc "Versioned AI egress policy for one workspace."
  use Ecto.Schema

  import Ecto.Changeset

  alias Storyarn.Accounts.User
  alias Storyarn.Workspaces.Workspace

  @initial_lanes ~w(managed)

  schema "ai_workspace_policies" do
    field :allowed_lanes, {:array, :string}, default: []
    field :version, :integer, default: 1

    belongs_to :workspace, Workspace
    belongs_to :updated_by, User

    timestamps(type: :utc_datetime)
  end

  def changeset(policy, attrs) do
    policy
    |> cast(attrs, [:allowed_lanes, :version])
    |> put_change(:updated_by_id, Map.get(attrs, :updated_by_id))
    |> validate_required([:allowed_lanes, :version])
    |> validate_number(:version, greater_than: 0)
    |> validate_subset(:allowed_lanes, @initial_lanes)
    |> unique_constraint(:workspace_id)
    |> foreign_key_constraint(:workspace_id)
    |> foreign_key_constraint(:updated_by_id)
  end

  def initial_lanes, do: @initial_lanes
end

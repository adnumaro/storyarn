defmodule Storyarn.AI.IntegrationWorkspaceAssignment do
  @moduledoc "Actor-owned connection assignment to one workspace."

  use Ecto.Schema

  import Ecto.Changeset

  alias Storyarn.Accounts.User
  alias Storyarn.AI.Integration
  alias Storyarn.Workspaces.Workspace

  @type t :: %__MODULE__{}

  schema "ai_integration_workspace_assignments" do
    field :provider, :string
    field :assigned_at, :utc_datetime
    field :revoked_at, :utc_datetime

    belongs_to :user, User
    belongs_to :workspace, Workspace
    belongs_to :integration, Integration

    timestamps(type: :utc_datetime)
  end

  @doc false
  def assign_changeset(%__MODULE__{} = assignment, assigned_at) do
    assignment
    |> change(assigned_at: assigned_at)
    |> validate_required([:user_id, :workspace_id, :integration_id, :provider, :assigned_at])
    |> validate_length(:provider, min: 1, max: 100)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:workspace_id)
    |> foreign_key_constraint(:integration_id)
    |> unique_constraint([:integration_id, :workspace_id],
      name: :ai_assignments_active_integration_workspace_index
    )
    |> unique_constraint([:user_id, :workspace_id, :provider],
      name: :ai_assignments_active_provider_workspace_index
    )
  end

  @doc false
  def revoke_changeset(%__MODULE__{} = assignment, revoked_at) do
    assignment
    |> change(revoked_at: revoked_at)
    |> validate_required([:revoked_at])
  end
end

defmodule Storyarn.Workspaces.Memberships.Commands.CreateMembership do
  @moduledoc false

  alias Storyarn.Repo
  alias Storyarn.Workspaces.Memberships.Rules.OwnerProtection
  alias Storyarn.Workspaces.WorkspaceMembership

  @spec create(integer(), integer(), String.t()) ::
          {:ok, WorkspaceMembership.t()}
          | {:error, Ecto.Changeset.t() | :cannot_assign_owner_role}
  def create(workspace_id, user_id, role) do
    with :ok <- OwnerProtection.allow_role_assignment(role) do
      %WorkspaceMembership{}
      |> WorkspaceMembership.changeset(%{
        workspace_id: workspace_id,
        user_id: user_id,
        role: role
      })
      |> Repo.insert()
    end
  end
end

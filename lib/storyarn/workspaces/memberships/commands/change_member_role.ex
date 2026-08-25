defmodule Storyarn.Workspaces.Memberships.Commands.ChangeMemberRole do
  @moduledoc false

  alias Storyarn.Repo
  alias Storyarn.Workspaces.Memberships.Rules.OwnerProtection
  alias Storyarn.Workspaces.WorkspaceMembership

  @spec change(WorkspaceMembership.t(), String.t()) ::
          {:ok, WorkspaceMembership.t()}
          | {:error, Ecto.Changeset.t() | :cannot_change_owner_role}
  def change(membership, role) do
    with :ok <- OwnerProtection.allow_role_change(membership) do
      membership
      |> WorkspaceMembership.changeset(%{role: role})
      |> Repo.update()
    end
  end
end

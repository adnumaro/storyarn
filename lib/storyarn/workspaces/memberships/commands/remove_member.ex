defmodule Storyarn.Workspaces.Memberships.Commands.RemoveMember do
  @moduledoc false

  alias Storyarn.Repo
  alias Storyarn.Workspaces.Memberships.Rules.OwnerProtection
  alias Storyarn.Workspaces.WorkspaceMembership

  @spec remove(WorkspaceMembership.t()) ::
          {:ok, WorkspaceMembership.t()}
          | {:error, Ecto.Changeset.t() | :cannot_remove_owner}
  def remove(membership) do
    with :ok <- OwnerProtection.allow_removal(membership) do
      Repo.delete(membership)
    end
  end
end

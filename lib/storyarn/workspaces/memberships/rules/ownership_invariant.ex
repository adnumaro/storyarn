defmodule Storyarn.Workspaces.Memberships.Rules.OwnershipInvariant do
  @moduledoc false

  alias Storyarn.Workspaces.Workspace
  alias Storyarn.Workspaces.WorkspaceMembership

  @spec owner(Workspace.t(), [WorkspaceMembership.t()]) ::
          {:ok, WorkspaceMembership.t()} | {:error, :ownership_invariant_violation}
  def owner(%Workspace{owner_id: owner_id}, memberships) when is_list(memberships) do
    case Enum.filter(memberships, &(&1.role == "owner")) do
      [%WorkspaceMembership{user_id: ^owner_id} = owner_membership] ->
        {:ok, owner_membership}

      _missing_or_ambiguous_owner ->
        {:error, :ownership_invariant_violation}
    end
  end
end

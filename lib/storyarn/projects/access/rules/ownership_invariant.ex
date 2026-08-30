defmodule Storyarn.Projects.Access.Rules.OwnershipInvariant do
  @moduledoc false

  alias Storyarn.Projects.Project
  alias Storyarn.Projects.ProjectMembership

  @spec owner(Project.t(), [ProjectMembership.t()]) ::
          {:ok, ProjectMembership.t()} | {:error, :ownership_invariant_violation}
  def owner(%Project{owner_id: owner_id}, memberships) when is_list(memberships) do
    case Enum.filter(memberships, &(&1.role == "owner")) do
      [%ProjectMembership{user_id: ^owner_id} = owner_membership] ->
        {:ok, owner_membership}

      _missing_or_ambiguous_owner ->
        {:error, :ownership_invariant_violation}
    end
  end
end

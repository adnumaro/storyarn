defmodule Storyarn.AI.Integrations.Commands.WorkspaceAccessLocks do
  @moduledoc """
  Root lock protocol for workspace-scoped Integrations mutations.

  Mutations that can later lock an integration, assignment, consent or
  preference must enter through this protocol first. The global order is:

      Workspace -> WorkspaceMembership -> WorkspacePolicy ->
        Integration -> Assignment -> Consent/Preference

  The policy step is deliberately left to the caller because revocation-style
  mutations do not consult policy. No caller may acquire an upstream lock after
  taking one of the downstream Integrations locks.
  """

  import Ecto.Query

  alias Storyarn.AI.Integrations.Projections.WorkspaceMembershipRecord, as: WorkspaceMembership
  alias Storyarn.AI.Integrations.Projections.WorkspaceRecord, as: Workspace
  alias Storyarn.Repo

  @max_pg_bigint 9_223_372_036_854_775_807

  defguardp valid_id(id)
            when is_integer(id) and id > 0 and id <= @max_pg_bigint

  @type scope :: %{
          required(:user) => %{required(:id) => integer(), optional(atom()) => term()},
          optional(atom()) => term()
        }

  @spec lock(scope(), pos_integer()) ::
          {:ok, Workspace.t(), WorkspaceMembership.t()} | {:error, :workspace_unavailable}
  def lock(%{user: %{id: user_id}}, workspace_id) when valid_id(user_id) and valid_id(workspace_id) do
    workspace =
      Repo.one(
        from(workspace in Workspace,
          where: workspace.id == ^workspace_id,
          lock: "FOR SHARE"
        )
      )

    membership = lock_membership(workspace, user_id)

    case {workspace, membership} do
      {%Workspace{} = workspace, %WorkspaceMembership{} = membership} ->
        {:ok, workspace, membership}

      _missing_access ->
        {:error, :workspace_unavailable}
    end
  end

  def lock(%{user: _}, _workspace_id), do: {:error, :workspace_unavailable}

  defp lock_membership(%Workspace{id: workspace_id}, user_id) do
    Repo.one(
      from(membership in WorkspaceMembership,
        where: membership.workspace_id == ^workspace_id and membership.user_id == ^user_id,
        lock: "FOR UPDATE"
      )
    )
  end

  defp lock_membership(nil, _user_id), do: nil
end

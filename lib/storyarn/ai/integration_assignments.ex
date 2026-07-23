defmodule Storyarn.AI.IntegrationAssignments do
  @moduledoc """
  Security boundary for assigning actor-owned AI connections to workspaces.

  Every read and mutation is actor-scoped before workspace/provider filtering.
  """

  import Ecto.Query

  alias Storyarn.Accounts.Scope
  alias Storyarn.AI.Audit
  alias Storyarn.AI.Integration
  alias Storyarn.AI.IntegrationWorkspaceAssignment
  alias Storyarn.AI.PersonalConsent
  alias Storyarn.AI.Policy
  alias Storyarn.AI.WorkspacePolicy
  alias Storyarn.FeatureFlags
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Workspaces
  alias Storyarn.Workspaces.WorkspaceMembership

  @lock_namespace 981_006

  @type mutation_error ::
          :feature_disabled
          | :integration_unavailable
          | :workspace_unavailable
          | :member_personal_ai_disabled
          | :provider_already_assigned
          | :assignment_not_found
          | Ecto.Changeset.t()

  @spec assign(Scope.t(), pos_integer(), pos_integer()) ::
          {:ok, IntegrationWorkspaceAssignment.t()} | {:error, mutation_error()}
  def assign(%Scope{user: %{id: user_id}} = scope, integration_id, workspace_id)
      when is_integer(integration_id) and integration_id > 0 and is_integer(workspace_id) and workspace_id > 0 do
    transact_if_enabled(scope, fn ->
      assign_locked(scope, user_id, integration_id, workspace_id)
    end)
  end

  def assign(%Scope{}, _integration_id, _workspace_id), do: {:error, :workspace_unavailable}

  @spec unassign(Scope.t(), pos_integer(), pos_integer()) ::
          {:ok, IntegrationWorkspaceAssignment.t()} | {:error, mutation_error()}
  def unassign(%Scope{user: %{id: user_id}} = scope, integration_id, workspace_id)
      when is_integer(integration_id) and integration_id > 0 and is_integer(workspace_id) and workspace_id > 0 do
    transact_if_enabled(scope, fn ->
      unassign_locked(scope, user_id, integration_id, workspace_id)
    end)
  end

  def unassign(%Scope{}, _integration_id, _workspace_id), do: {:error, :assignment_not_found}

  @doc "Returns actor-visible workspace states for one actor-owned active integration."
  @spec list_states(Scope.t(), Integration.t()) :: [map()]
  def list_states(%Scope{user: %{id: user_id}} = scope, %Integration{user_id: user_id, revoked_at: nil} = integration) do
    workspaces = Workspaces.list_workspaces(scope)
    workspace_ids = Enum.map(workspaces, & &1.workspace.id)
    policies = policies_by_workspace(workspace_ids)
    assignments = assignments_by_workspace(user_id, integration.id, workspace_ids)

    Enum.map(workspaces, fn %{workspace: workspace, role: role} ->
      policy = Map.get(policies, workspace.id, %WorkspacePolicy{workspace_id: workspace.id, allowed_lanes: []})
      assignment = Map.get(assignments, workspace.id)
      eligibility = eligibility(role, policy)

      %{
        workspace_id: workspace.id,
        workspace_name: workspace.name,
        workspace_slug: workspace.slug,
        role: role,
        assigned: not is_nil(assignment),
        assignment_id: assignment && assignment.id,
        can_assign: eligibility in [:owner, :member],
        state: state(assignment, eligibility),
        reason: reason(eligibility)
      }
    end)
  end

  def list_states(%Scope{}, %Integration{}), do: []

  @doc false
  @spec active_for(pos_integer(), pos_integer(), pos_integer(), keyword()) ::
          IntegrationWorkspaceAssignment.t() | nil
  def active_for(user_id, workspace_id, integration_id, opts \\ [])
      when is_integer(user_id) and is_integer(workspace_id) and is_integer(integration_id) do
    query =
      from(assignment in IntegrationWorkspaceAssignment,
        join: membership in WorkspaceMembership,
        on:
          membership.user_id == assignment.user_id and
            membership.workspace_id == assignment.workspace_id,
        where:
          assignment.user_id == ^user_id and assignment.workspace_id == ^workspace_id and
            assignment.integration_id == ^integration_id and is_nil(assignment.revoked_at),
        select: assignment
      )

    query = if Keyword.get(opts, :lock, false), do: lock(query, "FOR UPDATE"), else: query
    Repo.one(query)
  end

  @doc false
  @spec authorize_route(pos_integer(), pos_integer(), Integration.t(), map(), keyword()) ::
          {:ok, IntegrationWorkspaceAssignment.t()} | {:error, :assignment_required}
  def authorize_route(user_id, workspace_id, integration, configuration, opts \\ [])

  def authorize_route(user_id, workspace_id, %Integration{} = integration, configuration, opts)
      when is_map(configuration) do
    assignment = active_for(user_id, workspace_id, integration.id, opts)

    if assignment && configuration["workspace_assignment_id"] == assignment.id,
      do: {:ok, assignment},
      else: {:error, :assignment_required}
  end

  def authorize_route(_user_id, _workspace_id, %Integration{}, _configuration, _opts), do: {:error, :assignment_required}

  @doc false
  @spec revoke_for_integration(pos_integer(), DateTime.t()) :: non_neg_integer()
  def revoke_for_integration(integration_id, revoked_at) do
    assignments =
      Repo.all(
        from(assignment in IntegrationWorkspaceAssignment,
          where: assignment.integration_id == ^integration_id and is_nil(assignment.revoked_at),
          lock: "FOR UPDATE"
        )
      )

    Enum.each(assignments, &revoke_assignment_only!(&1, revoked_at))
    length(assignments)
  end

  defp transact_if_enabled(scope, transaction_fun) do
    with :ok <- feature_enabled(scope) do
      transaction_fun
      |> Repo.transaction()
      |> unwrap_transaction()
    end
  end

  defp assign_locked(scope, user_id, integration_id, workspace_id) do
    with {:ok, workspace, membership} <- workspace_access(scope, workspace_id),
         %Integration{} = integration <- lock_owned_integration(integration_id, user_id),
         policy = Policy.get_effective(workspace.id, lock: true),
         :ok <- eligible(membership.role, policy) do
      lock_assignment!(user_id, workspace.id, integration.provider)
      get_or_insert(integration, workspace.id)
    else
      nil -> Repo.rollback(:integration_unavailable)
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp unassign_locked(scope, user_id, integration_id, workspace_id) do
    with {:ok, _workspace, membership} <- workspace_access(scope, workspace_id),
         :ok <- require_workspace_membership(membership.role) do
      case lock_active(user_id, integration_id, workspace_id) do
        %IntegrationWorkspaceAssignment{} = assignment ->
          revoke_locked!(assignment, TimeHelpers.now())

        nil ->
          Repo.rollback(:assignment_not_found)
      end
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp get_or_insert(integration, workspace_id) do
    case active_for(integration.user_id, workspace_id, integration.id, lock: true) do
      %IntegrationWorkspaceAssignment{} = assignment ->
        assignment

      nil ->
        ensure_provider_available!(integration.user_id, workspace_id, integration)
        insert_assignment!(integration, workspace_id)
    end
  end

  defp ensure_provider_available!(user_id, workspace_id, integration) do
    conflict =
      Repo.one(
        from(assignment in IntegrationWorkspaceAssignment,
          where:
            assignment.user_id == ^user_id and assignment.workspace_id == ^workspace_id and
              assignment.provider == ^integration.provider and is_nil(assignment.revoked_at),
          lock: "FOR UPDATE"
        )
      )

    if conflict, do: Repo.rollback(:provider_already_assigned), else: :ok
  end

  defp insert_assignment!(integration, workspace_id) do
    now = TimeHelpers.now()

    assignment =
      %IntegrationWorkspaceAssignment{
        user_id: integration.user_id,
        workspace_id: workspace_id,
        integration_id: integration.id,
        provider: integration.provider
      }
      |> IntegrationWorkspaceAssignment.assign_changeset(now)
      |> Repo.insert!()

    audit!(assignment, :workspace_assigned)
    assignment
  end

  defp revoke_locked!(assignment, revoked_at) do
    revoke_assignment_only!(assignment, revoked_at)

    Repo.update_all(
      from(consent in PersonalConsent,
        where:
          consent.user_id == ^assignment.user_id and consent.workspace_id == ^assignment.workspace_id and
            consent.integration_id == ^assignment.integration_id and is_nil(consent.revoked_at)
      ),
      set: [revoked_at: revoked_at, updated_at: revoked_at]
    )

    %{assignment | revoked_at: revoked_at, updated_at: revoked_at}
  end

  defp revoke_assignment_only!(assignment, revoked_at) do
    assignment
    |> IntegrationWorkspaceAssignment.revoke_changeset(revoked_at)
    |> Repo.update!()

    audit!(assignment, :workspace_unassigned)
  end

  defp audit!(assignment, action) do
    metadata = %{
      integration_id: assignment.integration_id,
      workspace_id: assignment.workspace_id,
      assignment_id: assignment.id
    }

    case Audit.log(assignment.user_id, assignment.provider, action, metadata) do
      {:ok, _audit} -> :ok
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  defp feature_enabled(%Scope{user: user}) do
    if FeatureFlags.enabled?(:ai_integrations, for: user), do: :ok, else: {:error, :feature_disabled}
  end

  defp workspace_access(scope, workspace_id) do
    case Workspaces.get_workspace(scope, workspace_id) do
      {:ok, workspace, membership} -> {:ok, workspace, membership}
      _error -> {:error, :workspace_unavailable}
    end
  end

  defp eligible("owner", %WorkspacePolicy{}), do: :ok
  defp eligible(nil, %WorkspacePolicy{}), do: {:error, :workspace_unavailable}

  defp eligible(_role, %WorkspacePolicy{allowed_lanes: lanes}) do
    if "personal_byok" in lanes, do: :ok, else: {:error, :member_personal_ai_disabled}
  end

  defp eligibility("owner", %WorkspacePolicy{}), do: :owner
  defp eligibility(nil, %WorkspacePolicy{}), do: :workspace_membership_required

  defp eligibility(_role, %WorkspacePolicy{allowed_lanes: lanes}) do
    if "personal_byok" in lanes, do: :member, else: :blocked
  end

  defp state(%IntegrationWorkspaceAssignment{}, :blocked), do: "blocked"
  defp state(%IntegrationWorkspaceAssignment{}, :workspace_membership_required), do: "blocked"
  defp state(%IntegrationWorkspaceAssignment{}, _eligibility), do: "assigned"
  defp state(nil, :blocked), do: "blocked"
  defp state(nil, :workspace_membership_required), do: "blocked"
  defp state(nil, _eligibility), do: "available"

  defp reason(:owner), do: "owner_allowed"
  defp reason(:member), do: "member_policy_allowed"
  defp reason(:blocked), do: "member_policy_disabled"
  defp reason(:workspace_membership_required), do: "workspace_membership_required"

  defp require_workspace_membership(nil), do: {:error, :workspace_unavailable}
  defp require_workspace_membership(role) when is_binary(role), do: :ok

  defp lock_owned_integration(integration_id, user_id) do
    Repo.one(
      from(integration in Integration,
        where: integration.id == ^integration_id and integration.user_id == ^user_id and is_nil(integration.revoked_at),
        lock: "FOR UPDATE"
      )
    )
  end

  defp lock_active(user_id, integration_id, workspace_id) do
    Repo.one(
      from(assignment in IntegrationWorkspaceAssignment,
        where:
          assignment.user_id == ^user_id and assignment.integration_id == ^integration_id and
            assignment.workspace_id == ^workspace_id and is_nil(assignment.revoked_at),
        lock: "FOR UPDATE"
      )
    )
  end

  defp lock_assignment!(user_id, workspace_id, provider) do
    lock_key = :erlang.phash2({user_id, workspace_id, provider}, 2_147_483_647)
    Repo.query!("SELECT pg_advisory_xact_lock($1, $2)", [@lock_namespace, lock_key])
  end

  defp assignments_by_workspace(_user_id, _integration_id, []), do: %{}

  defp assignments_by_workspace(user_id, integration_id, workspace_ids) do
    from(assignment in IntegrationWorkspaceAssignment,
      join: membership in WorkspaceMembership,
      on:
        membership.user_id == assignment.user_id and
          membership.workspace_id == assignment.workspace_id,
      where:
        assignment.user_id == ^user_id and assignment.integration_id == ^integration_id and
          assignment.workspace_id in ^workspace_ids and is_nil(assignment.revoked_at)
    )
    |> Repo.all()
    |> Map.new(&{&1.workspace_id, &1})
  end

  defp policies_by_workspace([]), do: %{}

  defp policies_by_workspace(workspace_ids) do
    from(policy in WorkspacePolicy, where: policy.workspace_id in ^workspace_ids)
    |> Repo.all()
    |> Map.new(&{&1.workspace_id, &1})
  end

  defp unwrap_transaction({:ok, result}), do: {:ok, result}
  defp unwrap_transaction({:error, reason}), do: {:error, reason}
end

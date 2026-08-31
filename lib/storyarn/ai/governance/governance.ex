defmodule Storyarn.AI.Governance do
  @moduledoc """
  Public capability boundary for AI access and workspace egress policy.

  Governance decides who may use an AI task, against which workspace or
  project, and which provider lanes the workspace owner permits. It reads the
  shared SQL tables through Governance-owned projections and never selects a
  provider or performs an inference request.
  """

  alias Storyarn.AI.Governance.Commands.Policies, as: PolicyCommands
  alias Storyarn.AI.Governance.Execution.Authorization
  alias Storyarn.AI.Governance.Queries.Policies, as: PolicyQueries
  alias Storyarn.AI.Governance.Queries.ProjectAccess
  alias Storyarn.AI.Governance.Queries.WorkspaceAccess
  alias Storyarn.AI.Governance.Rules.PolicyLanes
  alias Storyarn.AI.PolicyDecision

  @type actor :: %{required(:id) => pos_integer(), optional(atom()) => term()}
  @type scope :: %{required(:user) => actor() | nil, optional(atom()) => term()}

  defdelegate list_workspaces(scope), to: WorkspaceAccess, as: :list
  defdelegate get_workspace(scope, workspace_id), to: WorkspaceAccess, as: :get
  defdelegate workspace_can?(role, action), to: WorkspaceAccess, as: :can?

  defdelegate get_project(scope, project_id), to: ProjectAccess, as: :get
  defdelegate project_can?(role, action), to: ProjectAccess, as: :can?
  defdelegate effective_project_role(project_role, workspace_role), to: ProjectAccess, as: :effective_role

  defdelegate get_workspace_policy(scope, workspace_id), to: PolicyQueries, as: :get
  defdelegate update_workspace_policy(scope, workspace_id, lanes), to: PolicyCommands, as: :update
  defdelegate get_effective_policy(workspace_id), to: PolicyQueries, as: :get_effective
  defdelegate effective_policies(workspace_ids), to: PolicyQueries, as: :effective_by_workspace
  defdelegate lock_effective_policy(workspace_id), to: PolicyCommands, as: :lock_effective

  defdelegate effective_lanes(policy_or_lanes, workspace_role), to: PolicyLanes, as: :effective
  defdelegate personal_lane_allowed?(policy_or_lanes, workspace_role), to: PolicyLanes, as: :personal_allowed?

  defdelegate authorize(intent, task, phase, opts \\ []), to: Authorization
  defdelegate preauthorize_intent(intent, task, phase, opts \\ []), to: Authorization

  defdelegate complete_intent_authorization(intent, task, phase, preauthorization, opts \\ []),
    to: Authorization

  defdelegate prepare_operation_reauthorization(operation), to: Authorization
  defdelegate complete_operation_lock_preparation(operation, preparation), to: Authorization
  defdelegate preauthorize_operation(operation, task, phase, opts \\ []), to: Authorization

  defdelegate complete_operation_reauthorization(operation, task, phase, preauthorization, opts \\ []),
    to: Authorization

  defdelegate decision_to_map(decision), to: PolicyDecision, as: :to_map
end

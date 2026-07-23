defmodule Storyarn.AI.PolicyDecision do
  @moduledoc "Actor authorization decision, deliberately separate from provider routing."

  import Ecto.Query

  alias Storyarn.AI.ExecutionIntent
  alias Storyarn.AI.Operation
  alias Storyarn.AI.Policy
  alias Storyarn.AI.Task
  alias Storyarn.FeatureFlags
  alias Storyarn.Projects
  alias Storyarn.Projects.Memberships, as: ProjectMemberships
  alias Storyarn.Projects.Project
  alias Storyarn.Projects.ProjectMembership
  alias Storyarn.Repo
  alias Storyarn.Workspaces
  alias Storyarn.Workspaces.Workspace
  alias Storyarn.Workspaces.WorkspaceMembership

  @enforce_keys [
    :actor_id,
    :workspace_id,
    :project_id,
    :task_id,
    :phase,
    :policy_version,
    :allowed_lanes,
    :base_permission,
    :domain_permission
  ]
  defstruct [
    :actor_id,
    :workspace_id,
    :project_id,
    :task_id,
    :phase,
    :policy_version,
    :allowed_lanes,
    :base_permission,
    :domain_permission,
    :project_role,
    :workspace_role,
    bulk?: false,
    scheduled?: false
  ]

  @type t :: %__MODULE__{}

  @spec authorize(ExecutionIntent.t(), Task.t(), :execute | :apply | :attach, keyword()) ::
          {:ok, t()} | {:error, atom()}
  def authorize(%ExecutionIntent{} = intent, %Task{} = task, phase, opts \\ []) do
    lane = Keyword.get(opts, :lane)
    lock_policy? = Keyword.get(opts, :lock_policy, false)
    lock_access? = Keyword.get(opts, :lock_access, lock_policy?)
    subject_authorization = Keyword.get(opts, :subject_authorization, intent)

    with :ok <- feature_enabled(intent),
         :ok <- task_shape(intent, task, lane),
         {:ok, access} <- resolve_access(intent, lock_access?),
         :ok <- base_permission(access, task, intent),
         :ok <- domain_permission(access, task, phase),
         :ok <- Task.authorize_subject(task, intent.scope, subject_authorization, phase),
         policy = Policy.get_effective(intent.workspace_id, lock: lock_policy?),
         :ok <- lane_allowed(policy.allowed_lanes, task.allowed_lanes, lane) do
      {:ok,
       %__MODULE__{
         actor_id: intent.scope.user.id,
         workspace_id: intent.workspace_id,
         project_id: intent.project_id,
         task_id: task.id,
         phase: phase,
         policy_version: policy.version,
         allowed_lanes: allowed_lanes(intent, task, policy.allowed_lanes),
         base_permission: :use_ai,
         domain_permission: Map.fetch!(task.required_domain_permissions, phase),
         project_role: access.project_role,
         workspace_role: access.workspace_role,
         bulk?: intent.bulk?,
         scheduled?: intent.scheduled?
       }}
    end
  end

  @spec reauthorize(Operation.t(), Task.t(), :execute | :apply | :attach, keyword()) ::
          {:ok, t()} | {:error, atom()}
  def reauthorize(operation, task, phase, opts \\ [])

  def reauthorize(%Operation{user_id: nil}, %Task{}, _phase, _opts), do: {:error, :actor_deleted}

  def reauthorize(%Operation{} = operation, %Task{} = task, phase, opts) do
    user = Repo.get(Storyarn.Accounts.User, operation.user_id)

    if user do
      subject =
        if operation.subject_type do
          %{type: operation.subject_type, id: operation.subject_id, revision: operation.subject_revision}
        end

      {:ok, intent} =
        ExecutionIntent.new(Storyarn.Accounts.Scope.for_user(user), %{
          workspace_id: operation.workspace_id_snapshot,
          project_id: operation.project_id_snapshot,
          task_id: operation.task_id,
          input: %{},
          subject: subject,
          bulk?: operation.policy_decision["bulk"] || false,
          scheduled?: operation.policy_decision["scheduled"] || false
        })

      with {:ok, decision} <- authorize(intent, task, phase, Keyword.put(opts, :subject_authorization, operation)),
           true <- decision.policy_version == operation.policy_decision["policy_version"],
           true <- Task.subject_current?(task, operation) do
        {:ok, decision}
      else
        false -> {:error, :policy_or_subject_changed}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :actor_deleted}
    end
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = decision) do
    %{
      "workspace_id" => decision.workspace_id,
      "actor_id" => decision.actor_id,
      "project_id" => decision.project_id,
      "task_id" => decision.task_id,
      "phase" => Atom.to_string(decision.phase),
      "policy_version" => decision.policy_version,
      "allowed_lanes" => Enum.map(decision.allowed_lanes, &Atom.to_string/1),
      "base_permission" => Atom.to_string(decision.base_permission),
      "domain_permission" => Atom.to_string(decision.domain_permission),
      "project_role" => decision.project_role,
      "workspace_role" => decision.workspace_role,
      "bulk" => decision.bulk?,
      "scheduled" => decision.scheduled?
    }
  end

  defp feature_enabled(%ExecutionIntent{scope: %{user: user}}) do
    if FeatureFlags.enabled?(:ai_integrations, for: user), do: :ok, else: {:error, :feature_disabled}
  end

  defp task_shape(intent, task, lane) do
    with :ok <- task_matches(intent, task),
         :ok <- bulk_allowed(intent, task),
         :ok <- scheduled_allowed(intent, task, lane) do
      valid_data_scope(intent, task)
    end
  end

  defp task_matches(%ExecutionIntent{task_id: task_id}, %Task{id: task_id}), do: :ok
  defp task_matches(%ExecutionIntent{}, %Task{}), do: {:error, :task_mismatch}

  defp bulk_allowed(%ExecutionIntent{bulk?: false}, %Task{}), do: :ok
  defp bulk_allowed(%ExecutionIntent{}, %Task{bulk_allowed?: true}), do: :ok
  defp bulk_allowed(%ExecutionIntent{}, %Task{}), do: {:error, :bulk_not_allowed}

  defp scheduled_allowed(%ExecutionIntent{scheduled?: false}, %Task{}, _lane), do: :ok

  defp scheduled_allowed(%ExecutionIntent{scheduled?: true}, %Task{}, :personal_byok),
    do: {:error, :personal_byok_unattended}

  defp scheduled_allowed(%ExecutionIntent{}, %Task{scheduled_allowed?: true}, _lane), do: :ok
  defp scheduled_allowed(%ExecutionIntent{}, %Task{}, _lane), do: {:error, :scheduled_not_allowed}

  defp valid_data_scope(%ExecutionIntent{project_id: nil, subject: nil}, %Task{data_scope: :workspace}), do: :ok

  defp valid_data_scope(%ExecutionIntent{project_id: project_id, subject: nil}, %Task{data_scope: :project})
       when is_integer(project_id), do: :ok

  defp valid_data_scope(%ExecutionIntent{project_id: project_id, subject: subject}, %Task{data_scope: :entity})
       when is_integer(project_id) and not is_nil(subject), do: :ok

  defp valid_data_scope(%ExecutionIntent{}, %Task{}), do: {:error, :invalid_scope}

  defp resolve_access(%ExecutionIntent{scope: scope, workspace_id: workspace_id, project_id: nil}, false) do
    case Workspaces.get_workspace(scope, workspace_id) do
      {:ok, _workspace, membership} -> {:ok, %{workspace_role: membership.role, project_role: nil}}
      _error -> {:error, :unauthorized}
    end
  end

  defp resolve_access(%ExecutionIntent{scope: scope, workspace_id: workspace_id, project_id: project_id}, false) do
    with {:ok, project, project_membership} <- Projects.get_project(scope, project_id),
         true <- project.workspace_id == workspace_id,
         {:ok, _workspace, workspace_membership} <- Workspaces.get_workspace(scope, workspace_id) do
      {:ok, %{workspace_role: workspace_membership.role, project_role: project_membership.role}}
    else
      _error -> {:error, :unauthorized}
    end
  end

  defp resolve_access(%ExecutionIntent{scope: %{user: %{id: user_id}}, workspace_id: workspace_id, project_id: nil}, true) do
    workspace = Repo.one(from(workspace in Workspace, where: workspace.id == ^workspace_id, lock: "FOR SHARE"))

    membership =
      Repo.one(
        from(membership in WorkspaceMembership,
          where: membership.workspace_id == ^workspace_id and membership.user_id == ^user_id,
          lock: "FOR UPDATE"
        )
      )

    if workspace && membership,
      do: {:ok, %{workspace_role: membership.role, project_role: nil}},
      else: {:error, :unauthorized}
  end

  defp resolve_access(
         %ExecutionIntent{scope: %{user: %{id: user_id}}, workspace_id: workspace_id, project_id: project_id},
         true
       ) do
    project = lock_project(project_id, workspace_id)
    workspace = lock_workspace(workspace_id)
    project_membership = lock_project_membership(project_id, user_id)
    workspace_membership = lock_workspace_membership(workspace_id, user_id)

    project_role =
      ProjectMemberships.effective_role(
        membership_role(project_membership),
        membership_role(workspace_membership)
      )

    case {project, workspace, project_role} do
      {%Project{}, %Workspace{}, role} when is_binary(role) ->
        {:ok, %{workspace_role: membership_role(workspace_membership), project_role: role}}

      _missing ->
        {:error, :unauthorized}
    end
  end

  defp lock_project(project_id, workspace_id) do
    Repo.one(
      from(project in Project,
        where: project.id == ^project_id and project.workspace_id == ^workspace_id and is_nil(project.deleted_at),
        lock: "FOR SHARE"
      )
    )
  end

  defp lock_workspace(workspace_id) do
    Repo.one(from(workspace in Workspace, where: workspace.id == ^workspace_id, lock: "FOR SHARE"))
  end

  defp lock_project_membership(project_id, user_id) do
    Repo.one(
      from(membership in ProjectMembership,
        where: membership.project_id == ^project_id and membership.user_id == ^user_id,
        lock: "FOR UPDATE"
      )
    )
  end

  defp lock_workspace_membership(workspace_id, user_id) do
    Repo.one(
      from(membership in WorkspaceMembership,
        where: membership.workspace_id == ^workspace_id and membership.user_id == ^user_id,
        lock: "FOR UPDATE"
      )
    )
  end

  defp membership_role(%{role: role}), do: role
  defp membership_role(nil), do: nil

  defp base_permission(access, task, intent) do
    role = role_for_scope(access, task.data_scope)
    permission_module = permission_module(task.data_scope)

    cond do
      not permission_module.can?(role, :use_ai) -> {:error, :missing_use_ai}
      intent.bulk? and not permission_module.can?(role, :run_bulk_ai) -> {:error, :missing_run_bulk_ai}
      true -> :ok
    end
  end

  defp domain_permission(access, task, phase) do
    case Map.fetch(task.required_domain_permissions, phase) do
      {:ok, permission} ->
        role = role_for_scope(access, task.data_scope)

        if permission_module(task.data_scope).can?(role, permission),
          do: :ok,
          else: {:error, :missing_domain_permission}

      :error ->
        {:error, :unsupported_phase}
    end
  end

  defp role_for_scope(access, :workspace), do: access.workspace_role
  defp role_for_scope(access, scope) when scope in [:project, :entity], do: access.project_role

  defp permission_module(:workspace), do: Workspaces
  defp permission_module(scope) when scope in [:project, :entity], do: Projects

  defp lane_allowed(policy_lanes, task_lanes, nil) do
    if Enum.any?(task_lanes, &(Atom.to_string(&1) in policy_lanes)), do: :ok, else: {:error, :ai_disabled}
  end

  defp lane_allowed(policy_lanes, task_lanes, lane) when lane in [:managed, :personal_byok, :workspace_byok] do
    cond do
      policy_lanes == [] -> {:error, :ai_disabled}
      lane in task_lanes and Atom.to_string(lane) in policy_lanes -> :ok
      true -> {:error, :lane_not_allowed}
    end
  end

  defp lane_allowed(_policy_lanes, _task_lanes, _lane), do: {:error, :lane_not_allowed}

  defp allowed_lanes(%ExecutionIntent{scheduled?: true}, task, policy_lanes) do
    task.allowed_lanes
    |> List.delete(:personal_byok)
    |> Enum.filter(&(Atom.to_string(&1) in policy_lanes))
  end

  defp allowed_lanes(%ExecutionIntent{}, task, policy_lanes) do
    Enum.filter(task.allowed_lanes, &(Atom.to_string(&1) in policy_lanes))
  end
end

defmodule Storyarn.AI.Governance.Execution.Authorization do
  @moduledoc "Evaluates and rechecks actor authorization for one AI operation phase."

  import Ecto.Query

  alias Storyarn.AI.ExecutionIntent
  alias Storyarn.AI.Governance.Adapters.FeatureFlags
  alias Storyarn.AI.Governance.Commands.Policies, as: PolicyCommands
  alias Storyarn.AI.Governance.Projections.ProjectMembershipRecord, as: ProjectMembership
  alias Storyarn.AI.Governance.Projections.ProjectRecord, as: Project
  alias Storyarn.AI.Governance.Projections.UserRecord, as: User
  alias Storyarn.AI.Governance.Projections.WorkspaceMembershipRecord, as: WorkspaceMembership
  alias Storyarn.AI.Governance.Projections.WorkspaceRecord, as: Workspace
  alias Storyarn.AI.Governance.Queries.Policies
  alias Storyarn.AI.Governance.Queries.ProjectAccess
  alias Storyarn.AI.Governance.Queries.WorkspaceAccess
  alias Storyarn.AI.Governance.Rules.PolicyLanes
  alias Storyarn.AI.Operation
  alias Storyarn.AI.PolicyDecision
  alias Storyarn.AI.Task
  alias Storyarn.Repo

  @reauthorization_identity_fields [
    :id,
    :user_id,
    :actor_id,
    :workspace_id,
    :workspace_id_snapshot,
    :project_id,
    :project_id_snapshot,
    :route_option_id,
    :task_id,
    :task_contract_hash,
    :capability,
    :idempotency_key,
    :subject_type,
    :subject_id,
    :subject_revision,
    :context_hash,
    :context_manifest,
    :context_subject,
    :input_hash,
    :input_schema_version,
    :output_schema_version,
    :prompt_version,
    :context_version,
    :result_type,
    :result_destination,
    :policy_decision,
    :execution_route
  ]

  # The live foreign keys are deliberately absent. A committed hard delete may
  # nilify them while a transition waits for Operation; the durable snapshots
  # and semantic contract remain the identity required for technical cleanup.
  @technical_operation_identity_fields [
    :id,
    :actor_id,
    :workspace_id_snapshot,
    :project_id_snapshot,
    :task_id,
    :task_contract_hash,
    :capability,
    :idempotency_key,
    :subject_type,
    :subject_id,
    :subject_revision,
    :context_hash,
    :context_manifest,
    :context_subject,
    :input_hash,
    :input_schema_version,
    :output_schema_version,
    :prompt_version,
    :context_version,
    :result_type,
    :result_destination,
    :policy_decision,
    :execution_route
  ]

  @opaque intent_authorization :: %{
            identity: binary(),
            task_contract_hash: String.t(),
            phase: :execute | :apply | :attach,
            lane: atom() | nil,
            result: {:ok, PolicyDecision.t()}
          }

  @opaque operation_reauthorization :: %{
            identity: map(),
            task_contract_hash: String.t(),
            phase: :execute | :apply | :attach,
            lane: atom() | nil,
            result: {:ok, PolicyDecision.t()} | {:error, atom()}
          }

  @opaque operation_lock_preparation :: %{
            identity: map(),
            technical_identity: map(),
            workspace_id: pos_integer() | nil,
            workspace_present?: boolean()
          }

  @spec authorize(ExecutionIntent.t(), Task.t(), :execute | :apply | :attach, keyword()) ::
          {:ok, PolicyDecision.t()} | {:error, atom()}
  def authorize(%ExecutionIntent{} = intent, %Task{} = task, phase, opts \\ []) do
    lane = Keyword.get(opts, :lane)
    lock_policy? = Keyword.get(opts, :lock_policy, false)
    lock_access? = Keyword.get(opts, :lock_access, lock_policy?)
    subject_authorization = Keyword.get(opts, :subject_authorization, intent)
    owner_requirement = owner_authorization_requirement(intent, task, phase)

    with :ok <- feature_enabled(intent),
         :ok <- task_shape(intent, task, lane),
         {:ok, access} <- resolve_access(intent, lock_access?, owner_requirement),
         :ok <- validate_canonical_owner(intent, access, owner_requirement),
         :ok <- base_permission(access, task, intent),
         :ok <- domain_permission(access, task, phase),
         :ok <- Task.authorize_subject(task, intent.scope, subject_authorization, phase),
         policy = effective_policy(intent.workspace_id, lock_policy?),
         effective_lanes = PolicyLanes.effective(policy, access.workspace_role),
         :ok <- lane_allowed(effective_lanes, task.allowed_lanes, lane) do
      {:ok,
       %PolicyDecision{
         actor_id: intent.scope.user.id,
         workspace_id: intent.workspace_id,
         project_id: intent.project_id,
         task_id: task.id,
         phase: phase,
         policy_version: policy.version,
         allowed_lanes: allowed_lanes(intent, task, effective_lanes),
         base_permission: :use_ai,
         domain_permission: Map.fetch!(task.required_domain_permissions, phase),
         project_role: access.project_role,
         workspace_role: access.workspace_role,
         bulk?: intent.bulk?,
         scheduled?: intent.scheduled?
       }}
    end
  end

  @doc """
  Performs the locked authorization pass before an intent waits on execution rows.

  This is the only way to obtain the opaque token accepted by
  `complete_intent_authorization/5`. A successful token therefore proves that
  the current transaction already retains Workspace, Project, membership and
  policy locks before it acquires a RouteOption lock.
  """
  @spec preauthorize_intent(
          ExecutionIntent.t(),
          Task.t(),
          :execute | :apply | :attach,
          keyword()
        ) :: {:ok, intent_authorization()} | {:error, atom()}
  def preauthorize_intent(%ExecutionIntent{} = intent, %Task{} = task, phase, opts \\ []) do
    ensure_transaction!()
    lane = Keyword.get(opts, :lane)

    case authorize(intent, task, phase,
           lane: lane,
           lock_access: true,
           lock_policy: true
         ) do
      {:ok, %PolicyDecision{} = decision} ->
        {:ok,
         %{
           identity: intent_authorization_identity(intent),
           task_contract_hash: Task.contract_hash(task),
           phase: phase,
           lane: lane,
           result: {:ok, decision}
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Rechecks volatile authorization after a downstream execution row is locked.

  The opaque preauthorization pins the intent, task contract, phase, lane and
  preliminary decision. This completion is deliberately lock-free: it checks
  the feature/task switches, pinned pure permissions and only consumer
  callbacks covered by the task's explicit lock-free contract.
  """
  @spec complete_intent_authorization(
          ExecutionIntent.t(),
          Task.t(),
          :execute | :apply | :attach,
          intent_authorization(),
          keyword()
        ) :: {:ok, PolicyDecision.t()} | {:error, atom()}
  def complete_intent_authorization(intent, task, phase, preauthorization, opts \\ [])

  def complete_intent_authorization(
        %ExecutionIntent{} = intent,
        %Task{} = task,
        phase,
        %{
          identity: identity,
          task_contract_hash: task_contract_hash,
          phase: prepared_phase,
          lane: prepared_lane,
          result: preliminary_result
        },
        opts
      ) do
    ensure_transaction!()
    lane = Keyword.get(opts, :lane)
    current_task_contract_hash = Task.contract_hash(task)

    with :ok <- current_intent_authorization_identity(intent, identity),
         :ok <- current_task_contract(current_task_contract_hash, task_contract_hash),
         :ok <- expected_intent_authorization_pass(phase, lane, prepared_phase, prepared_lane),
         {:ok, %PolicyDecision{} = decision} <- preliminary_result,
         :ok <- volatile_intent_authorization(intent, task, phase, lane, decision) do
      {:ok, decision}
    end
  end

  def complete_intent_authorization(%ExecutionIntent{}, %Task{}, _phase, _preauthorization, _opts) do
    ensure_transaction!()
    {:error, :authorization_changed}
  end

  @doc """
  Performs the locked first authorization pass before `Operation FOR UPDATE`.

  This function is internal to the split transition protocol. Calling it after
  locking an Operation would reacquire Workspace, Project, membership and
  policy locks in the opposite direction. Transition code must use
  `preauthorize_operation/4` followed by
  `complete_operation_reauthorization/5` instead.
  """
  @spec reauthorize(Operation.t(), Task.t(), :execute | :apply | :attach, keyword()) ::
          {:ok, PolicyDecision.t()} | {:error, atom()}
  def reauthorize(operation, task, phase, opts \\ [])

  def reauthorize(%Operation{user_id: nil}, %Task{}, _phase, _opts), do: {:error, :actor_deleted}

  def reauthorize(%Operation{} = operation, %Task{} = task, phase, opts) do
    with {:ok, intent} <- operation_intent(operation),
         {:ok, decision} <- authorize(intent, task, phase, Keyword.put(opts, :subject_authorization, operation)),
         true <- decision.policy_version == operation.policy_decision["policy_version"],
         true <- Task.subject_current?(task, operation) do
      {:ok, decision}
    else
      false -> {:error, :policy_or_subject_changed}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Establishes the technical parent lock required before inspecting a task.

  This deliberately locks the snapshotted Workspace before feature switches,
  task contracts or authorization are evaluated. Even a denied operation must
  retain this edge before it waits for `ai_operations FOR UPDATE`; otherwise a
  concurrent workspace hard delete could retain Workspace while waiting for the
  same Operation in the opposite direction.

  The preparation is transaction-local and may be passed to
  `preauthorize_operation/4` through its `:preparation` option.
  """
  @spec prepare_operation_reauthorization(Operation.t()) :: operation_lock_preparation()
  def prepare_operation_reauthorization(%Operation{} = operation) do
    ensure_transaction!()
    workspace_id = operation.workspace_id_snapshot || operation.workspace_id

    workspace =
      if workspace_id do
        Repo.one(from(workspace in Workspace, where: workspace.id == ^workspace_id, lock: "FOR SHARE"))
      end

    %{
      identity: reauthorization_identity(operation),
      technical_identity: technical_operation_identity(operation),
      workspace_id: workspace_id,
      workspace_present?: match?(%Workspace{}, workspace)
    }
  end

  @doc """
  Validates a technical root-lock token after taking Operation.

  Unlike authorization completion, this deliberately accepts a missing
  Workspace and foreign keys nilified by a committed hard delete. At that
  point no parent lock remains to form a cycle, and settlement or recovery must
  still be able to finish. Durable snapshots and semantic operation fields must
  remain identical.
  """
  @spec complete_operation_lock_preparation(Operation.t(), operation_lock_preparation()) ::
          :ok | {:error, :operation_authorization_changed}
  def complete_operation_lock_preparation(%Operation{} = operation, %{
        technical_identity: technical_identity,
        workspace_id: workspace_id
      }) do
    ensure_transaction!()
    expected_workspace_id = operation.workspace_id_snapshot || operation.workspace_id

    if technical_operation_identity(operation) == technical_identity and
         workspace_id == expected_workspace_id do
      :ok
    else
      {:error, :operation_authorization_changed}
    end
  end

  def complete_operation_lock_preparation(%Operation{}, _preparation) do
    ensure_transaction!()
    {:error, :operation_authorization_changed}
  end

  @doc """
  Acquires every upstream lock needed to reauthorize an operation.

  This is the first half of the operation transition protocol. It must run in
  the same transaction, before the caller takes `ai_operations FOR UPDATE`.
  Access is locked in Workspace -> Project -> memberships/policy order, so a
  workspace hard delete can never hold Workspace while this transaction holds
  Operation and waits in the opposite direction.

  The returned value is deliberately opaque. Pass it, together with the current
  `FOR UPDATE` operation row, to `complete_operation_reauthorization/5` before
  making a transition or invoking a feature-owned apply callback.
  """
  @spec preauthorize_operation(Operation.t(), Task.t(), :execute | :apply | :attach, keyword()) ::
          operation_reauthorization()
  def preauthorize_operation(%Operation{} = operation, %Task{} = task, phase, opts \\ []) do
    ensure_transaction!()
    {preparation, opts} = Keyword.pop(opts, :preparation)
    preparation = preparation || prepare_operation_reauthorization(operation)
    lane = Keyword.get(opts, :lane)

    result =
      with :ok <- valid_authorization_lock_preparation(operation, preparation) do
        reauthorize(operation, task, phase,
          lane: lane,
          lock_access: true,
          lock_policy: true
        )
      end

    %{
      identity: reauthorization_identity(operation),
      task_contract_hash: Task.contract_hash(task),
      phase: phase,
      lane: lane,
      result: result
    }
  end

  @doc """
  Completes a preauthorization against the current locked operation row.

  The immutable authorization fingerprint, requested phase/lane and task
  contract are checked again after `ai_operations FOR UPDATE`. A narrow second
  pass rechecks the current actor, feature flag, task shape and explicitly
  lock-free subject callbacks. It never queries Workspace, Project,
  memberships or policy again: all of those rows were already validated and
  remain locked by the transaction.
  """
  @spec complete_operation_reauthorization(
          Operation.t(),
          Task.t(),
          :execute | :apply | :attach,
          operation_reauthorization(),
          keyword()
        ) ::
          {:ok, PolicyDecision.t()} | {:error, atom()}
  def complete_operation_reauthorization(
        %Operation{} = operation,
        %Task{} = task,
        phase,
        %{
          identity: identity,
          task_contract_hash: task_contract_hash,
          phase: prepared_phase,
          lane: prepared_lane,
          result: preliminary_result
        },
        opts \\ []
      ) do
    ensure_transaction!()
    lane = Keyword.get(opts, :lane)
    current_task_contract_hash = Task.contract_hash(task)

    with :ok <- current_reauthorization_identity(operation, identity),
         :ok <- current_task_contract(current_task_contract_hash, task_contract_hash),
         :ok <- operation_task_contract(operation, current_task_contract_hash),
         :ok <- expected_authorization_pass(phase, lane, prepared_phase, prepared_lane),
         {:ok, %PolicyDecision{} = decision} <- preliminary_result,
         {:ok, intent} <- operation_intent(operation),
         :ok <- volatile_authorization(operation, intent, task, phase, lane, decision) do
      {:ok, decision}
    end
  end

  defp valid_authorization_lock_preparation(operation, %{
         identity: identity,
         workspace_id: workspace_id,
         workspace_present?: workspace_present?
       }) do
    expected_workspace_id = operation.workspace_id_snapshot || operation.workspace_id

    cond do
      reauthorization_identity(operation) != identity ->
        {:error, :operation_authorization_changed}

      workspace_id != expected_workspace_id ->
        {:error, :operation_authorization_changed}

      not workspace_present? ->
        {:error, :unauthorized}

      true ->
        :ok
    end
  end

  defp valid_authorization_lock_preparation(_operation, _preparation), do: {:error, :operation_authorization_changed}

  defp current_reauthorization_identity(operation, identity) do
    if reauthorization_identity(operation) == identity,
      do: :ok,
      else: {:error, :operation_authorization_changed}
  end

  defp current_intent_authorization_identity(intent, identity) do
    if intent_authorization_identity(intent) == identity,
      do: :ok,
      else: {:error, :authorization_changed}
  end

  defp current_task_contract(current_task_contract_hash, task_contract_hash) do
    if current_task_contract_hash == task_contract_hash,
      do: :ok,
      else: {:error, :task_contract_changed}
  end

  defp operation_task_contract(operation, current_task_contract_hash) do
    if operation.task_contract_hash == current_task_contract_hash,
      do: :ok,
      else: {:error, :task_contract_changed}
  end

  defp reauthorization_identity(%Operation{} = operation) do
    Map.take(operation, @reauthorization_identity_fields)
  end

  defp technical_operation_identity(%Operation{} = operation) do
    Map.take(operation, @technical_operation_identity_fields)
  end

  defp intent_authorization_identity(%ExecutionIntent{} = intent) do
    identity = {
      intent.scope,
      intent.workspace_id,
      intent.project_id,
      intent.task_id,
      intent.input,
      intent.input_hash,
      intent.subject,
      intent.requested_route_ref,
      intent.idempotency_key,
      intent.bulk?,
      intent.scheduled?
    }

    identity
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
  end

  defp expected_intent_authorization_pass(phase, lane, phase, lane) when phase in [:execute, :apply, :attach], do: :ok

  defp expected_intent_authorization_pass(_phase, _lane, _prepared_phase, _prepared_lane),
    do: {:error, :authorization_changed}

  defp expected_authorization_pass(phase, lane, phase, lane) when phase in [:execute, :apply, :attach], do: :ok

  defp expected_authorization_pass(_phase, _lane, _prepared_phase, _prepared_lane),
    do: {:error, :operation_authorization_changed}

  # This is intentionally not a second call to authorize/4. The first pass
  # retains every Workspace, Project, membership and policy lock. Re-entering
  # that graph behind Operation would recreate the lock inversion this split
  # protocol exists to remove. Only volatile, lock-free facts are checked here.
  defp volatile_intent_authorization(intent, task, phase, lane, decision) do
    access = %{
      workspace_role: decision.workspace_role,
      project_role: decision.project_role
    }

    with :ok <- feature_enabled(intent),
         true <- Task.enabled?(task) || {:error, :task_disabled},
         :ok <- task_shape(intent, task, lane),
         :ok <- decision_matches_intent(decision, intent, task, phase),
         :ok <- base_permission(access, task, intent),
         :ok <- domain_permission(access, task, phase),
         :ok <- safe_post_operation_subject_callbacks(task),
         :ok <- Task.authorize_subject(task, intent.scope, intent, phase) do
      decision_lane_allowed(decision, task, lane)
    end
  end

  defp volatile_authorization(operation, intent, task, phase, lane, decision) do
    access = %{
      workspace_role: decision.workspace_role,
      project_role: decision.project_role
    }

    with :ok <- feature_enabled(intent),
         :ok <- task_shape(intent, task, lane),
         :ok <- decision_matches_operation(decision, operation, intent, task, phase),
         :ok <- base_permission(access, task, intent),
         :ok <- domain_permission(access, task, phase),
         :ok <- safe_post_operation_subject_callbacks(task),
         :ok <- Task.authorize_subject(task, intent.scope, operation, phase),
         :ok <- decision_lane_allowed(decision, task, lane),
         true <- Task.subject_current?(task, operation) do
      :ok
    else
      false -> {:error, :policy_or_subject_changed}
      {:error, reason} -> {:error, reason}
    end
  end

  defp decision_matches_operation(decision, operation, intent, task, phase) do
    expected_domain_permission = Map.get(task.required_domain_permissions, phase)

    if operation_decision_identity_matches?(decision, operation, intent) and
         operation_decision_contract_matches?(decision, operation, task, phase) and
         decision_requirements_match?(decision, expected_domain_permission, intent) do
      :ok
    else
      {:error, :operation_authorization_changed}
    end
  end

  defp decision_matches_intent(decision, intent, task, phase) do
    expected_domain_permission = Map.get(task.required_domain_permissions, phase)

    if intent_decision_identity_matches?(decision, intent, task) and
         decision.phase == phase and
         decision_requirements_match?(decision, expected_domain_permission, intent) do
      :ok
    else
      {:error, :authorization_changed}
    end
  end

  defp operation_decision_identity_matches?(decision, operation, intent) do
    decision.actor_id == operation.actor_id and
      decision.actor_id == intent.scope.user.id and
      decision.workspace_id == operation.workspace_id_snapshot and
      decision.project_id == operation.project_id_snapshot
  end

  defp operation_decision_contract_matches?(decision, operation, task, phase) do
    decision.task_id == operation.task_id and
      decision.task_id == task.id and
      decision.phase == phase and
      decision.policy_version == operation.policy_decision["policy_version"]
  end

  defp intent_decision_identity_matches?(decision, intent, task) do
    decision.actor_id == intent.scope.user.id and
      decision.workspace_id == intent.workspace_id and
      decision.project_id == intent.project_id and
      decision.task_id == intent.task_id and
      decision.task_id == task.id
  end

  defp decision_requirements_match?(decision, expected_domain_permission, intent) do
    decision.base_permission == :use_ai and
      decision.domain_permission == expected_domain_permission and
      decision.bulk? == intent.bulk? and
      decision.scheduled? == intent.scheduled?
  end

  defp decision_lane_allowed(%PolicyDecision{allowed_lanes: allowed_lanes}, task, lane) do
    policy_lanes = Enum.map(allowed_lanes, &Atom.to_string/1)
    lane_allowed(policy_lanes, task.allowed_lanes, lane)
  end

  defp safe_post_operation_subject_callbacks(task) do
    if Task.post_operation_authorization_safe?(task),
      do: :ok,
      else: {:error, :unsafe_post_operation_authorization}
  end

  defp operation_intent(%Operation{user_id: nil}), do: {:error, :actor_deleted}

  defp operation_intent(%Operation{} = operation) do
    case Repo.get(User, operation.user_id) do
      %User{} = user ->
        ExecutionIntent.new(%{user: user}, %{
          workspace_id: operation.workspace_id_snapshot,
          project_id: operation.project_id_snapshot,
          task_id: operation.task_id,
          input: %{},
          subject: operation_subject(operation),
          bulk?: operation.policy_decision["bulk"] || false,
          scheduled?: operation.policy_decision["scheduled"] || false
        })

      nil ->
        {:error, :actor_deleted}
    end
  end

  defp operation_subject(%Operation{subject_type: nil}), do: nil

  defp operation_subject(%Operation{} = operation) do
    %{type: operation.subject_type, id: operation.subject_id, revision: operation.subject_revision}
  end

  defp ensure_transaction! do
    if Repo.in_transaction?() do
      :ok
    else
      raise ArgumentError, "operation reauthorization must run inside one database transaction"
    end
  end

  defp feature_enabled(%ExecutionIntent{scope: %{user: user}}) do
    if FeatureFlags.ai_integrations_enabled?(user), do: :ok, else: {:error, :feature_disabled}
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

  defp resolve_access(%ExecutionIntent{scope: scope, workspace_id: workspace_id, project_id: nil}, false, _requirement) do
    case WorkspaceAccess.get(scope, workspace_id) do
      {:ok, workspace, membership} ->
        {:ok,
         %{
           workspace: workspace,
           workspace_role: membership.role,
           project: nil,
           project_role: nil
         }}

      _error ->
        {:error, :unauthorized}
    end
  end

  defp resolve_access(
         %ExecutionIntent{scope: scope, workspace_id: workspace_id, project_id: project_id},
         false,
         _requirement
       ) do
    with {:ok, project, project_membership} <- ProjectAccess.get(scope, project_id),
         true <- project.workspace_id == workspace_id,
         {:ok, workspace, workspace_membership} <- WorkspaceAccess.get(scope, workspace_id) do
      {:ok,
       %{
         workspace: workspace,
         workspace_role: workspace_membership.role,
         project: project,
         project_role: project_membership.role
       }}
    else
      _error -> {:error, :unauthorized}
    end
  end

  defp resolve_access(
         %ExecutionIntent{scope: %{user: %{id: user_id}}, workspace_id: workspace_id, project_id: nil},
         true,
         owner_requirement
       ) do
    workspace = Repo.one(from(workspace in Workspace, where: workspace.id == ^workspace_id, lock: "FOR SHARE"))

    {membership, locked_memberships} =
      if owner_requirement == :none do
        {lock_workspace_membership(workspace_id, user_id), nil}
      else
        memberships = lock_workspace_memberships(workspace_id)
        {Enum.find(memberships, &(&1.user_id == user_id)), memberships}
      end

    if workspace && membership do
      access = %{
        workspace: workspace,
        workspace_role: membership.role,
        project: nil,
        project_role: nil
      }

      {:ok, put_locked_memberships(access, :workspace_memberships, locked_memberships)}
    else
      {:error, :unauthorized}
    end
  end

  defp resolve_access(
         %ExecutionIntent{scope: %{user: %{id: user_id}}, workspace_id: workspace_id, project_id: project_id},
         true,
         owner_requirement
       ) do
    # Cross-context writers acquire parent rows in Workspace -> Project order.
    # Keeping that order here is load-bearing: a workspace hard delete holds
    # Workspace FOR UPDATE before cascading into Projects. Locking Project first
    # would let AI retain Project FOR SHARE while waiting for Workspace and close
    # a deadlock cycle with that delete.
    workspace = lock_workspace(workspace_id)
    project = lock_project(project_id, workspace_id)
    workspace_membership = lock_workspace_membership(workspace_id, user_id)

    # Bulk and owner-only authorization validate the complete owner invariant.
    # Lock the aggregate in the same stable order as ownership transfer instead
    # of locking the actor first: with duplicate owner rows, actor-first locks
    # could otherwise let concurrent authorizations acquire opposite rows.
    {project_membership, locked_project_memberships} =
      if owner_requirement == :none do
        {lock_project_membership(project_id, user_id), nil}
      else
        memberships = lock_project_memberships(project_id)
        {Enum.find(memberships, &(&1.user_id == user_id)), memberships}
      end

    project_role =
      ProjectAccess.effective_role(
        membership_role(project_membership),
        membership_role(workspace_membership)
      )

    case {project, workspace, project_role} do
      {%Project{}, %Workspace{}, role} when is_binary(role) ->
        access = %{
          workspace: workspace,
          workspace_role: membership_role(workspace_membership),
          project: project,
          project_role: role
        }

        {:ok,
         put_locked_memberships(
           access,
           :project_memberships,
           locked_project_memberships
         )}

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

  defp lock_project_memberships(project_id) do
    Repo.all(
      from(membership in ProjectMembership,
        where: membership.project_id == ^project_id,
        order_by: [asc: membership.user_id, asc: membership.id],
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

  defp lock_workspace_memberships(workspace_id) do
    Repo.all(
      from(membership in WorkspaceMembership,
        where: membership.workspace_id == ^workspace_id,
        order_by: [asc: membership.user_id, asc: membership.id],
        lock: "FOR UPDATE"
      )
    )
  end

  defp put_locked_memberships(access, _key, nil), do: access
  defp put_locked_memberships(access, key, memberships), do: Map.put(access, key, memberships)

  defp membership_role(%{role: role}), do: role
  defp membership_role(nil), do: nil

  defp owner_authorization_requirement(%ExecutionIntent{bulk?: true}, %Task{}, _phase), do: :bulk

  defp owner_authorization_requirement(%ExecutionIntent{}, %Task{} = task, phase) do
    if Map.get(task.required_domain_permissions, phase) in [:manage_workspace, :manage_project],
      do: :owner_permission,
      else: :none
  end

  defp validate_canonical_owner(%ExecutionIntent{}, _access, :none), do: :ok

  defp validate_canonical_owner(
         %ExecutionIntent{project_id: nil, scope: %{user: %{id: actor_id}}},
         %{workspace: %Workspace{owner_id: owner_id}} = access,
         requirement
       ) do
    owner_memberships =
      owner_memberships(
        access,
        :workspace_memberships,
        fn -> list_workspace_owner_memberships(access.workspace.id) end
      )

    validate_owner_membership(owner_memberships, owner_id, actor_id, requirement)
  end

  defp validate_canonical_owner(
         %ExecutionIntent{project_id: project_id, scope: %{user: %{id: actor_id}}},
         %{project: %Project{id: project_id, owner_id: owner_id}} = access,
         requirement
       ) do
    owner_memberships =
      owner_memberships(
        access,
        :project_memberships,
        fn -> list_project_owner_memberships(project_id) end
      )

    validate_owner_membership(owner_memberships, owner_id, actor_id, requirement)
  end

  defp owner_memberships(access, key, unlocked_query) do
    case Map.fetch(access, key) do
      {:ok, memberships} -> Enum.filter(memberships, &(&1.role == "owner"))
      :error -> unlocked_query.()
    end
  end

  defp list_project_owner_memberships(project_id) do
    Repo.all(
      from(membership in ProjectMembership,
        where: membership.project_id == ^project_id and membership.role == "owner",
        order_by: [asc: membership.user_id, asc: membership.id]
      )
    )
  end

  defp list_workspace_owner_memberships(workspace_id) do
    Repo.all(
      from(membership in WorkspaceMembership,
        where: membership.workspace_id == ^workspace_id and membership.role == "owner",
        order_by: [asc: membership.user_id, asc: membership.id]
      )
    )
  end

  defp validate_owner_membership([%{user_id: owner_id}], owner_id, owner_id, _requirement), do: :ok

  defp validate_owner_membership([%{user_id: owner_id}], owner_id, _actor_id, :bulk), do: {:error, :missing_run_bulk_ai}

  defp validate_owner_membership([%{user_id: owner_id}], owner_id, _actor_id, :owner_permission),
    do: {:error, :missing_domain_permission}

  defp validate_owner_membership(_owner_memberships, _owner_id, _actor_id, _requirement),
    do: {:error, :ownership_invariant_violation}

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

  defp permission_module(:workspace), do: WorkspaceAccess
  defp permission_module(scope) when scope in [:project, :entity], do: ProjectAccess

  defp effective_policy(workspace_id, true), do: PolicyCommands.lock_effective(workspace_id)
  defp effective_policy(workspace_id, false), do: Policies.get_effective(workspace_id)

  defp lane_allowed(policy_lanes, task_lanes, nil) do
    if Enum.any?(task_lanes, &(Atom.to_string(&1) in policy_lanes)), do: :ok, else: {:error, :ai_disabled}
  end

  defp lane_allowed(policy_lanes, task_lanes, lane) when lane in [:managed, :personal_byok, :workspace_byok] do
    task_policy_lanes = Enum.filter(task_lanes, &(Atom.to_string(&1) in policy_lanes))

    cond do
      task_policy_lanes == [] -> {:error, :ai_disabled}
      lane in task_policy_lanes -> :ok
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

defmodule Storyarn.AI.Context do
  @moduledoc """
  Builds bounded, authorized and deterministic context packages.

  This boundary never calls an inference provider and never loads a whole
  project. Every selection comes from a registered task and one typed subject.
  """

  alias Storyarn.Accounts.Scope
  alias Storyarn.AI.Context.Finalizer
  alias Storyarn.AI.Context.Package
  alias Storyarn.AI.Context.Policy
  alias Storyarn.AI.Context.SubjectRef
  alias Storyarn.AI.ExecutionIntent
  alias Storyarn.AI.Operation
  alias Storyarn.AI.Task
  alias Storyarn.AI.Telemetry
  alias Storyarn.Projects

  @spec build_context(Scope.t(), Task.t(), SubjectRef.t()) ::
          {:ok, Package.t()} | {:error, atom()}
  def build_context(%Scope{} = scope, %Task{} = task, %SubjectRef{} = subject_ref) do
    started = System.monotonic_time()

    result =
      with {:ok, policy} <- Policy.new(task.context_policy),
           :ok <- contextual_policy(policy),
           {:ok, subject_ref} <- SubjectRef.validate(subject_ref),
           :ok <- matching_scope(policy, subject_ref),
           {:ok, project, _membership} <- authorize_project(scope, subject_ref),
           {:ok, draft} <- builder(policy.scope).build(project, subject_ref, policy) do
        Finalizer.finalize(
          policy,
          task.context_version,
          draft.entities,
          draft.excluded,
          draft.warnings
        )
      end

    emit_telemetry(task, result, started)
    result
  end

  def build_context(_scope, _task, _subject_ref), do: {:error, :invalid_context_subject}

  @doc "Builds the task-owned package and its content-free persisted subject, when context is required."
  @spec prepare(Scope.t(), Task.t(), ExecutionIntent.t() | Operation.t()) ::
          {:ok, nil | %{package: Package.t(), subject: map() | nil}} | {:error, atom()}
  def prepare(%Scope{} = scope, %Task{} = task, intent_or_operation) do
    with {:ok, policy} <- Policy.new(task.context_policy) do
      case policy.scope do
        :none -> {:ok, nil}
        _scope -> prepare_context(scope, task, intent_or_operation)
      end
    end
  end

  @spec current?(Scope.t(), Task.t(), SubjectRef.t(), String.t()) ::
          :ok | {:error, :stale_context | atom()}
  def current?(%Scope{} = scope, %Task{} = task, %SubjectRef{} = subject_ref, expected_hash)
      when is_binary(expected_hash) do
    case build_context(scope, task, subject_ref) do
      {:ok, %Package{hash: ^expected_hash}} -> :ok
      {:ok, %Package{}} -> {:error, :stale_context}
      {:error, reason} -> {:error, reason}
    end
  end

  def current?(_scope, _task, _subject_ref, _expected_hash), do: {:error, :stale_context}

  @doc "Reauthorizes and verifies the context bound to a durable operation."
  @spec operation_current?(Scope.t(), Task.t(), Operation.t()) :: :ok | {:error, atom()}
  def operation_current?(%Scope{}, %Task{}, %Operation{context_hash: nil, context_manifest: nil, context_subject: nil}),
    do: :ok

  def operation_current?(%Scope{} = scope, %Task{} = task, %Operation{
        context_hash: hash,
        context_manifest: %{},
        context_subject: %{} = persisted
      })
      when is_binary(hash) do
    with {:ok, subject_ref} <- SubjectRef.from_persisted_map(persisted) do
      current?(scope, task, subject_ref, hash)
    end
  end

  def operation_current?(
        %Scope{},
        %Task{} = task,
        %Operation{context_hash: hash, context_manifest: %{}, context_subject: nil} = operation
      )
      when is_binary(hash) do
    if Task.subject_current?(task, operation), do: :ok, else: {:error, :stale_context}
  end

  def operation_current?(_scope, _task, _operation), do: {:error, :stale_context}

  defp authorize_project(scope, subject_ref) do
    case Projects.get_project(scope, subject_ref.project_id) do
      {:ok, %{workspace_id: workspace_id} = project, membership}
      when workspace_id == subject_ref.workspace_id ->
        {:ok, project, membership}

      {:ok, _project, _membership} ->
        {:error, :unauthorized_context}

      {:error, _reason} ->
        {:error, :unauthorized_context}
    end
  end

  defp contextual_policy(%Policy{scope: :none}), do: {:error, :context_not_required}
  defp contextual_policy(%Policy{}), do: :ok

  defp matching_scope(%Policy{scope: scope}, %SubjectRef{kind: scope}), do: :ok
  defp matching_scope(_policy, _subject_ref), do: {:error, :context_scope_mismatch}

  defp builder(:dialogue), do: Storyarn.AI.Context.Builders.Dialogue
  defp builder(:flow_neighborhood), do: Storyarn.AI.Context.Builders.FlowNeighborhood
  defp builder(:sheet), do: Storyarn.AI.Context.Builders.Sheet
  defp builder(:structural_finding), do: Storyarn.AI.Context.Builders.StructuralFinding

  defp prepare_context(scope, task, intent_or_operation) do
    with {:ok, subject_ref} <- Task.context_subject(task, intent_or_operation),
         {:ok, package} <- build_context(scope, task, subject_ref) do
      {:ok,
       %{
         package: package,
         subject: persistable_subject(subject_ref)
       }}
    end
  end

  defp persistable_subject(subject_ref) do
    case SubjectRef.persisted_map(subject_ref) do
      {:ok, persisted} -> persisted
      {:error, :context_subject_not_persistable} -> nil
    end
  end

  defp emit_telemetry(task, result, started) do
    duration = System.monotonic_time() - started

    {measurements, metadata} =
      case result do
        {:ok, package} ->
          {
            %{
              duration: duration,
              serialized_bytes: package.serialized_bytes,
              included_count: length(package.manifest.included),
              excluded_count: length(package.manifest.excluded),
              truncated: if("optional_context_truncated" in package.warnings, do: 1, else: 0)
            },
            %{
              task_id: task.id,
              status: "ok",
              context_version: task.context_version,
              context_scope: Atom.to_string(package.scope),
              builder_version: package.version,
              context_hash: package.hash
            }
          }

        {:error, reason} ->
          {
            %{duration: duration},
            %{
              task_id: task.id,
              status: "error",
              context_version: task.context_version,
              context_scope: context_scope(task),
              error_classification: Atom.to_string(reason)
            }
          }
      end

    Telemetry.emit([:context, :build], measurements, metadata)
  end

  defp context_scope(%Task{} = task) do
    case Policy.new(task.context_policy) do
      {:ok, %Policy{scope: scope}} -> Atom.to_string(scope)
      {:error, :invalid_context_policy} -> "invalid"
    end
  end
end

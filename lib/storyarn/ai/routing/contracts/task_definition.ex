defmodule Storyarn.AI.TaskDefinition do
  @moduledoc "Behaviour implemented by every registered AI task."

  alias Storyarn.AI.Context.Entity
  alias Storyarn.AI.Context.Policy
  alias Storyarn.AI.Context.SubjectRef
  alias Storyarn.AI.ExecutionIntent
  alias Storyarn.AI.Operation

  @doc """
  Returns the task's deploy-sensitive contract without taking database locks.

  The registry rebuilds tasks after an Operation row may already be locked.
  `definition/0`, including any zero-arity `enabled?` function it returns, must
  therefore remain lock-free and must not call Workspace, Project, membership,
  policy or other upstream authorization code.
  """
  @callback definition() :: map()

  @doc """
  Resolves the consumer context contract without taking database locks.

  Like `definition/0`, this callback runs while the registry rebuilds a task
  and may therefore execute after an Operation has already been locked.
  """
  @callback context_contract(map()) :: module() | nil
  @callback validate_input(map() | list()) :: :ok | {:error, atom()}
  @callback validate_output(term()) :: :ok | {:error, atom()}

  @doc """
  Declares that the complete task definition is safe after a durable row lock.

  The registry can rebuild `definition/0` and evaluate its `enabled?` value
  after locking an Operation or RouteOption. AI also rechecks
  `authorize_subject/3` and `subject_current?/1`, while contextual tasks can
  rebuild evidence through `build_context/4`. Every registered task must return
  `:lock_free`: these callbacks may perform ordinary snapshot reads, but must
  never acquire database locks or call back into Workspace, Project,
  membership, or AI-policy authorization. The declaration also covers every
  callback on the `Storyarn.AI.Context.Contract` module returned by
  `context_contract/1`. `acquire_source_locks/1` is the only consumer callback
  allowed to lock domain evidence.
  """
  @callback post_operation_authorization_mode() :: :lock_free

  @callback authorize_subject(ExecutionIntent.scope(), ExecutionIntent.t() | Operation.t(), :execute | :apply | :attach) ::
              :ok | {:error, atom()}
  @callback subject_current?(Operation.t()) :: boolean()
  @callback context_subject(ExecutionIntent.t() | Operation.t()) ::
              {:ok, SubjectRef.t()} | {:error, atom()}
  @callback build_context(map(), SubjectRef.t(), Policy.t(), Entity.builder()) ::
              {:ok, map()} | {:error, atom()}
  @callback acquire_source_locks(Operation.t()) :: :ok | {:error, :stale_context}

  @optional_callbacks validate_input: 1,
                      validate_output: 1,
                      authorize_subject: 3,
                      subject_current?: 1,
                      context_contract: 1,
                      context_subject: 1,
                      build_context: 4,
                      acquire_source_locks: 1
end

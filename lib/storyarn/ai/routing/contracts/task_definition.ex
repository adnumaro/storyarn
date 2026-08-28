defmodule Storyarn.AI.TaskDefinition do
  @moduledoc "Behaviour implemented by every registered AI task."

  alias Storyarn.AI.Context.Entity
  alias Storyarn.AI.Context.Policy
  alias Storyarn.AI.Context.SubjectRef
  alias Storyarn.AI.ExecutionIntent
  alias Storyarn.AI.Operation

  @callback definition() :: map()
  @callback context_contract(map()) :: module() | nil
  @callback validate_input(map() | list()) :: :ok | {:error, atom()}
  @callback validate_output(term()) :: :ok | {:error, atom()}
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

defmodule Storyarn.AI.Context.Contract do
  @moduledoc """
  Consumer-owned contract for deterministic AI context.

  The AI kernel owns the bounded envelope and execution plumbing. Each bounded
  context owns the vocabulary accepted inside that envelope: scopes, selectable
  subjects, field groups and source types.
  """

  alias Storyarn.AI.Context.Policy
  alias Storyarn.AI.Context.SubjectRef

  @type source_location :: :included | :excluded

  @callback validate_policy(Policy.t()) :: :ok | {:error, :invalid_context_policy}
  @callback validate_subject(SubjectRef.t()) :: :ok | {:error, :invalid_context_subject}
  @callback subject_matches_policy?(SubjectRef.t(), Policy.t()) :: boolean()
  @callback persisted_subject(SubjectRef.t()) ::
              {:ok, map()} | {:error, :context_subject_not_persistable}
  @callback restore_subject(map()) :: {:ok, SubjectRef.t()} | {:error, :invalid_context_subject}
  @callback source_type?(String.t(), source_location()) :: boolean()

  @required_callbacks [
    validate_policy: 1,
    validate_subject: 1,
    subject_matches_policy?: 2,
    persisted_subject: 1,
    restore_subject: 1,
    source_type?: 2
  ]

  @spec valid?(term()) :: boolean()
  def valid?(module) when is_atom(module) do
    Code.ensure_loaded?(module) and
      Enum.all?(@required_callbacks, fn {function, arity} ->
        function_exported?(module, function, arity)
      end)
  end

  def valid?(_module), do: false
end

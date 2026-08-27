defmodule Storyarn.AI.Context do
  @moduledoc """
  Public capability boundary for deterministic AI context construction.

  Consumers provide their typed context contract and subject selection. The
  capability authorizes that selection, builds the bounded package and checks
  whether persisted operation context is still current.
  """

  alias Storyarn.AI.Context.Execution.Builder
  alias Storyarn.AI.Context.PersistenceContract

  defdelegate build_context(scope, task, subject_ref), to: Builder
  defdelegate prepare(scope, task, intent_or_operation), to: Builder
  defdelegate current?(scope, task, subject_ref, expected_hash), to: Builder
  defdelegate operation_current?(scope, task, operation), to: Builder

  @doc false
  defdelegate valid_persisted_context?(task_id, hash, manifest, subject),
    to: PersistenceContract,
    as: :valid?
end

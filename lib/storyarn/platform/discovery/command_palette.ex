defmodule Storyarn.Platform.CommandPalette do
  @moduledoc """
  Public boundary for command-palette metadata and durable mutations.

  The generated operation catalog is read-only metadata. Successful mutation
  results are stored in the same database transaction as the mutation.
  Replaying an execution ID after a LiveView reconnect therefore returns the
  original result instead of creating or deleting twice.
  """

  alias Storyarn.Accounts.Scope
  alias Storyarn.Platform.CommandPalette.Commands
  alias Storyarn.Platform.CommandPalette.Definition
  alias Storyarn.Platform.CommandPalette.Queries
  alias Storyarn.Platform.CommandPalette.RateLimits

  @type reply :: %{optional(:url) => String.t(), optional(:deleted) => boolean(), optional(:error) => String.t()}
  @type parameter_completion :: %{
          required(:mode) => Definition.completion_mode(),
          required(:source) => Definition.completion_source()
        }

  @doc "Returns the JSON-safe catalog consumed by the guided command palette."
  @spec operation_catalog() :: [map()]
  defdelegate operation_catalog(), to: Queries

  @doc "Resolves one registered parameter's completion contract without atomizing client input."
  @spec parameter_completion(String.t(), String.t()) :: {:ok, parameter_completion()} | :error
  defdelegate parameter_completion(operation_id, parameter_id), to: Queries

  @doc "Returns whether an id belongs to a registered command-palette operation."
  @spec registered_operation_id?(term()) :: boolean()
  defdelegate registered_operation_id?(operation_id), to: Queries

  @doc "Applies the command palette's consumer-owned deep-search rate limit."
  defdelegate check_deep_search_rate(user_id, limit \\ 12), to: RateLimits, as: :check_deep_search

  @doc """
  Runs a palette mutation once per actor/event/execution ID.

  The callback returns the client reply and optional post-commit metadata.
  Metadata is deliberately not persisted: cached replays return `nil`, which
  prevents duplicate PubSub broadcasts while still returning the same reply.
  """
  @spec run(Scope.t(), String.t(), String.t(), (-> {reply(), term()}), (term() -> reply())) ::
          {reply(), term() | nil}
  defdelegate run(scope, event, execution_id, operation, error_reply), to: Commands
end

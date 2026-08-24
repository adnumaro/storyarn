defmodule Storyarn.Platform.CommandPalette do
  @moduledoc """
  Public boundary for command-palette metadata and durable mutations.

  The generated operation catalog is read-only metadata. Successful mutation
  results are stored in the same database transaction as the mutation.
  Replaying an execution ID after a LiveView reconnect therefore returns the
  original result instead of creating or deleting twice.
  """

  import Ecto.Query

  alias Storyarn.Accounts.Scope
  alias Storyarn.Platform.CommandPalette.Definition
  alias Storyarn.Platform.CommandPalette.Operation
  alias Storyarn.Platform.CommandPalette.Registry
  alias Storyarn.Repo

  @events Operation.events()
  @lock_namespace 981_003
  @max_lock_key 2_147_483_647
  @retained_results 64

  @type reply :: %{optional(:url) => String.t(), optional(:deleted) => boolean(), optional(:error) => String.t()}
  @type parameter_completion :: %{
          required(:mode) => Definition.completion_mode(),
          required(:source) => Definition.completion_source()
        }

  @doc "Returns the JSON-safe catalog consumed by the guided command palette."
  @spec operation_catalog() :: [map()]
  def operation_catalog, do: Registry.catalog()

  @doc "Resolves one registered parameter's completion contract without atomizing client input."
  @spec parameter_completion(String.t(), String.t()) :: {:ok, parameter_completion()} | :error
  def parameter_completion(operation_id, parameter_id) do
    with {:ok, parameter} <- Registry.fetch_parameter(operation_id, parameter_id) do
      {:ok, %{mode: parameter.completion_mode, source: parameter.completion_source}}
    end
  end

  @doc "Returns whether an id belongs to a registered command-palette operation."
  @spec registered_operation_id?(term()) :: boolean()
  def registered_operation_id?(operation_id) do
    match?({:ok, _definition}, Registry.fetch(operation_id))
  end

  @doc """
  Runs a palette mutation once per actor/event/execution ID.

  The callback returns the client reply and optional post-commit metadata.
  Metadata is deliberately not persisted: cached replays return `nil`, which
  prevents duplicate PubSub broadcasts while still returning the same reply.
  """
  @spec run(Scope.t(), String.t(), String.t(), (-> {reply(), term()}), (term() -> reply())) ::
          {reply(), term() | nil}
  def run(%{user: %{id: user_id}}, event, execution_id, operation, error_reply)
      when event in @events and is_binary(execution_id) and is_function(operation, 0) and is_function(error_reply, 1) do
    user_id
    |> transact_once(event, execution_id, operation)
    |> resolve_transaction(error_reply)
  end

  defp transact_once(user_id, event, execution_id, operation) do
    Repo.transaction(fn ->
      lock_actor!(user_id)

      Operation
      |> Repo.get_by(user_id: user_id, event: event, operation_id: execution_id)
      |> replay_or_execute(user_id, event, execution_id, operation)
    end)
  end

  defp replay_or_execute(nil, user_id, event, execution_id, operation) do
    {reply, metadata} = operation.()
    persist_success_or_rollback(user_id, event, execution_id, reply, metadata)
  end

  defp replay_or_execute(%Operation{} = stored, _user_id, _event, _execution_id, _operation) do
    {decode_result(stored.result), nil}
  end

  defp persist_success_or_rollback(user_id, event, execution_id, reply, metadata) do
    if successful_reply?(reply) do
      store_result!(user_id, event, execution_id, reply)
      {reply, metadata}
    else
      Repo.rollback({:palette_reply, reply})
    end
  end

  defp resolve_transaction({:ok, result}, _error_reply), do: result
  defp resolve_transaction({:error, {:palette_reply, reply}}, _error_reply), do: {reply, nil}
  defp resolve_transaction({:error, reason}, error_reply), do: {error_reply.(reason), nil}

  defp store_result!(user_id, event, execution_id, reply) do
    %Operation{user_id: user_id}
    |> Operation.changeset(%{
      event: event,
      operation_id: execution_id,
      result: reply
    })
    |> Repo.insert!()

    prune_actor_results(user_id)
    :ok
  end

  defp successful_reply?(%{url: url}) when is_binary(url), do: true
  defp successful_reply?(%{deleted: true}), do: true
  defp successful_reply?(_reply), do: false

  defp decode_result(%{"url" => url}) when is_binary(url), do: %{url: url}
  defp decode_result(%{"deleted" => true}), do: %{deleted: true}

  defp prune_actor_results(user_id) do
    stale_ids =
      Repo.all(
        from(operation in Operation,
          where: operation.user_id == ^user_id,
          order_by: [desc: operation.inserted_at, desc: operation.id],
          offset: ^@retained_results,
          select: operation.id
        )
      )

    if stale_ids != [] do
      Repo.delete_all(from(operation in Operation, where: operation.id in ^stale_ids))
    end
  end

  defp lock_actor!(user_id) do
    Repo.query!("SELECT pg_advisory_xact_lock($1, $2)", [
      @lock_namespace,
      :erlang.phash2(user_id, @max_lock_key)
    ])

    :ok
  end
end

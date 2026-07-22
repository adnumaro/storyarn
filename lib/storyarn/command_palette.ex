defmodule Storyarn.CommandPalette do
  @moduledoc """
  Durable execution boundary for mutating command-palette operations.

  Successful results are stored in the same database transaction as the
  mutation. Replaying an operation ID after a LiveView reconnect therefore
  returns the original result instead of creating or deleting twice.
  """

  import Ecto.Query

  alias Storyarn.Accounts.Scope
  alias Storyarn.CommandPalette.Operation
  alias Storyarn.Repo

  @events Operation.events()
  @lock_namespace 981_003
  @max_lock_key 2_147_483_647
  @retained_results 64

  @type reply :: %{optional(:url) => String.t(), optional(:deleted) => boolean(), optional(:error) => String.t()}

  @doc """
  Runs a palette mutation once per actor/event/operation ID.

  The callback returns the client reply and optional post-commit metadata.
  Metadata is deliberately not persisted: cached replays return `nil`, which
  prevents duplicate PubSub broadcasts while still returning the same reply.
  """
  @spec run(Scope.t(), String.t(), String.t(), (-> {reply(), term()}), (term() -> reply())) ::
          {reply(), term() | nil}
  def run(%Scope{user: %{id: user_id}}, event, operation_id, operation, error_reply)
      when event in @events and is_binary(operation_id) and is_function(operation, 0) and is_function(error_reply, 1) do
    user_id
    |> transact_once(event, operation_id, operation)
    |> resolve_transaction(error_reply)
  end

  defp transact_once(user_id, event, operation_id, operation) do
    Repo.transaction(fn ->
      lock_actor!(user_id)

      Operation
      |> Repo.get_by(user_id: user_id, event: event, operation_id: operation_id)
      |> replay_or_execute(user_id, event, operation_id, operation)
    end)
  end

  defp replay_or_execute(nil, user_id, event, operation_id, operation) do
    {reply, metadata} = operation.()
    persist_success_or_rollback(user_id, event, operation_id, reply, metadata)
  end

  defp replay_or_execute(%Operation{} = stored, _user_id, _event, _operation_id, _operation) do
    {decode_result(stored.result), nil}
  end

  defp persist_success_or_rollback(user_id, event, operation_id, reply, metadata) do
    if successful_reply?(reply) do
      store_result!(user_id, event, operation_id, reply)
      {reply, metadata}
    else
      Repo.rollback({:palette_reply, reply})
    end
  end

  defp resolve_transaction({:ok, result}, _error_reply), do: result
  defp resolve_transaction({:error, {:palette_reply, reply}}, _error_reply), do: {reply, nil}
  defp resolve_transaction({:error, reason}, error_reply), do: {error_reply.(reason), nil}

  defp store_result!(user_id, event, operation_id, reply) do
    %Operation{user_id: user_id}
    |> Operation.changeset(%{
      event: event,
      operation_id: operation_id,
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

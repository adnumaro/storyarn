defmodule Storyarn.AI.Results do
  @moduledoc "Actor-private result reads, view stamping, disposition and authorized apply boundary."

  import Ecto.Query

  alias Storyarn.Accounts.Scope
  alias Storyarn.AI.Context
  alias Storyarn.AI.Context.SourceLocks
  alias Storyarn.AI.ExecutionRoute
  alias Storyarn.AI.Operation
  alias Storyarn.AI.PersonalConsents
  alias Storyarn.AI.PolicyDecision
  alias Storyarn.AI.Result
  alias Storyarn.AI.Task
  alias Storyarn.AI.TaskRegistry
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers

  @default_expiration_batch_size 100

  @spec get_operation(Scope.t(), pos_integer()) :: Operation.t() | nil
  def get_operation(%Scope{user: %{id: actor_id}}, operation_id) do
    Repo.one(from(operation in Operation, where: operation.id == ^operation_id and operation.actor_id == ^actor_id))
  end

  @spec get(Scope.t(), pos_integer()) :: {:ok, map() | list(), Operation.t()} | {:error, atom()}
  def get(%Scope{user: %{id: actor_id}}, operation_id) do
    now = TimeHelpers.now()

    row =
      Repo.one(
        from(operation in Operation,
          join: result in Result,
          on: result.operation_id == operation.id,
          where:
            operation.id == ^operation_id and operation.actor_id == ^actor_id and
              operation.execution_status == "succeeded" and result.expires_at > ^now and
              not is_nil(result.output_encrypted),
          select: {operation, result.output_encrypted}
        )
      )

    decode_row(row)
  end

  defp decode_row({%Operation{} = operation, output}) do
    case Jason.decode(output) do
      {:ok, decoded} -> {:ok, decoded, operation}
      {:error, _reason} -> {:error, :invalid_result}
    end
  end

  defp decode_row(nil), do: {:error, :not_found}

  @doc """
  Reads a still-readable result by the idempotency key that produced it.

  Lets a surface that forgot its operation id recover the result the actor
  already paid for, instead of offering to buy the same thing twice. Covered by
  `ai_operations_actor_task_idempotency_unique`, so it is one index lookup.
  """
  @spec get_by_idempotency_key(Scope.t(), String.t(), String.t()) ::
          {:ok, map() | list(), Operation.t()} | {:error, atom()}
  def get_by_idempotency_key(%Scope{user: %{id: actor_id}}, task_id, idempotency_key)
      when is_binary(task_id) and is_binary(idempotency_key) do
    now = TimeHelpers.now()

    row =
      Repo.one(
        from(operation in Operation,
          join: result in Result,
          on: result.operation_id == operation.id,
          where:
            operation.actor_id == ^actor_id and operation.task_id == ^task_id and
              operation.idempotency_key == ^idempotency_key and
              operation.execution_status == "succeeded" and result.expires_at > ^now and
              not is_nil(result.output_encrypted),
          select: {operation, result.output_encrypted}
        )
      )

    decode_row(row)
  end

  @doc """
  Every operation of this actor that spent one of `idempotency_keys`, keyed by key.

  A key is consumed permanently by the first operation that used it, even after
  that operation stops being readable — cancelled, expired, or failed — because
  `Execution.execute/1` replays the row rather than creating anything. So a caller
  choosing which key to spend next needs each row's STATUS, not merely its
  existence: still in flight means "attach to it", terminal-and-unreadable means
  "this key can never produce anything again", and absent means "free to spend".

  One query rather than one per candidate key, because such a caller has to
  consider ALL of them: an attempt that never spent its key — an abandoned
  preflight, or a route blocked before it could create anything — leaves a gap
  that must not hide a paid result above it.
  """
  @spec operations_by_idempotency_keys(Scope.t(), String.t(), [String.t()]) ::
          %{String.t() => Operation.t()}
  def operations_by_idempotency_keys(%Scope{user: %{id: actor_id}}, task_id, idempotency_keys)
      when is_binary(task_id) and is_list(idempotency_keys) do
    from(operation in Operation,
      where:
        operation.actor_id == ^actor_id and
          operation.task_id == ^task_id and
          operation.idempotency_key in ^idempotency_keys
    )
    |> Repo.all()
    |> Map.new(&{&1.idempotency_key, &1})
  end

  @doc """
  Records that the actor saw this result.

  The slice contract asks for `viewed`, never `accepted`, so this is deliberately
  NOT a disposition: it leaves `user_disposition` nil, which keeps dismiss, apply
  and expiry-abandonment reachable. Idempotent and silent — a surface rendering a
  result must not fail because the stamp could not be written.
  """
  @spec record_view(Scope.t(), pos_integer()) :: :ok
  def record_view(%Scope{user: %{id: actor_id}}, operation_id) do
    case Repo.one(
           from(operation in Operation,
             where:
               operation.id == ^operation_id and operation.actor_id == ^actor_id and
                 operation.execution_status == "succeeded" and is_nil(operation.viewed_at)
           )
         ) do
      %Operation{} = operation ->
        operation |> Operation.viewed_changeset() |> Repo.update()
        :ok

      nil ->
        :ok
    end
  end

  @spec dismiss(Scope.t(), pos_integer()) :: {:ok, Operation.t()} | {:error, atom()}
  def dismiss(%Scope{user: %{id: actor_id}}, operation_id) do
    Repo.transaction(fn ->
      operation = lock_actor_operation(operation_id, actor_id)

      case operation do
        %Operation{execution_status: "succeeded", user_disposition: nil} ->
          dismissed = operation |> Operation.disposition_changeset("dismissed") |> Repo.update!()
          delete_result(operation.id)
          dismissed

        nil ->
          Repo.rollback(:not_found)

        %Operation{user_disposition: disposition} when not is_nil(disposition) ->
          Repo.rollback(:already_decided)

        _operation ->
          Repo.rollback(:not_succeeded)
      end
    end)
  end

  @doc """
  Reauthorizes and applies a temporary result through a feature-owned mutation.

  `current_revision` must be read by the server-side feature immediately before
  this call. Context roots and source rows are locked before the final staleness
  check. The callback runs while those locks remain held in the same database
  transaction and receives decoded output plus content-free provenance.
  """
  @spec apply(Scope.t(), pos_integer(), String.t() | nil, (term(), map() -> {:ok, term()} | {:error, term()})) ::
          {:ok, term()} | {:error, term()}
  def apply(%Scope{user: %{id: actor_id}} = scope, operation_id, current_revision, apply_fun)
      when is_function(apply_fun, 2) do
    Repo.transaction(fn ->
      operation = lock_actor_operation(operation_id, actor_id)

      with %Operation{execution_status: "succeeded", user_disposition: nil} <- operation,
           :ok <- revision_matches(operation, current_revision),
           {:ok, task} <- TaskRegistry.get(operation.task_id),
           :ok <- task_contract_current(operation, task),
           {:ok, _decision} <- PolicyDecision.reauthorize(operation, task, :apply, lock_policy: true),
           :ok <- SourceLocks.acquire(operation),
           :ok <- Context.operation_current?(scope, task, operation),
           {:ok, route} <- ExecutionRoute.from_map(operation.execution_route),
           :ok <- PersonalConsents.authorize_operation(operation, task, route, lock: true),
           %Result{} = result <- lock_result(operation.id),
           true <- DateTime.after?(result.expires_at, TimeHelpers.now()),
           {:ok, output} <- Jason.decode(result.output_encrypted),
           {:ok, applied} <- apply_fun.(output, provenance(operation)) do
        operation |> Operation.disposition_changeset("accepted") |> Repo.update!()
        Repo.delete!(result)
        applied
      else
        nil -> Repo.rollback(:not_found)
        false -> Repo.rollback(:expired)
        %Operation{user_disposition: disposition} when not is_nil(disposition) -> Repo.rollback(:already_decided)
        %Operation{} -> Repo.rollback(:not_succeeded)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @spec expire(DateTime.t(), keyword()) ::
          {:ok, %{expired_count: non_neg_integer(), failure_count: non_neg_integer(), more?: boolean()}}
  def expire(now \\ TimeHelpers.now(), opts \\ []) do
    batch_size = Keyword.get(opts, :batch_size, @default_expiration_batch_size)

    ids =
      Repo.all(
        from(result in Result,
          where: not is_nil(result.expires_at) and result.expires_at <= ^now,
          order_by: [asc: result.expires_at, asc: result.id],
          limit: ^(batch_size + 1),
          select: result.operation_id
        )
      )

    {batch, overflow} = Enum.split(ids, batch_size)

    summary =
      Enum.reduce(batch, %{expired_count: 0, failure_count: 0, more?: overflow != []}, fn operation_id, acc ->
        case expire_one(operation_id, now) do
          :ok -> Map.update!(acc, :expired_count, &(&1 + 1))
          :missing -> acc
          {:error, _reason} -> Map.update!(acc, :failure_count, &(&1 + 1))
        end
      end)

    {:ok, summary}
  end

  @spec purge_project(pos_integer()) :: non_neg_integer()
  def purge_project(project_id) do
    {count, _} = Repo.delete_all(from(result in Result, where: result.project_id == ^project_id))
    count
  end

  defp expire_one(operation_id, now) do
    fn -> expire_locked(operation_id, now) end
    |> Repo.transaction()
    |> case do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  defp expire_locked(operation_id, now) do
    operation = lock_operation(operation_id)
    result = Repo.one(from(result in Result, where: result.operation_id == ^operation_id, lock: "FOR UPDATE"))

    if result && result.expires_at && DateTime.compare(result.expires_at, now) != :gt do
      maybe_abandon(operation)
      Repo.delete!(result)
      :ok
    else
      :missing
    end
  end

  defp maybe_abandon(%Operation{execution_status: "succeeded", user_disposition: nil} = operation) do
    operation |> Operation.disposition_changeset("abandoned") |> Repo.update!()
  end

  defp maybe_abandon(%Operation{}), do: :ok

  defp revision_matches(%Operation{subject_revision: nil}, nil), do: :ok
  defp revision_matches(%Operation{subject_revision: revision}, revision), do: :ok
  defp revision_matches(_operation, _revision), do: {:error, :stale_subject}

  defp task_contract_current(operation, task) do
    if operation.task_contract_hash == Task.contract_hash(task),
      do: :ok,
      else: {:error, :task_contract_changed}
  end

  defp provenance(operation) do
    %{
      operation_id: operation.id,
      actor_id: operation.actor_id,
      task_id: operation.task_id,
      capability: operation.capability,
      input_hash: operation.input_hash,
      input_schema_version: operation.input_schema_version,
      output_schema_version: operation.output_schema_version,
      prompt_version: operation.prompt_version,
      context_version: operation.context_version,
      context_hash: operation.context_hash,
      context_manifest: operation.context_manifest,
      route: Map.take(operation.execution_route, ~w(lane provider model price_id price_version))
    }
  end

  defp lock_actor_operation(operation_id, actor_id) do
    Repo.one(
      from(operation in Operation,
        where: operation.id == ^operation_id and operation.actor_id == ^actor_id,
        lock: "FOR UPDATE"
      )
    )
  end

  defp lock_operation(operation_id) do
    Repo.one(from(operation in Operation, where: operation.id == ^operation_id, lock: "FOR UPDATE"))
  end

  defp lock_result(operation_id) do
    Repo.one(from(result in Result, where: result.operation_id == ^operation_id, lock: "FOR UPDATE"))
  end

  defp delete_result(operation_id) do
    Repo.delete_all(from(result in Result, where: result.operation_id == ^operation_id))
  end
end

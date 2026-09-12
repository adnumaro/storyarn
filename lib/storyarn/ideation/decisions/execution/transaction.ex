defmodule Storyarn.Ideation.Decisions.Execution.Transaction do
  @moduledoc false
  import Ecto.Query

  alias Storyarn.Ideation.Decisions.Decision
  alias Storyarn.Ideation.Decisions.Events.Invalidation
  alias Storyarn.Ideation.Decisions.Execution.Mutation
  alias Storyarn.Ideation.Decisions.Queries.Catalog
  alias Storyarn.Ideation.Decisions.Revision
  alias Storyarn.Ideation.Decisions.Rules.Input
  alias Storyarn.Ideation.Sessions
  alias Storyarn.Repo

  def run(scope, project_id, session_id, command) do
    if Repo.in_transaction?() do
      {:error, :decision_requires_outer_transaction}
    else
      fn -> locked(scope, project_id, session_id, command) end
      |> Repo.transact()
      |> complete(scope, project_id, session_id)
    end
  end

  defp locked(scope, project_id, session_id, command) do
    with {:ok, access} <- Sessions.lock_for_contribution(scope, project_id, session_id),
         false <- access.configuration.private_mode,
         {:ok, receipt} <- receipt(access, command.key),
         {:ok, decision} <- locate(access, command.id, receipt) do
      identity = if decision, do: decision.recovery_identity

      fingerprint =
        Input.fingerprint(command.operation, access.session_identity, identity, command.version, command.attrs)

      execute(scope, project_id, access, decision, receipt, command, fingerprint)
    else
      true -> {:error, :private_mode}
      {:error, _} = error -> error
    end
  end

  defp receipt(access, key) do
    current =
      Repo.one(
        from r in Revision,
          where: r.session_id == ^access.session_id and r.actor_id == ^access.user_id and r.request_key == ^key,
          select: %{decision_id: r.decision_id, fingerprint: r.fingerprint}
      )

    if is_nil(current) and replaced_receipt?(access, key),
      do: {:error, :idempotency_conflict},
      else: {:ok, current}
  end

  defp replaced_receipt?(access, key) do
    # Restoring an older generation must not replay writes that recovery rolled
    # back. Retained receipts only fence the same logical session; never expose
    # their decision, content, or fingerprint through ordinary authorization.
    Repo.exists?(
      from r in Revision,
        join: s in subquery(Sessions.receipt_generations_query()),
        on: s.id == r.session_id,
        where:
          s.project_id == ^access.project_id and s.recovery_identity == ^access.session_identity and
            not is_nil(s.deleted_at) and r.actor_id == ^access.user_id and r.request_key == ^key
    )
  end

  defp locate(_access, nil, _receipt), do: {:ok, nil}

  defp locate(access, id, nil) do
    case Repo.get_by(Decision, id: id, session_id: access.session_id) do
      nil -> {:error, :not_found}
      decision -> {:ok, decision}
    end
  end

  defp locate(access, id, receipt) do
    # A retained generation may have the original numeric ID. Its stable
    # identity must still match the receipt's currently authorized decision.
    identity = Repo.one(from d in Decision, where: d.id == ^id, select: d.recovery_identity)
    decision = Repo.get_by(Decision, id: receipt.decision_id, session_id: access.session_id)

    if decision && decision.recovery_identity == identity,
      do: {:ok, decision},
      else: {:error, :idempotency_conflict}
  end

  defp execute(scope, project_id, access, decision, nil, command, fingerprint) do
    with {:ok, decision} <- Mutation.run(scope, project_id, access, decision, command, fingerprint) do
      {:ok, {decision.id, true}}
    end
  end

  defp execute(_scope, _project_id, _access, _decision, %{fingerprint: fingerprint} = receipt, _command, fingerprint),
    do: {:ok, {receipt.decision_id, false}}

  defp execute(_, _, _, _, _, _, _), do: {:error, :idempotency_conflict}

  defp complete({:ok, {id, changed?}}, scope, project_id, session_id) do
    if changed?, do: Invalidation.broadcast(project_id, session_id)
    Catalog.get(scope, project_id, session_id, id)
  end

  defp complete({:error, _} = error, _, _, _), do: error
end

defmodule Storyarn.Ideation.References.ContextualSession do
  @moduledoc false
  import Ecto.Query
  import Storyarn.Ideation.References.Input, only: [valid_id: 1]

  alias Storyarn.Ideation.References.Catalog
  alias Storyarn.Ideation.References.ContextualCatalog
  alias Storyarn.Ideation.References.ContextualInput
  alias Storyarn.Ideation.References.Events.Invalidation
  alias Storyarn.Ideation.References.Mutation
  alias Storyarn.Ideation.References.Queries.Targets
  alias Storyarn.Ideation.References.Reference
  alias Storyarn.Ideation.References.Revision
  alias Storyarn.Ideation.References.View
  alias Storyarn.Ideation.Sessions
  alias Storyarn.Repo

  def create(scope, project_id, attrs), do: run(scope, project_id, nil, attrs, :create)

  def link(scope, project_id, session_id, attrs) when valid_id(session_id),
    do: run(scope, project_id, session_id, attrs, :link)

  def link(_, _, _, _), do: {:error, :not_found}

  defp run(scope, project_id, session_id, attrs, operation) do
    with false <- Repo.in_transaction?(),
         {:ok, attrs} <- ContextualInput.command(attrs, operation) do
      fingerprint = ContextualInput.fingerprint(attrs, operation, session_id)

      result = Repo.transact(fn -> run_locked(scope, project_id, session_id, attrs, fingerprint) end)

      complete(result, scope, project_id, operation)
    else
      true -> {:error, :reference_requires_outer_transaction}
      {:error, _} = error -> error
    end
  end

  defp run_locked(scope, project_id, session_id, attrs, fingerprint) do
    with {:ok, access} <- lock_access(scope, project_id, session_id) do
      case receipt(project_id, session_id, access.user_id, attrs.request_key) do
        {:ok, nil} -> execute(scope, project_id, session_id, access, attrs, fingerprint)
        {:ok, %{fingerprint: ^fingerprint} = receipt} -> replay(scope, project_id, receipt)
        {:ok, _} -> {:error, :idempotency_conflict}
        {:error, _} = error -> error
      end
    end
  end

  defp lock_access(scope, project_id, nil), do: Sessions.lock_contextual_creation(scope, project_id)
  defp lock_access(scope, project_id, session_id), do: Sessions.lock_for_contribution(scope, project_id, session_id)

  # Creation's origin revision is its durable receipt, already part of sealed
  # recovery. The exclusive Project lock serializes requests before a session exists.
  defp receipt(project_id, session_id, actor_id, key) do
    query =
      from(r in Revision,
        join: s in subquery(Sessions.contextual_receipt_sources_query()),
        on: s.id == r.session_id,
        where: s.project_id == ^project_id and r.actor_id == ^actor_id and r.request_key == ^key,
        order_by: [asc_nulls_first: s.deleted_at],
        limit: 2,
        select: %{
          session_id: r.session_id,
          reference_id: r.reference_id,
          fingerprint: r.fingerprint,
          deleted_at: s.deleted_at
        }
      )

    query = if session_id, do: where(query, [r], r.session_id == ^session_id), else: query
    select_receipt(Repo.all(query) ++ reuse_receipts(project_id, session_id, actor_id, key))
  end

  defp reuse_receipts(project_id, session_id, actor_id, key) do
    query =
      from(r in subquery(Sessions.contextual_link_receipts_query()),
        join: s in subquery(Sessions.contextual_receipt_sources_query()),
        on: s.id == r.session_id,
        where: s.project_id == ^project_id and r.actor_id == ^actor_id and r.request_key == ^key,
        order_by: [asc_nulls_first: s.deleted_at],
        limit: 2,
        select: %{
          session_id: r.session_id,
          reference_identity: r.reference_identity,
          fingerprint: r.fingerprint,
          deleted_at: s.deleted_at
        }
      )

    query = if session_id, do: where(query, [r], r.session_id == ^session_id), else: query

    query
    |> Repo.all()
    |> Enum.map(fn row ->
      %{row | fingerprint: Base.decode16!(row.fingerprint, case: :lower)}
    end)
  end

  defp select_receipt([]), do: {:ok, nil}

  defp select_receipt(receipts) do
    # Prefer the restored live generation. A receipt that exists only in recovery
    # trash rejects replay generically rather than recreating its former session.
    case Enum.filter(receipts, &is_nil(&1.deleted_at)) do
      [receipt] -> {:ok, receipt}
      [] -> {:error, :not_found}
      _ -> {:error, :idempotency_conflict}
    end
  end

  defp replay(scope, project_id, receipt) do
    with %Reference{deleted_at: nil, idea_id: nil} = reference <- receipt_reference(receipt),
         {:ok, target} <- Targets.get(scope, project_id, reference.target_type, reference.target_id),
         true <- View.available?(reference, target) do
      {:ok, {reference.session_id, reference.id, false}}
    else
      _ -> {:error, :not_found}
    end
  end

  defp receipt_reference(%{reference_id: id}), do: Repo.get(Reference, id)

  defp receipt_reference(%{session_id: session_id, reference_identity: identity}) do
    Repo.one(from(r in Reference, where: r.session_id == ^session_id and r.recovery_identity == ^identity))
  end

  defp execute(scope, project_id, nil, access, attrs, fingerprint) do
    with {:ok, target} <- consulted_target(scope, project_id, attrs),
         {:ok, session} <- Sessions.create_session(scope, project_id, attrs.session_attrs),
         {:ok, {reference, true}} <- insert(session.id, access.user_id, attrs, target, fingerprint),
         {:ok, _} <- consulted_target(scope, project_id, attrs) do
      {:ok, {session.id, reference.id, true}}
    end
  end

  defp execute(scope, project_id, session_id, access, attrs, fingerprint) do
    with {:ok, target} <- consulted_target(scope, project_id, attrs) do
      case ContextualCatalog.existing(project_id, session_id, target) do
        %Reference{} = reference ->
          reuse_reference(reference, access, attrs, fingerprint)

        nil ->
          link_new(scope, project_id, session_id, access.user_id, attrs, target, fingerprint)
      end
    end
  end

  defp reuse_reference(reference, access, attrs, fingerprint) do
    with {:ok, _} <-
           Sessions.record_contextual_link_receipt(
             access,
             attrs.request_key,
             fingerprint,
             reference.recovery_identity
           ) do
      {:ok, {access.session_id, reference.id, :session}}
    end
  end

  defp link_new(scope, project_id, session_id, actor_id, attrs, target, fingerprint) do
    with count when count < 100 <- Repo.aggregate(Catalog.session_query(session_id, nil), :count),
         {:ok, {reference, true}} <- insert(session_id, actor_id, attrs, target, fingerprint),
         {:ok, _} <- consulted_target(scope, project_id, attrs) do
      {:ok, {session_id, reference.id, true}}
    else
      count when is_integer(count) -> {:error, :reference_limit}
      {:error, _} = error -> error
    end
  end

  defp insert(session_id, actor_id, attrs, target, fingerprint) do
    Mutation.insert_locked(
      session_id,
      nil,
      actor_id,
      Map.put(attrs, :relation, "origin"),
      target,
      attrs.request_key,
      fingerprint
    )
  end

  defp consulted_target(scope, project_id, attrs) do
    with {:ok, target} <- Targets.get(scope, project_id, attrs.target_type, attrs.target_id),
         true <- target.identity == attrs.target_identity do
      if target.fingerprint == attrs.target_fingerprint, do: {:ok, target}, else: {:error, :stale_context}
    else
      _ -> {:error, :not_found}
    end
  end

  defp complete({:ok, {session_id, reference_id, changed}}, scope, project_id, operation) do
    if changed do
      Invalidation.broadcast(project_id, session_id)

      if operation == :create or changed == :session,
        do: Sessions.notify_contextual_session({:ok, session_id}, project_id)
    end

    with {:ok, session} <- Sessions.get_session(scope, project_id, session_id),
         {:ok, reference} <- Catalog.get(scope, project_id, session_id, nil, reference_id) do
      {:ok, %{session: session, reference: reference}}
    end
  end

  defp complete({:error, _} = error, _, _, _), do: error
end

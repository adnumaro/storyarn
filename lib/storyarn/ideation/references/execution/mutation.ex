defmodule Storyarn.Ideation.References.Mutation do
  @moduledoc false
  import Ecto.Query
  import Storyarn.Ideation.References.Input, only: [valid_id: 1, valid_version: 1]

  alias Storyarn.Ideation.Ideas
  alias Storyarn.Ideation.References.Catalog
  alias Storyarn.Ideation.References.Events.Invalidation
  alias Storyarn.Ideation.References.Input
  alias Storyarn.Ideation.References.Queries.Targets
  alias Storyarn.Ideation.References.Reference
  alias Storyarn.Ideation.References.Revision
  alias Storyarn.Ideation.References.View
  alias Storyarn.Ideation.Sessions
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Repo

  def add(scope, project_id, session_id, idea_id, attrs) do
    with {:ok, attrs} <- Input.create(attrs) do
      command = %{
        operation: "create",
        id: nil,
        version: nil,
        key: attrs.request_key,
        attrs: Map.delete(attrs, :request_key)
      }

      run(scope, project_id, session_id, idea_id, command)
    end
  end

  def change(scope, project_id, session_id, idea_id, id, version, key, operation)
      when valid_id(id) and valid_version(version) and operation in ["refresh", "remove"] do
    with {:ok, key} <- Input.request_key(key) do
      run(scope, project_id, session_id, idea_id, %{
        operation: operation,
        id: id,
        version: version,
        key: key,
        attrs: %{}
      })
    end
  end

  def change(_, _, _, _, _, _, _, _), do: {:error, :invalid_reference}

  defp run(scope, project_id, session_id, idea_id, command) do
    if Repo.in_transaction?() do
      {:error, :reference_requires_outer_transaction}
    else
      result = Repo.transact(fn -> locked(scope, project_id, session_id, idea_id, command) end)
      committed(result, scope, project_id, session_id, idea_id, command.operation)
    end
  end

  defp committed({:ok, {reference, changed}}, scope, project_id, session_id, idea_id, operation) do
    if changed, do: Invalidation.broadcast(project_id, session_id)

    if operation == "remove",
      do: {:ok, %{id: reference.id, version: reference.version}},
      else: Catalog.get(scope, project_id, session_id, idea_id, reference.id)
  end

  defp committed({:error, _} = error, _, _, _, _, _), do: error

  defp locked(scope, project_id, session_id, idea_id, command) do
    with {:ok, access} <- Sessions.lock_for_contribution(scope, project_id, session_id),
         {:ok, _} <- Ideas.comment_source(scope, project_id, session_id, idea_id, lock: :share) do
      fingerprint = Input.fingerprint(command.operation, idea_id, command.id, command.version, command.attrs)

      receipt =
        Repo.one(
          from r in Revision,
            where: r.session_id == ^session_id and r.actor_id == ^access.user_id and r.request_key == ^command.key
        )

      case receipt do
        nil -> execute(scope, project_id, session_id, idea_id, access.user_id, command, fingerprint)
        %{fingerprint: ^fingerprint} -> replay(receipt, idea_id, command)
        _ -> {:error, :idempotency_conflict}
      end
    end
  end

  defp replay(receipt, idea_id, command) do
    reference = Repo.get!(Reference, receipt.reference_id)

    cond do
      reference.idea_id != idea_id -> {:error, :not_found}
      command.operation == "remove" and reference.version == receipt.number -> {:ok, {reference, false}}
      not is_nil(reference.deleted_at) -> {:error, :not_found}
      command.operation == "create" -> {:ok, {reference, false}}
      reference.version == receipt.number -> {:ok, {reference, false}}
      true -> {:error, :stale_reference}
    end
  end

  # Internal References port. Caller owns the authorized session lock, duplicate
  # and capacity checks; this shared writer keeps origin links in the same audit contract.
  def insert_locked(session_id, idea_id, actor_id, attrs, target, key, fingerprint) do
    reference = %Reference{
      session_id: session_id,
      idea_id: idea_id,
      created_by_id: actor_id,
      target_type: attrs.target_type,
      target_id: attrs.target_id,
      target_identity: target.identity,
      relation: attrs.relation,
      version: 1,
      context: View.context(target)
    }

    with {:ok, reference} <- Repo.insert(reference),
         {:ok, _} <- record(reference, actor_id, %{operation: "create", key: key}, fingerprint) do
      {:ok, {reference, true}}
    end
  end

  defp execute(scope, project_id, session_id, idea_id, actor_id, %{operation: "create"} = command, fingerprint) do
    attrs = command.attrs
    query = Catalog.session_query(session_id, idea_id)

    with false <-
           Repo.exists?(
             from r in query,
               where:
                 r.target_type == ^attrs.target_type and r.target_id == ^attrs.target_id and
                   r.relation == ^attrs.relation
           ),
         count when count < 100 <- Repo.aggregate(query, :count),
         {:ok, target} <- Targets.get(scope, project_id, attrs.target_type, attrs.target_id) do
      insert_locked(session_id, idea_id, actor_id, attrs, target, command.key, fingerprint)
    else
      true -> {:error, :reference_exists}
      count when is_integer(count) -> {:error, :reference_limit}
      {:error, _} = error -> error
    end
  end

  defp execute(scope, project_id, session_id, idea_id, actor_id, command, fingerprint) do
    case Catalog.record(session_id, idea_id, command.id) do
      %Reference{version: version} = reference when version == command.version and version < 50 ->
        with {:ok, attrs} <- changes(scope, project_id, reference, command.operation),
             {:ok, reference} <-
               reference |> Ecto.Changeset.change(Map.put(attrs, :version, version + 1)) |> Repo.update(),
             {:ok, _} <- record(reference, actor_id, command, fingerprint) do
          {:ok, {reference, true}}
        end

      %Reference{version: version} when version >= 50 ->
        {:error, :reference_history_limit}

      %Reference{} ->
        {:error, :stale_reference}

      nil ->
        {:error, :not_found}
    end
  end

  defp changes(_, _, _, "remove"), do: {:ok, %{deleted_at: %{TimeHelpers.now() | microsecond: {0, 6}}}}

  defp changes(_, _, %{version: version}, "refresh") when version >= 49, do: {:error, :reference_history_limit}

  defp changes(scope, project_id, reference, "refresh") do
    with {:ok, target} <- Targets.get(scope, project_id, reference.target_type, reference.target_id),
         true <- View.available?(reference, target) do
      {:ok, %{context: View.context(target)}}
    else
      _ -> {:error, :not_found}
    end
  end

  defp record(reference, actor_id, command, fingerprint) do
    Repo.insert(%Revision{
      session_id: reference.session_id,
      reference_id: reference.id,
      actor_id: actor_id,
      number: reference.version,
      operation: command.operation,
      request_key: command.key,
      fingerprint: fingerprint,
      context: reference.context
    })
  end
end

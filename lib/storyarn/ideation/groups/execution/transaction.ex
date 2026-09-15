defmodule Storyarn.Ideation.Groups.Execution.Transaction do
  @moduledoc false
  import Ecto.Query

  alias Storyarn.Ideation.Groups.Events.Invalidation
  alias Storyarn.Ideation.Groups.Execution.Memberships
  alias Storyarn.Ideation.Groups.Group
  alias Storyarn.Ideation.Groups.Queries.List
  alias Storyarn.Ideation.Groups.Revision
  alias Storyarn.Ideation.Groups.Rules.Input
  alias Storyarn.Ideation.Ideas
  alias Storyarn.Ideation.Sessions
  alias Storyarn.Repo

  def run(scope, project_id, session_id, command, callback) do
    if Repo.in_transaction?() do
      {:error, :group_requires_outer_transaction}
    else
      fn -> run_locked(scope, project_id, session_id, command, callback) end
      |> Repo.transact()
      |> complete(project_id, session_id, command.operation)
    end
  end

  defp run_locked(scope, project_id, session_id, command, callback) do
    fingerprint =
      Input.fingerprint(command.operation, command.group_id, command.version, command.attrs)

    with {:ok, access} <- Sessions.lock_for_contribution(scope, project_id, session_id),
         :ok <- round_open(session_id, command.group_id) do
      execute(access, command.request_key, fingerprint, command.attrs, callback)
    end
  end

  defp execute(access, key, fingerprint, attrs, callback) do
    receipt =
      Repo.one(
        from(r in Revision,
          where:
            r.session_id == ^access.session_id and r.actor_id == ^access.user_id and
              r.request_key == ^key
        )
      )

    case receipt do
      nil ->
        with {:ok, group} <- callback.(access, key, fingerprint) do
          {:ok, {project(group), true}}
        end

      %{fingerprint: ^fingerprint} ->
        group = Repo.get!(Group, receipt.group_id)

        # A creation replayed after its round went private answers like any other read of it.
        with :ok <- round_open(access.session_id, group.id),
             :ok <- replay_current(group, receipt, attrs) do
          {:ok, {project(group), false}}
        end

      _ ->
        {:error, :idempotency_conflict}
    end
  end

  # A retried creation is satisfied by the group it already created, even after
  # later edits by any editor; only its deletion makes the receipt stale.
  defp replay_current(group, %{operation: "create"}, _attrs),
    do: if(is_nil(group.deleted_at), do: :ok, else: {:error, :stale_group})

  defp replay_current(group, receipt, _attrs) when group.version != receipt.number, do: {:error, :stale_group}

  defp replay_current(group, %{operation: "move"}, attrs) do
    ids = group.id |> Memberships.current() |> Enum.map(& &1.idea_id)

    actual =
      group.session_id
      |> Ideas.group_sources(ids)
      |> Map.new(&{&1.idea_id, Map.get(&1.canvas, "version", 0)})

    expected = Map.new(attrs.member_versions, fn {id, version} -> {id, version + 1} end)
    if actual == expected, do: :ok, else: {:error, :stale_canvas}
  end

  defp replay_current(_, _, _), do: :ok

  defp project(group), do: group |> then(&List.project([&1], &1.session_id)) |> hd()

  defp complete({:ok, {result, changed?}}, project_id, session_id, operation) do
    if changed?, do: Invalidation.broadcast(project_id, session_id, operation)
    {:ok, result}
  end

  defp complete({:error, reason}, _, _, _), do: {:error, reason}

  # A group of a private round stays hidden, so nobody edits it until the reveal.
  defp round_open(_session_id, nil), do: :ok

  defp round_open(session_id, group_id) do
    case Repo.one(from g in Group, where: g.session_id == ^session_id and g.id == ^group_id, select: g.round_id) do
      nil -> :ok
      round_id -> if Sessions.round_private?(round_id), do: {:error, :private_round}, else: :ok
    end
  end
end

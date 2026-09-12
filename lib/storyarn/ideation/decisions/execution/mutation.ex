defmodule Storyarn.Ideation.Decisions.Execution.Mutation do
  @moduledoc false
  import Ecto.Changeset, only: [change: 2]
  import Ecto.Query

  alias Storyarn.Ideation.Decisions.Adapters.Responsibility
  alias Storyarn.Ideation.Decisions.Decision
  alias Storyarn.Ideation.Decisions.Queries.Sources
  alias Storyarn.Ideation.Decisions.Revision
  alias Storyarn.Repo

  def run(scope, project_id, access, nil, %{operation: "propose"} = command, fingerprint) do
    count = Repo.aggregate(from(d in Decision, where: d.session_id == ^access.session_id), :count)

    with true <- count < 100,
         :ok <- Responsibility.validate(scope, project_id, command.attrs.responsible_id),
         {:ok, snapshot} <- Sources.capture(access.session_id, command.attrs.sources) do
      decision = Repo.insert!(%Decision{session_id: access.session_id, author_id: access.user_id})
      record(decision, access.user_id, command, fingerprint, Map.merge(content(command.attrs), snapshot))
    else
      false -> {:error, :decision_limit_reached}
      {:error, _} = error -> error
    end
  end

  def run(scope, project_id, access, decision, command, fingerprint) do
    if decision.version == command.version do
      previous = Repo.get_by!(Revision, decision_id: decision.id, number: decision.version)
      mutate(scope, project_id, access, decision, previous, command, fingerprint)
    else
      {:error, :stale_decision}
    end
  end

  defp mutate(scope, project_id, access, decision, previous, %{operation: "revise"} = command, fingerprint) do
    # Reserve the final history slot for accepting the last proposal.
    with true <- decision.version < 99,
         :ok <- assignment(access, previous, command.attrs.responsible_id),
         :ok <- Responsibility.validate(scope, project_id, command.attrs.responsible_id),
         {:ok, snapshot} <- Sources.capture(access.session_id, command.attrs.sources, previous) do
      updated = decision |> change(version: decision.version + 1, status: :proposed) |> Repo.update!()
      record(updated, access.user_id, command, fingerprint, Map.merge(content(command.attrs), snapshot))
    else
      false -> {:error, :decision_history_limit}
      {:error, _} = error -> error
    end
  end

  defp mutate(_scope, _project_id, access, decision, previous, %{operation: "accept"} = command, fingerprint) do
    cond do
      decision.status == :accepted -> {:error, :already_accepted}
      previous.responsible_id != access.user_id -> {:error, :not_decision_responsible}
      decision.version >= 100 -> {:error, :decision_history_limit}
      true -> accept(access, decision, previous, command, fingerprint)
    end
  end

  defp accept(access, decision, previous, command, fingerprint) do
    items = previous.sources["items"]
    current = Sources.current(access.session_id, items)

    if Enum.all?(items, &Sources.available?(&1, current)) do
      version = decision.version + 1
      updated = decision |> change(version: version, status: :accepted, accepted_version: version) |> Repo.update!()
      snapshot = Map.take(previous, [:title, :conclusion, :reason, :responsible_id, :sources, :source_context])
      record(updated, access.user_id, command, fingerprint, snapshot)
    else
      {:error, :sources_unavailable}
    end
  end

  defp assignment(access, previous, responsible_id) do
    if responsible_id == previous.responsible_id or access.owner? or previous.responsible_id == access.user_id,
      do: :ok,
      else: {:error, :cannot_assign_responsible}
  end

  defp content(attrs), do: Map.take(attrs, [:title, :conclusion, :reason, :responsible_id])

  defp record(decision, actor_id, command, fingerprint, snapshot) do
    fields =
      Map.merge(snapshot, %{
        session_id: decision.session_id,
        decision_id: decision.id,
        number: decision.version,
        operation: command.operation,
        actor_id: actor_id,
        request_key: command.key,
        fingerprint: fingerprint
      })

    Repo.insert!(struct!(Revision, fields))
    {:ok, decision}
  end
end

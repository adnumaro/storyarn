defmodule Storyarn.Ideation.Decisions.Execution.Mutation do
  @moduledoc false
  import Ecto.Changeset, only: [change: 2]
  import Ecto.Query

  alias Storyarn.Ideation.Decisions.Adapters.Responsibility
  alias Storyarn.Ideation.Decisions.Application
  alias Storyarn.Ideation.Decisions.Decision
  alias Storyarn.Ideation.Decisions.Queries.Sources
  alias Storyarn.Ideation.Decisions.Queries.Targets
  alias Storyarn.Ideation.Decisions.Revision
  alias Storyarn.Repo

  @content ~w(verb title conclusion reason responsible_id next_action next_action_owner_id replaces_id)a
  @snapshot @content ++ ~w(sources source_context targets target_context round_id)a
  @max_applications 500

  def run(scope, project_id, access, nil, %{operation: "propose"} = command, fingerprint) do
    attrs = command.attrs
    count = Repo.aggregate(from(d in Decision, where: d.session_id == ^access.session_id), :count)

    with true <- count < 100,
         :ok <- registrable(access, attrs),
         :ok <- Responsibility.validate(scope, project_id, attrs.responsible_id),
         :ok <- validate_owner(scope, project_id, attrs.next_action_owner_id),
         {:ok, _} <- replaceable(access, nil, attrs.replaces_id),
         {:ok, snapshot} <- capture(scope, project_id, access, attrs, nil) do
      decision = Repo.insert!(%Decision{session_id: access.session_id, author_id: access.user_id})
      {:ok, decision, revision} = record(decision, access.user_id, command, fingerprint, snapshot)
      register(access, decision, revision, command, fingerprint)
    else
      false -> {:error, :decision_limit_reached}
      {:error, _} = error -> error
    end
  end

  def run(scope, project_id, access, decision, command, fingerprint) do
    if decision.version == command.version do
      previous = Repo.get_by!(Revision, decision_id: decision.id, number: basis(decision))
      mutate(scope, project_id, access, decision, previous, command, fingerprint)
    else
      {:error, :stale_decision}
    end
  end

  # A declaration is a statement about the agreement in force; it neither
  # advances the decision nor touches the affected content.
  def declare(access, decision, command, fingerprint) do
    agreement = decision.accepted_version

    with true <- (decision.status in [:accepted, :proposed] and not is_nil(agreement)) || {:error, :not_applicable},
         true <- agreement == command.agreement || {:error, :stale_decision},
         %Revision{} = accepted <- Repo.get_by(Revision, decision_id: decision.id, number: agreement),
         :ok <- declarable_target(accepted, command.attrs.target_key),
         true <- applications(decision) < @max_applications || {:error, :application_limit_reached} do
      Repo.insert!(%Application{
        session_id: decision.session_id,
        decision_id: decision.id,
        agreement: agreement,
        target_key: command.attrs.target_key,
        state: command.attrs.state,
        note: command.attrs.note,
        actor_id: access.user_id,
        request_key: command.key,
        fingerprint: fingerprint
      })

      {:ok, decision}
    end
  end

  defp mutate(scope, project_id, access, decision, previous, %{operation: "revise"} = command, fingerprint) do
    attrs = command.attrs

    # Reserve the last history slots for accepting the proposal and superseding it.
    with :ok <- live(decision),
         true <- decision.version < 97 || {:error, :decision_history_limit},
         :ok <- assignment(access, previous, attrs.responsible_id),
         :ok <- registrable(access, attrs),
         :ok <- Responsibility.validate(scope, project_id, attrs.responsible_id),
         :ok <- validate_owner(scope, project_id, attrs.next_action_owner_id),
         {:ok, _} <- replaceable(access, decision.id, attrs.replaces_id),
         {:ok, snapshot} <- capture(scope, project_id, access, attrs, previous) do
      updated = decision |> change(version: decision.version + 1, status: :proposed) |> Repo.update!()
      {:ok, updated, revision} = record(updated, access.user_id, command, fingerprint, snapshot)
      register(access, updated, revision, command, fingerprint)
    end
  end

  defp mutate(_scope, _project_id, access, decision, previous, %{operation: "accept"} = command, fingerprint) do
    cond do
      decision.status == :accepted -> {:error, :already_accepted}
      decision.status != :proposed -> {:error, :decision_retired}
      previous.responsible_id != access.user_id -> {:error, :not_decision_responsible}
      decision.version >= 99 -> {:error, :decision_history_limit}
      true -> accept(access, decision, previous, command, fingerprint, "accept")
    end
  end

  defp mutate(_scope, _project_id, access, decision, previous, %{operation: "withdraw"} = command, fingerprint) do
    cond do
      decision.status != :proposed -> {:error, :not_withdrawable}
      not (access.owner? or previous.actor_id == access.user_id) -> {:error, :cannot_withdraw}
      decision.version >= 100 -> {:error, :decision_history_limit}
      true -> withdraw(access, decision, previous, command, fingerprint)
    end
  end

  # Registering is proposing and accepting in one step: two consecutive records
  # by the same person, who must be the responsible person.
  defp register(_access, decision, _revision, %{attrs: %{register: false}}, _fingerprint), do: {:ok, decision}

  defp register(access, decision, revision, command, fingerprint) do
    derived = %{command | key: derived_key(command.key, "register")}
    accept(access, decision, revision, derived, fingerprint, "register")
  end

  defp accept(access, decision, previous, command, fingerprint, operation) do
    items = previous.sources["items"]
    current = Sources.current(access.session_id, items)

    with true <- Enum.all?(items, &Sources.available?(&1, current)) || {:error, :sources_unavailable},
         {:ok, replaced} <- replaceable(access, decision.id, previous.replaces_id) do
      version = decision.version + 1
      updated = decision |> change(version: version, status: :accepted, accepted_version: version) |> Repo.update!()

      {:ok, updated, _} =
        record(updated, access.user_id, %{command | operation: operation}, fingerprint, copy(previous))

      supersede(access, replaced, updated, command, fingerprint)
    else
      {:error, :invalid_replacement} -> {:error, :replaced_decision_unavailable}
      {:error, _} = error -> error
    end
  end

  defp withdraw(access, decision, previous, command, fingerprint) do
    # Withdrawing a revision keeps the earlier agreement in force.
    status = if decision.accepted_version, do: :accepted, else: :withdrawn
    updated = decision |> change(version: decision.version + 1, status: status) |> Repo.update!()
    {:ok, updated, _} = record(updated, access.user_id, command, fingerprint, copy(previous))
    {:ok, updated}
  end

  defp supersede(_access, nil, decision, _command, _fingerprint), do: {:ok, decision}

  defp supersede(access, replaced, decision, command, fingerprint) do
    if replaced.version >= 100 do
      {:error, :decision_history_limit}
    else
      agreement = Repo.get_by!(Revision, decision_id: replaced.id, number: replaced.accepted_version)
      updated = replaced |> change(version: replaced.version + 1, status: :superseded) |> Repo.update!()

      snapshot = Map.put(copy(agreement), :superseded_by_id, decision.id)
      derived = %{command | operation: "supersede", key: derived_key(command.key, "supersede")}
      {:ok, _, _} = record(updated, access.user_id, derived, fingerprint, snapshot)
      {:ok, decision}
    end
  end

  # Only an agreement in force can be replaced, and never by the decision itself.
  # A revision of the replacement keeps naming what it already replaced; there
  # is nothing left to supersede.
  defp replaceable(_access, _self, nil), do: {:ok, nil}
  defp replaceable(_access, id, id), do: {:error, :invalid_replacement}

  defp replaceable(access, self, id) do
    case Repo.get_by(Decision, id: id, session_id: access.session_id) do
      %Decision{status: status, accepted_version: agreement} = decision
      when status in [:accepted, :proposed] and not is_nil(agreement) ->
        {:ok, decision}

      %Decision{status: :superseded} = decision when not is_nil(self) ->
        if superseded_by?(decision, self), do: {:ok, nil}, else: {:error, :invalid_replacement}

      _ ->
        {:error, :invalid_replacement}
    end
  end

  defp superseded_by?(decision, self) do
    Repo.exists?(
      from r in Revision,
        where: r.decision_id == ^decision.id and r.number == ^decision.version and r.superseded_by_id == ^self
    )
  end

  # Without a pending revision the agreement in force is what the next step
  # builds on; a withdrawn revision's record never carries its authority.
  defp basis(%Decision{status: :accepted, accepted_version: agreement}) when not is_nil(agreement), do: agreement
  defp basis(decision), do: decision.version

  defp live(%Decision{status: status}) when status in [:proposed, :accepted], do: :ok
  defp live(_decision), do: {:error, :decision_retired}

  defp registrable(access, %{register: true, responsible_id: responsible}) when responsible != access.user_id,
    do: {:error, :not_decision_responsible}

  defp registrable(_access, _attrs), do: :ok

  defp validate_owner(_scope, _project_id, nil), do: :ok

  defp validate_owner(scope, project_id, owner_id) do
    case Responsibility.validate(scope, project_id, owner_id) do
      :ok -> :ok
      {:error, :responsible_busy} -> {:error, :responsible_busy}
      {:error, _} -> {:error, :ineligible_next_action_owner}
    end
  end

  defp assignment(access, previous, responsible_id) do
    if responsible_id == previous.responsible_id or access.owner? or previous.responsible_id == access.user_id,
      do: :ok,
      else: {:error, :cannot_assign_responsible}
  end

  defp declarable_target(%Revision{targets: %{"items" => []}}, nil), do: :ok

  defp declarable_target(%Revision{targets: %{"items" => items}}, key) when is_binary(key) do
    if Enum.any?(items, &(&1["key"] == key)), do: :ok, else: {:error, :invalid_application}
  end

  defp declarable_target(_revision, _key), do: {:error, :invalid_application}

  defp applications(decision), do: Repo.aggregate(from(a in Application, where: a.decision_id == ^decision.id), :count)

  defp capture(scope, project_id, access, attrs, previous) do
    with {:ok, sources} <- Sources.capture(access.session_id, attrs.sources, previous),
         {:ok, targets} <- Targets.capture(scope, project_id, attrs.targets) do
      {:ok, attrs |> Map.take(@content) |> Map.merge(sources) |> Map.merge(targets)}
    end
  end

  defp copy(revision), do: Map.take(revision, @snapshot)

  # One command may write several records; each needs its own receipt slot.
  defp derived_key(key, purpose) do
    {:ok, bytes} = Ecto.UUID.dump(key)
    {:ok, uuid} = Ecto.UUID.load(:crypto.hash(:md5, [bytes, purpose]))
    uuid
  end

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

    {:ok, decision, Repo.insert!(struct!(Revision, fields))}
  end
end

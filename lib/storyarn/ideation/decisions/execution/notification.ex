defmodule Storyarn.Ideation.Decisions.Execution.Notification do
  @moduledoc false
  alias Storyarn.Ideation.Decisions.Adapters.Notifications
  alias Storyarn.Ideation.Decisions.Revision
  alias Storyarn.Ideation.Sessions
  alias Storyarn.Repo

  @doc """
  Tells the people a write concerns, inside its transaction: the responsible
  person when a proposal waits for them, the proposer and the discussion when it
  is accepted, the next action's owner, and the responsible person and proposer
  when content is marked applied. The actor is never told about their own step.

  A request to accept is settled once the decision stops waiting for it: a
  revision, acceptance or withdrawal marks the earlier requests read before any
  new one is delivered, and so does superseding the decision it replaces.
  """
  def notify(scope, project_id, access, decision, command) do
    with {:ok, settled} <- settle(project_id, settled_ids(decision, command)),
         {:ok, delivered} <- deliver(scope, project_id, access, decision, command) do
      {:ok, Enum.reject([settled | delivered_list(delivered)], &is_nil/1)}
    end
  end

  defp settled_ids(decision, %{operation: operation}) do
    own = if operation in ~w(revise accept withdraw), do: [decision.id], else: []
    own ++ replaced(decision)
  end

  defp replaced(%{status: :accepted} = decision) do
    case revision(decision, decision.accepted_version) do
      %Revision{replaces_id: id} when is_integer(id) -> [id]
      _ -> []
    end
  end

  defp replaced(_decision), do: []

  defp settle(_project_id, []), do: {:ok, nil}

  defp settle(project_id, ids) do
    Enum.reduce_while(ids, {:ok, {:read, []}}, fn id, {:ok, {:read, read}} ->
      case Notifications.resolve_requests(project_id, id) do
        {:ok, {:read, more}} -> {:cont, {:ok, {:read, Enum.uniq(read ++ more)}}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp delivered_list(nil), do: []
  defp delivered_list(outcome), do: [outcome]

  defp deliver(scope, project_id, access, decision, command) do
    recipients =
      scope |> recipients(project_id, access, decision, command) |> Enum.reject(&(&1.user_id == access.user_id))

    with [_ | _] <- recipients,
         {:ok, session} <- Sessions.get_session(scope, project_id, access.session_id) do
      event = %{id: decision.id, label: session.title, event: event(decision, command)}
      Notifications.deliver(access.user_id, project_id, event, Enum.uniq(recipients))
    else
      _ -> {:ok, nil}
    end
  end

  defp recipients(_scope, _project_id, _access, %{status: :proposed} = decision, %{operation: operation})
       when operation in ["propose", "revise"] do
    head = revision(decision, decision.version)
    [%{user_id: head.responsible_id, kind: "decision_to_accept"}]
  end

  defp recipients(scope, project_id, access, %{status: :accepted} = decision, %{operation: operation})
       when operation in ["propose", "revise", "accept"] do
    agreement = revision(decision, decision.accepted_version)
    proposal = revision(decision, decision.accepted_version - 1)
    discussion = Notifications.discussants(scope, project_id, access.session_id, decision.id)

    accepted =
      for user_id <- Enum.uniq([proposal && proposal.actor_id | discussion]),
          not is_nil(user_id),
          do: %{user_id: user_id, kind: "decision_accepted"}

    next =
      if agreement.next_action_owner_id,
        do: [%{user_id: agreement.next_action_owner_id, kind: "decision_next_action"}],
        else: []

    accepted ++ next
  end

  defp recipients(_scope, _project_id, _access, decision, %{operation: "declare", attrs: %{state: "applied"}}) do
    agreement = revision(decision, decision.accepted_version)

    for user_id <- Enum.uniq([agreement.responsible_id, decision.author_id]),
        not is_nil(user_id),
        do: %{user_id: user_id, kind: "decision_applied"}
  end

  defp recipients(_scope, _project_id, _access, _decision, _command), do: []

  defp event(_decision, %{operation: "declare", key: key}), do: "d#{key}"
  defp event(decision, _command), do: "r#{decision.version}"

  defp revision(_decision, nil), do: nil
  defp revision(_decision, number) when number < 1, do: nil
  defp revision(decision, number), do: Repo.get_by(Revision, decision_id: decision.id, number: number)
end

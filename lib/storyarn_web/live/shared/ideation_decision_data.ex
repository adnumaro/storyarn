defmodule StoryarnWeb.Live.Shared.IdeationDecisionData do
  @moduledoc false

  # `board` holds the session's rounds and the project's members; when it also
  # holds an `href` function, available targets link to their editor.
  def decision(value, board) do
    %{
      id: value.id,
      sessionId: value.session_id,
      version: value.version,
      status: value.status,
      proposal: revision(value.proposal, board),
      accepted: if(value.accepted, do: revision(value.accepted, board)),
      application: application(value.application, board),
      proposerName: member_name(board, value.proposer_id),
      withdrawnByName: member_name(board, value.withdrawn_by_id),
      replaces: link(value.replaces),
      supersedes: link(value.supersedes),
      supersededBy: link(value.superseded_by),
      canAccept: value.can_accept,
      canRevise: value.can_revise,
      canAssign: value.can_assign,
      canWithdraw: value.can_withdraw,
      canDeclare: value.can_declare,
      tasks: Enum.map(value.tasks, &task(&1, board)),
      canLinkTasks: value.can_link_tasks,
      updatedAt: value.updated_at
    }
  end

  def revision(value, board) do
    %{
      revision: value.number,
      operation: value.operation,
      verb: value.verb,
      title: value.title,
      conclusion: value.conclusion,
      reason: value.reason,
      responsibleId: value.responsible_id,
      responsibleName: member_name(board, value.responsible_id),
      actorName: member_name(board, value.actor_id),
      nextAction: next_action(value, board),
      round: round(board, value.round_id),
      replacesId: value.replaces_id,
      recordedAt: value.inserted_at,
      sources: Enum.map(value.sources, &source(&1, board)),
      targets: Enum.map(value.targets, &target(&1, board))
    }
  end

  # Newest first. A registration is one step for the person who took it, so its
  # proposal and acceptance read as a single entry.
  def history(%{revisions: revisions, applications: applications, tasks: tasks}, board) do
    records = revisions |> Enum.sort_by(& &1.number) |> records(board) |> Enum.reverse()
    declared = Enum.map(applications, &declaration_entry(&1, board))
    linked = Enum.map(tasks, &task_entry(&1, board))

    Enum.sort_by(records ++ declared ++ linked, & &1.at, {:desc, DateTime})
  end

  def source(value, board \\ nil) do
    %{
      type: value.type,
      id: value.id,
      identity: value.identity,
      version: value.version,
      title: Map.get(value, :title) || "",
      preview: plain_text(Map.get(value, :body, "")),
      authorName: if(board, do: member_name(board, Map.get(value, :author_id))),
      roundNumber: if(board, do: round_number(board, Map.get(value, :round_id))),
      state: Map.get(value, :state),
      available: Map.get(value, :available, true),
      changed: Map.get(value, :changed, false),
      currentVersion: Map.get(value, :current_version)
    }
  end

  def target(value, board) do
    %{
      key: value.key,
      type: value.type,
      id: value.id,
      name: value.name,
      isNew: value.new,
      available: value.available,
      href: href(board, value),
      application: declaration(Map.get(value, :application), board)
    }
  end

  defp href(%{href: href}, %{available: true, id: id, type: type}) when is_integer(id), do: href.(%{type: type, id: id})
  defp href(_board, _target), do: nil

  defp records([], _board), do: []

  defp records([proposal, %{operation: "register"} = registration | rest], board)
       when proposal.operation in ["propose", "revise"] and proposal.actor_id == registration.actor_id do
    entry = record_entry(registration, board)
    [%{entry | operation: "registered", id: "record-#{proposal.number}"} | records(rest, board)]
  end

  defp records([revision | rest], board), do: [record_entry(revision, board) | records(rest, board)]

  defp record_entry(revision, board) do
    %{
      kind: "record",
      id: "record-#{revision.number}",
      operation: revision.operation,
      actorName: member_name(board, revision.actor_id),
      responsibleName: member_name(board, revision.responsible_id),
      title: revision.title,
      text: revision.conclusion,
      at: revision.inserted_at
    }
  end

  defp declaration_entry(value, board) do
    %{
      kind: "application",
      id: "application-#{value.agreement}-#{value.target_key}-#{DateTime.to_unix(value.inserted_at, :microsecond)}",
      operation: value.state,
      actorName: member_name(board, value.actor_id),
      targetName: value.target && value.target.name,
      targetType: value.target && value.target.type,
      text: value.note,
      at: value.inserted_at
    }
  end

  defp task(value, board) do
    %{
      key: value.key,
      kind: value.kind,
      url: value.url,
      title: value.title,
      linkedByName: member_name(board, value.linked_by_id),
      linkedAt: value.linked_at
    }
  end

  defp task_entry(value, board) do
    %{
      kind: "task",
      id: "task-#{value.key}-#{value.operation}-#{DateTime.to_unix(value.inserted_at, :microsecond)}",
      operation: value.operation,
      actorName: member_name(board, value.actor_id),
      targetName: value.title || value.url,
      url: value.url,
      text: nil,
      at: value.inserted_at
    }
  end

  defp application(nil, _board), do: nil

  defp application(value, board) do
    %{
      targets: Enum.map(value.targets, &target(&1, board)),
      decision: declaration(value.decision, board),
      pending: value.pending,
      total: value.total
    }
  end

  defp declaration(nil, _board), do: nil

  defp declaration(value, board) do
    %{state: value.state, note: value.note, actorName: member_name(board, value.actor_id), at: value.inserted_at}
  end

  defp next_action(%{next_action: nil}, _board), do: nil

  defp next_action(value, board) do
    %{
      text: value.next_action,
      ownerId: value.next_action_owner_id,
      ownerName: member_name(board, value.next_action_owner_id)
    }
  end

  defp link(nil), do: nil
  defp link(value), do: %{id: value.id, title: value.title}

  defp round(_board, nil), do: nil

  defp round(board, id) do
    case Enum.find(board.rounds, &(&1.id == id)) do
      nil -> nil
      round -> %{number: round.number, prompt: round.prompt}
    end
  end

  defp round_number(_board, nil), do: nil

  defp round_number(board, id) do
    case Enum.find(board.rounds, &(&1.id == id)) do
      nil -> nil
      round -> round.number
    end
  end

  defp plain_text(nil), do: ""
  defp plain_text(value), do: value |> Floki.parse_fragment!() |> Floki.text(sep: " ")

  defp member_name(_board, nil), do: nil

  defp member_name(board, id) do
    case Enum.find(board.members, &(&1.id == id)) do
      nil -> nil
      member -> member.display_name
    end
  end
end

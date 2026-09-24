defmodule Storyarn.Ideation.Decisions.View do
  @moduledoc false

  @pending ~w(not_applied partially_applied)

  def decision(decision, context, access) do
    head = context.revisions[{decision.id, decision.version}]
    agreement = decision.accepted_version && context.revisions[{decision.id, decision.accepted_version}]
    proposal = revision(head, context)
    accepted = if agreement, do: revision(agreement, context)

    %{
      id: decision.id,
      session_id: decision.session_id,
      author_id: decision.author_id,
      version: decision.version,
      status: decision.status,
      accepted_version: decision.accepted_version,
      proposal: proposal,
      accepted: accepted,
      application: if(accepted, do: application(decision, accepted, context)),
      inserted_at: decision.inserted_at,
      updated_at: decision.updated_at
    }
    |> Map.merge(people(decision, head))
    |> Map.merge(links(decision, head, proposal, accepted, context))
    |> Map.merge(permissions(decision, basis(decision, head, agreement), proposal, context, access))
  end

  defp basis(%{status: :accepted}, _head, agreement) when not is_nil(agreement), do: agreement
  defp basis(_decision, head, _agreement), do: head

  defp people(decision, head) do
    %{
      proposer_id: if(decision.status == :proposed, do: head.actor_id),
      withdrawn_by_id: if(decision.status == :withdrawn, do: head.actor_id)
    }
  end

  defp links(decision, head, proposal, accepted, context) do
    %{
      replaces: related(context, proposal.replaces_id),
      supersedes: if(accepted, do: related(context, accepted.replaces_id)),
      superseded_by: if(decision.status == :superseded, do: related(context, head.superseded_by_id))
    }
  end

  defp permissions(decision, head, proposal, context, access) do
    editable? = access.open? and access.editor?
    live? = decision.status in [:proposed, :accepted]
    can_revise? = editable? and live? and decision.version < 97

    %{
      can_revise: can_revise?,
      can_assign: can_revise? and owner_or?(access, head.responsible_id),
      can_accept: can_accept?(decision, proposal, context, access),
      can_withdraw: editable? and decision.status == :proposed and owner_or?(access, head.actor_id),
      can_declare: editable? and live? and not is_nil(decision.accepted_version)
    }
  end

  # The project owner, or the one person the rule names.
  defp owner_or?(access, user_id), do: access.owner? or user_id == access.user_id

  defp can_accept?(decision, proposal, context, access) do
    replaced = related(context, proposal.replaces_id)

    access.open? and access.editor? and decision.status == :proposed and proposal.responsible_id == access.user_id and
      Enum.all?(proposal.sources, & &1.available) and
      (is_nil(proposal.replaces_id) or
         (replaced && (replaced.replaceable or replaced.superseded_by_id == decision.id)))
  end

  def revision(revision, context) do
    sources = Jason.decode!(revision.source_context)
    labels = Jason.decode!(revision.target_context)

    revision
    |> Map.take([
      :number,
      :operation,
      :actor_id,
      :responsible_id,
      :verb,
      :title,
      :conclusion,
      :reason,
      :next_action,
      :next_action_owner_id,
      :round_id,
      :replaces_id,
      :superseded_by_id,
      :inserted_at
    ])
    |> Map.put(:sources, Enum.map(revision.sources["items"], &source(&1, sources, context.sources)))
    |> Map.put(:targets, Enum.map(revision.targets["items"], &target(&1, labels, context.targets)))
  end

  def declaration(application, agreement) do
    target = application.target_key && Enum.find(agreement.targets, &(&1.key == application.target_key))

    %{
      agreement: application.agreement,
      target_key: application.target_key,
      target: target,
      state: application.state,
      note: application.note,
      actor_id: application.actor_id,
      inserted_at: application.inserted_at
    }
  end

  # Only the latest statement per target counts; the default is "not applied".
  defp application(decision, accepted, context) do
    declared = Map.get(context.applications, {decision.id, accepted.number}, %{})

    targets =
      Enum.map(accepted.targets, fn target ->
        Map.put(target, :application, Map.get(declared, target.key))
      end)

    states = Enum.map(targets, &((&1.application && &1.application.state) || "not_applied"))

    %{
      targets: targets,
      decision: Map.get(declared, nil),
      pending: Enum.count(states, &(&1 in @pending)),
      total: length(targets)
    }
  end

  defp related(_context, nil), do: nil
  defp related(context, id), do: Map.get(context.related, id)

  defp source(source, context, current) do
    live = current[{source["type"], source["id"]}]
    available? = live != nil and live.identity == source["identity"]
    frozen = if available?, do: context[source["identity"]], else: %{}

    %{
      type: source["type"],
      id: if(available?, do: source["id"]),
      identity: source["identity"],
      version: source["version"],
      author_id: if(available?, do: source["author_id"]),
      round_id: if(available?, do: live.round_id),
      state: if(available?, do: live.state),
      title: frozen["title"],
      body: frozen["body"],
      available: available?,
      changed: available? and live.version != source["version"],
      current_version: if(available?, do: live.version)
    }
  end

  # Something new has no content yet: its label is all there is. Existing
  # content reads its current name and turns unavailable once it is replaced.
  defp target(%{"id" => nil, "identity" => nil} = target, labels, _live) do
    %{
      key: target["key"],
      type: target["type"],
      id: nil,
      name: labels[target["key"]]["label"],
      new: true,
      available: true
    }
  end

  defp target(target, labels, live) do
    current = live[{target["type"], target["id"]}]
    available? = current != nil and current.identity == target["identity"]

    %{
      key: target["key"],
      type: target["type"],
      id: if(available?, do: target["id"]),
      name: if(available? and current.name != "", do: current.name, else: labels[target["key"]]["label"]),
      new: false,
      available: available?
    }
  end
end

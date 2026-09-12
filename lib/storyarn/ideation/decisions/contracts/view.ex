defmodule Storyarn.Ideation.Decisions.View do
  @moduledoc false

  def decision(decision, proposal, accepted, access, current) do
    proposed = revision(proposal, current)
    editable? = access.open? and access.editor?
    can_revise? = editable? and decision.version < 99

    %{
      id: decision.id,
      session_id: decision.session_id,
      author_id: decision.author_id,
      version: decision.version,
      status: decision.status,
      proposal: proposed,
      accepted: if(accepted, do: revision(accepted, current)),
      can_revise: can_revise?,
      can_assign: can_revise? and (access.owner? or proposal.responsible_id == access.user_id),
      can_accept: can_accept?(decision, proposed, access),
      inserted_at: decision.inserted_at
    }
  end

  defp can_accept?(decision, proposal, access) do
    access.open? and access.editor? and decision.status == :proposed and proposal.responsible_id == access.user_id and
      Enum.all?(proposal.sources, & &1.available)
  end

  def revision(revision, current) do
    context = Jason.decode!(revision.source_context)

    revision
    |> Map.take([:number, :operation, :actor_id, :responsible_id, :title, :conclusion, :reason, :inserted_at])
    |> Map.put(:sources, Enum.map(revision.sources["items"], &source(&1, context, current)))
  end

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
      title: frozen["title"],
      body: frozen["body"],
      available: available?,
      changed: available? and live.version != source["version"],
      current_version: if(available?, do: live.version)
    }
  end
end

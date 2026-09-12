defmodule StoryarnWeb.IdeationLive.Helpers.DecisionData do
  @moduledoc false

  def decision(value, members) do
    value.proposal
    |> agreement(members)
    |> Map.merge(%{
      id: value.id,
      revision: value.version,
      status: value.status,
      canAccept: value.can_accept,
      canRevise: value.can_revise,
      canAssign: value.can_assign,
      previousAgreement:
        if(value.accepted && value.accepted.number != value.proposal.number,
          do: agreement(value.accepted, members)
        )
    })
  end

  def agreement(value, members) do
    %{
      revision: value.number,
      title: value.title,
      conclusion: value.conclusion,
      reason: value.reason,
      ownerId: value.responsible_id,
      ownerName: member_name(members, value.responsible_id),
      acceptedAt: if(value.operation == "accept", do: value.inserted_at),
      sources: Enum.map(value.sources, &source/1)
    }
  end

  def history(value, members) do
    value
    |> agreement(members)
    |> Map.merge(%{
      operation: operation(value.operation),
      actorName: member_name(members, value.actor_id),
      recordedAt: value.inserted_at
    })
  end

  def source(value) do
    %{
      type: value.type,
      id: value.id,
      identity: value.identity,
      version: value.version,
      title: Map.get(value, :title) || "",
      preview: plain_text(Map.get(value, :body, "")),
      available: Map.get(value, :available, true),
      changed: Map.get(value, :changed, false),
      currentVersion: Map.get(value, :current_version)
    }
  end

  defp plain_text(nil), do: ""
  defp plain_text(value), do: value |> Floki.parse_fragment!() |> Floki.text(sep: " ")

  defp member_name(members, id) do
    case Enum.find(members, &(&1.id == id)) do
      nil -> nil
      member -> member.display_name
    end
  end

  defp operation("propose"), do: "proposed"
  defp operation("revise"), do: "revised"
  defp operation("accept"), do: "accepted"
end

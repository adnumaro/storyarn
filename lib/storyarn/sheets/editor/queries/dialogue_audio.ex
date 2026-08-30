defmodule Storyarn.Sheets.Editor.Queries.DialogueAudio do
  @moduledoc """
  Read-only Sheet projection of dialogue lines spoken by one Sheet.

  The audio workspace needs a consumer-shaped view of Flow nodes and their
  parent Flows. It owns this query shape, but it does not gain write authority
  over either shared table.
  """

  import Ecto.Query

  alias Storyarn.Repo
  alias Storyarn.Sheets.Editor.Projections.FlowNodeRecord
  alias Storyarn.Sheets.Editor.Projections.FlowRecord

  @spec list_lines(integer(), integer()) :: [map()]
  def list_lines(project_id, sheet_id) do
    sheet_id = to_string(sheet_id)

    from(node in FlowNodeRecord,
      join: flow in FlowRecord,
      on: flow.id == node.flow_id,
      where:
        flow.project_id == ^project_id and is_nil(flow.deleted_at) and
          node.type == "dialogue" and is_nil(node.deleted_at),
      where: fragment("?->>'speaker_sheet_id' = ?", node.data, ^sheet_id),
      order_by: [asc: flow.name, asc: node.inserted_at],
      select: {node, flow}
    )
    |> Repo.all()
    |> Enum.map(fn {node, flow} ->
      Map.put(node, :flow, %{id: flow.id, name: flow.name, shortcut: flow.shortcut})
    end)
  end
end

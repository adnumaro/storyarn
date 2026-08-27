defmodule Storyarn.Sheets.Editor.Commands.DialogueAudio do
  @moduledoc """
  Sheets-owned projection and narrow writer for a speaker's dialogue audio.

  The audio tab consumes only this contract. It reads and updates the shared
  graph tables through Sheets records without depending on Flow code.
  """

  import Ecto.Query

  alias Storyarn.Platform.Collaboration
  alias Storyarn.Repo
  alias Storyarn.Sheets.Editor.Projections.AssetRecord
  alias Storyarn.Sheets.Editor.Projections.FlowNodeRecord
  alias Storyarn.Sheets.Editor.Projections.FlowRecord

  @derivatives_fingerprint_version 1

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

  @spec update_audio(integer(), integer(), integer(), integer() | nil) ::
          {:ok, FlowNodeRecord.t()} | {:error, term()}
  def update_audio(project_id, sheet_id, node_id, audio_asset_id) do
    case Repo.transaction(fn -> update_audio_in_transaction(project_id, sheet_id, node_id, audio_asset_id) end) do
      {:ok, node} ->
        Collaboration.broadcast_dashboard_change(project_id, :flows)
        {:ok, node}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp update_audio_in_transaction(project_id, sheet_id, node_id, audio_asset_id) do
    speaker_id = to_string(sheet_id)

    node =
      Repo.one(
        from node in FlowNodeRecord,
          join: flow in FlowRecord,
          on: flow.id == node.flow_id,
          where:
            node.id == ^node_id and node.type == "dialogue" and
              is_nil(node.deleted_at) and flow.project_id == ^project_id and
              is_nil(flow.deleted_at),
          where: fragment("?->>'speaker_sheet_id' = ?", node.data, ^speaker_id),
          lock: "FOR UPDATE"
      )

    with %FlowNodeRecord{} = node <- node,
         :ok <- validate_asset(project_id, audio_asset_id),
         data = Map.put(node.data || %{}, "audio_asset_id", audio_asset_id),
         fingerprint = derivatives_fingerprint(node.type, data),
         {:ok, updated} <-
           node
           |> Ecto.Changeset.change(data: data, derivatives_fingerprint: fingerprint)
           |> Repo.update() do
      updated
    else
      nil -> Repo.rollback(:not_found)
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp validate_asset(_project_id, nil), do: :ok

  defp validate_asset(project_id, asset_id) when is_integer(asset_id) do
    if Repo.exists?(
         from asset in AssetRecord,
           where:
             asset.id == ^asset_id and asset.project_id == ^project_id and
               is_nil(asset.deleted_at)
       ) do
      :ok
    else
      {:error, {:invalid_project_reference, :audio_asset_id, asset_id}}
    end
  end

  defp validate_asset(_project_id, asset_id), do: {:error, {:invalid_project_reference, :audio_asset_id, asset_id}}

  defp derivatives_fingerprint(type, data) do
    {@derivatives_fingerprint_version, type, data}
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end
end

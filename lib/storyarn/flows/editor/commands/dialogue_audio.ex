defmodule Storyarn.Flows.Editor.Commands.DialogueAudio do
  @moduledoc """
  Assigns audio to a dialogue node through the Flow-owned write model.

  The command is intentionally narrower than a generic node edit. It locks and
  validates only the project, Flow node, speaker Sheet and audio asset involved
  in this operation, then changes only `audio_asset_id` within the node data and
  recomputes the derived fingerprint for that data. This preserves the existing
  Sheet audio workspace behavior without allowing Sheets to write `flow_nodes`
  or making unrelated legacy node data block an audio change.
  """

  alias Storyarn.Flows.FlowNode
  alias Storyarn.Flows.NodeUpdate
  alias Storyarn.Flows.References
  alias Storyarn.Platform.Collaboration
  alias Storyarn.Repo

  @max_pg_bigint 9_223_372_036_854_775_807

  defguardp valid_id(value)
            when is_integer(value) and value > 0 and value <= @max_pg_bigint

  @receipt_node_fields [
    :id,
    :type,
    :position_x,
    :position_y,
    :data,
    :word_count,
    :derivatives_fingerprint,
    :deleted_at,
    :flow_id,
    :parent_id,
    :inserted_at,
    :updated_at
  ]

  @type receipt :: %{
          node_id: pos_integer(),
          audio_asset_id: pos_integer() | nil,
          node_snapshot: map()
        }
  @type error_reason ::
          :not_found | :update_failed | {:invalid_project_reference, :audio_asset_id, term()}

  @spec assign(pos_integer(), pos_integer(), pos_integer(), pos_integer() | nil) ::
          {:ok, receipt()} | {:error, error_reason()}
  def assign(project_id, speaker_sheet_id, node_id, audio_asset_id)
      when valid_id(project_id) and valid_id(speaker_sheet_id) and valid_id(node_id) and
             (is_nil(audio_asset_id) or valid_id(audio_asset_id)) do
    case Repo.transaction(fn ->
           assign_in_transaction(project_id, speaker_sheet_id, node_id, audio_asset_id)
         end) do
      {:ok, updated_node} ->
        Collaboration.broadcast_dashboard_change(project_id, :flows)

        {:ok,
         %{
           node_id: updated_node.id,
           audio_asset_id: updated_node.data["audio_asset_id"],
           node_snapshot: Map.take(updated_node, @receipt_node_fields)
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def assign(project_id, speaker_sheet_id, node_id, _audio_asset_id)
      when not (valid_id(project_id) and valid_id(speaker_sheet_id) and valid_id(node_id)), do: {:error, :not_found}

  def assign(_project_id, _speaker_sheet_id, _node_id, audio_asset_id),
    do: {:error, {:invalid_project_reference, :audio_asset_id, audio_asset_id}}

  defp assign_in_transaction(project_id, speaker_sheet_id, node_id, audio_asset_id) do
    # Audio assignment does not run the localization projection because audio
    # does not change translatable content. It still takes the project update
    # lock up front: ordinary node edits upgrade to that lock while reconciling
    # localization, so holding only KEY SHARE while waiting for the same Flow
    # row can form a lock-upgrade deadlock.
    with {:ok, locked} <- References.lock_active_node_for_write(node_id, :update),
         :ok <- validate_dialogue(locked, project_id, speaker_sheet_id),
         :ok <- lock_references(project_id, speaker_sheet_id, audio_asset_id),
         {:ok, updated_node} <- persist_audio(locked.node, audio_asset_id) do
      updated_node
    else
      {:error, reason} -> Repo.rollback(normalize_error(reason))
    end
  end

  defp validate_dialogue(
         %{project_id: project_id, node: %FlowNode{type: "dialogue"} = node},
         project_id,
         speaker_sheet_id
       ) do
    if normalize_speaker_id(node.data) == speaker_sheet_id,
      do: :ok,
      else: {:error, :not_found}
  end

  defp validate_dialogue(_locked, _project_id, _speaker_sheet_id), do: {:error, :not_found}

  defp lock_references(project_id, speaker_sheet_id, audio_asset_id) do
    with {:ok, [_speaker_sheet_id, ^audio_asset_id]} <-
           References.lock_active_references(project_id, [
             {:sheet, :speaker_sheet_id, speaker_sheet_id},
             {:asset, :audio_asset_id, audio_asset_id}
           ]) do
      References.ensure_locked_asset_content_type(
        project_id,
        audio_asset_id,
        :audio_asset_id,
        "audio/%"
      )
    end
  end

  defp persist_audio(%FlowNode{} = node, audio_asset_id) do
    data = Map.put(node.data || %{}, "audio_asset_id", audio_asset_id)

    node
    |> Ecto.Changeset.change(
      data: data,
      derivatives_fingerprint: NodeUpdate.derivatives_fingerprint(node.type, data)
    )
    |> Repo.update()
  end

  defp normalize_speaker_id(data) when is_map(data) do
    case data["speaker_sheet_id"] do
      value when is_integer(value) and value > 0 ->
        value

      value when is_binary(value) ->
        case Integer.parse(value) do
          {parsed, ""} when parsed > 0 -> parsed
          _invalid -> nil
        end

      _other ->
        nil
    end
  end

  defp normalize_speaker_id(_data), do: nil

  defp normalize_error(reason)
       when reason in [:not_found, :node_not_found, :flow_not_found, :project_not_found, :project_not_active],
       do: :not_found

  defp normalize_error({:invalid_project_reference, :speaker_sheet_id, _value}), do: :not_found

  defp normalize_error({:invalid_project_reference, :audio_asset_id, value}),
    do: {:invalid_project_reference, :audio_asset_id, value}

  defp normalize_error({:invalid_asset_content_type, :audio_asset_id, value}),
    do: {:invalid_project_reference, :audio_asset_id, value}

  defp normalize_error(_reason), do: :update_failed
end

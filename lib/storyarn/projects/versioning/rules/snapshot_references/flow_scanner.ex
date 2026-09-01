defmodule Storyarn.Projects.Versioning.SnapshotReferences.FlowScanner do
  @moduledoc "Extracts portable references from a Flow snapshot without I/O."

  use Gettext, backend: Storyarn.Gettext

  alias Storyarn.Projects.References.EntityReferenceExtraction
  alias Storyarn.Projects.References.RichTextMentions

  @spec scan(map()) :: [map()]
  def scan(snapshot) do
    refs = []

    refs =
      maybe_add_ref(refs, :scene, snapshot["scene_id"], dgettext("flows", "Flow backdrop scene"))

    refs =
      (snapshot["nodes"] || [])
      |> Enum.with_index(1)
      |> Enum.reduce(refs, fn {node, idx}, acc ->
        data = node["data"] || %{}
        type = node["type"] || "unknown"

        acc =
          acc
          |> maybe_add_ref(
            :sheet,
            data["speaker_sheet_id"],
            dgettext("flows", "Node #%{n} (%{type}) — speaker", n: idx, type: type)
          )
          |> maybe_add_ref(
            :sheet,
            data["location_sheet_id"],
            dgettext("flows", "Node #%{n} (%{type}) — location", n: idx, type: type)
          )
          |> maybe_add_ref(
            :flow,
            data["referenced_flow_id"],
            dgettext("flows", "Node #%{n} (%{type}) — referenced flow", n: idx, type: type)
          )
          |> maybe_add_asset_ref(
            data["audio_asset_id"],
            dgettext("flows", "Node #%{n} (%{type}) — audio", n: idx, type: type),
            "audio/"
          )
          |> maybe_add_avatar_ref(
            data["avatar_id"],
            data["speaker_sheet_id"],
            dgettext("flows", "Node #%{n} (%{type}) — avatar", n: idx, type: type)
          )
          |> add_flow_exit_target_ref(data, idx, type)
          |> add_flow_node_mention_refs(data, idx, type)

        add_sequence_asset_refs(acc, node, idx)
      end)

    add_localization_asset_refs(refs, snapshot)
  end

  defp maybe_add_ref(refs, _type, nil, _context), do: refs

  defp maybe_add_ref(refs, type, id, context), do: [%{type: type, id: id, context: context} | refs]

  defp maybe_add_asset_ref(refs, nil, _context, _expected_content_type_prefix), do: refs

  defp maybe_add_asset_ref(refs, id, context, expected_content_type_prefix) do
    [
      %{
        type: :asset,
        id: id,
        context: context,
        expected_content_type_prefix: expected_content_type_prefix
      }
      | refs
    ]
  end

  defp maybe_add_avatar_ref(refs, nil, _speaker_sheet_id, _context), do: refs

  defp maybe_add_avatar_ref(refs, avatar_id, speaker_sheet_id, context) do
    [
      %{
        type: :avatar,
        id: avatar_id,
        context: context,
        speaker_sheet_id: speaker_sheet_id
      }
      | refs
    ]
  end

  defp add_flow_exit_target_ref(refs, %{"target_type" => target_type, "target_id" => target_id}, node_index, type)
       when target_type in ["flow", "scene"] do
    maybe_add_ref(
      refs,
      String.to_existing_atom(target_type),
      target_id,
      dgettext("flows", "Node #%{n} (%{type}) — terminal target", n: node_index, type: type)
    )
  end

  defp add_flow_exit_target_ref(refs, _data, _node_index, _type), do: refs

  defp add_flow_node_mention_refs(refs, data, node_index, node_type) do
    context =
      dgettext("flows", "Node #%{n} (%{type}) — rich-text mention",
        n: node_index,
        type: node_type
      )

    data
    |> flow_node_mention_refs()
    |> Enum.reduce(refs, fn mention, acc ->
      [Map.put(mention, :context, context) | acc]
    end)
  end

  defp flow_node_mention_refs(data) do
    data
    |> RichTextMentions.html_candidates()
    |> Enum.flat_map(&flow_node_html_mention_refs/1)
  end

  defp flow_node_html_mention_refs(html) do
    case EntityReferenceExtraction.extract_block_value_references("rich_text", %{"content" => html}) do
      {:ok, references} -> Enum.map(references, &flow_node_mention_ref/1)
      {:error, reason} -> [%{type: :reference, id: malformed_flow_mention_id(reason)}]
    end
  end

  defp flow_node_mention_ref(reference), do: %{type: flow_mention_reference_type(reference.type), id: reference.id}

  defp flow_mention_reference_type("sheet"), do: :sheet
  defp flow_mention_reference_type("flow"), do: :flow

  defp malformed_flow_mention_id({:invalid_project_reference, _context, id})
       when is_integer(id) or is_binary(id) or is_nil(id), do: id

  defp malformed_flow_mention_id({:invalid_project_reference, _context, details}), do: inspect(details)
  defp malformed_flow_mention_id(_reason), do: nil

  defp add_sequence_asset_refs(refs, node, node_index) do
    refs =
      node
      |> snapshot_collection("sequence_tracks")
      |> Enum.with_index(1)
      |> Enum.reduce(refs, fn {track, track_index}, acc ->
        if is_map(track) do
          maybe_add_asset_ref(
            acc,
            track["asset_id"],
            dgettext("flows", "Node #%{n} sequence track #%{track} — audio",
              n: node_index,
              track: track_index
            ),
            "audio/"
          )
        else
          acc
        end
      end)

    node
    |> snapshot_collection("sequence_visual_layers")
    |> Enum.with_index(1)
    |> Enum.reduce(refs, fn {layer, layer_index}, acc ->
      if is_map(layer) do
        maybe_add_asset_ref(
          acc,
          layer["asset_id"],
          dgettext("flows", "Node #%{n} sequence visual layer #%{layer}",
            n: node_index,
            layer: layer_index
          ),
          "image/"
        )
      else
        acc
      end
    end)
  end

  defp add_localization_asset_refs(refs, snapshot) do
    snapshot
    |> snapshot_collection("localization")
    |> Enum.with_index(1)
    |> Enum.reduce(refs, fn
      {%{} = row, index}, acc ->
        acc
        |> maybe_add_asset_ref(
          row["vo_asset_id"],
          dgettext("flows", "Localization row #%{n} — voice-over", n: index),
          "audio/"
        )
        |> maybe_add_ref(
          :sheet,
          row["speaker_sheet_id"],
          dgettext("flows", "Localization row #%{n} — speaker", n: index)
        )

      {_row, _index}, acc ->
        acc
    end)
  end

  defp snapshot_collection(snapshot, key) when is_map(snapshot) do
    case Map.get(snapshot, key, []) do
      collection when is_list(collection) -> collection
      _malformed -> []
    end
  end

  defp snapshot_collection(_snapshot, _key), do: []
end

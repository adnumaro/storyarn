defmodule Storyarn.Flows.Versioning.Execution.ReferenceScanner do
  @moduledoc false

  use Gettext, backend: Storyarn.Gettext

  alias Storyarn.Flows.References

  def scan(snapshot) when is_map(snapshot) do
    refs =
      maybe_add_ref(
        [],
        :scene,
        snapshot["scene_id"],
        dgettext("flows", "Flow backdrop scene")
      )

    refs =
      snapshot
      |> collection("nodes")
      |> Enum.with_index(1)
      |> Enum.reduce(refs, fn {node, index}, acc -> scan_node(node, index, acc) end)

    scan_localization(snapshot, refs)
  end

  def scan(_snapshot), do: []

  defp scan_node(node, index, refs) when is_map(node) do
    data = node["data"] || %{}
    type = node["type"] || "unknown"

    refs
    |> maybe_add_ref(
      :sheet,
      data["speaker_sheet_id"],
      dgettext("flows", "Node #%{n} (%{type}) — speaker", n: index, type: type)
    )
    |> maybe_add_ref(
      :sheet,
      data["location_sheet_id"],
      dgettext("flows", "Node #%{n} (%{type}) — location", n: index, type: type)
    )
    |> maybe_add_ref(
      :flow,
      data["referenced_flow_id"],
      dgettext("flows", "Node #%{n} (%{type}) — referenced flow", n: index, type: type)
    )
    |> maybe_add_asset(
      data["audio_asset_id"],
      dgettext("flows", "Node #%{n} (%{type}) — audio", n: index, type: type),
      "audio/"
    )
    |> maybe_add_avatar(
      data["avatar_id"],
      data["speaker_sheet_id"],
      dgettext("flows", "Node #%{n} (%{type}) — avatar", n: index, type: type)
    )
    |> scan_exit_target(data, index, type)
    |> scan_mentions(data, index, type)
    |> scan_sequence_assets(node, index)
  end

  defp scan_node(_node, _index, refs), do: refs

  defp maybe_add_ref(refs, _type, nil, _context), do: refs
  defp maybe_add_ref(refs, type, id, context), do: [%{type: type, id: id, context: context} | refs]

  defp maybe_add_asset(refs, nil, _context, _prefix), do: refs

  defp maybe_add_asset(refs, id, context, prefix) do
    [%{type: :asset, id: id, context: context, expected_content_type_prefix: prefix} | refs]
  end

  defp maybe_add_avatar(refs, nil, _speaker_sheet_id, _context), do: refs

  defp maybe_add_avatar(refs, id, speaker_sheet_id, context) do
    [%{type: :avatar, id: id, speaker_sheet_id: speaker_sheet_id, context: context} | refs]
  end

  defp scan_exit_target(refs, %{"target_type" => target_type, "target_id" => id}, index, type)
       when target_type in ["flow", "scene"] do
    maybe_add_ref(
      refs,
      String.to_existing_atom(target_type),
      id,
      dgettext("flows", "Node #%{n} (%{type}) — terminal target", n: index, type: type)
    )
  end

  defp scan_exit_target(refs, _data, _index, _type), do: refs

  defp scan_mentions(refs, data, index, type) do
    context =
      dgettext("flows", "Node #%{n} (%{type}) — rich-text mention",
        n: index,
        type: type
      )

    data
    |> References.rich_text_html_candidates()
    |> Enum.reduce(refs, &scan_mentions_from_html(&1, context, &2))
  end

  defp scan_mentions_from_html(html, context, refs) do
    case References.extract_rich_text_mentions(html) do
      {:ok, mentions} ->
        Enum.reduce(mentions, refs, fn mention, mention_refs ->
          [%{type: mention_type(mention.type), id: mention.id, context: context} | mention_refs]
        end)

      {:error, reason} ->
        [%{type: :reference, id: malformed_mention_id(reason), context: context} | refs]
    end
  end

  defp mention_type("sheet"), do: :sheet
  defp mention_type("flow"), do: :flow

  defp malformed_mention_id({:invalid_mention, %{id: [id]}}), do: id
  defp malformed_mention_id({:invalid_mention, details}), do: inspect(details)
  defp malformed_mention_id(_reason), do: nil

  defp scan_sequence_assets(refs, node, node_index) do
    refs =
      node
      |> collection("sequence_tracks")
      |> Enum.with_index(1)
      |> Enum.reduce(refs, fn
        {%{} = track, track_index}, acc ->
          maybe_add_asset(
            acc,
            track["asset_id"],
            dgettext("flows", "Node #%{n} sequence track #%{track} — audio",
              n: node_index,
              track: track_index
            ),
            "audio/"
          )

        {_track, _track_index}, acc ->
          acc
      end)

    node
    |> collection("sequence_visual_layers")
    |> Enum.with_index(1)
    |> Enum.reduce(refs, fn
      {%{} = layer, layer_index}, acc ->
        maybe_add_asset(
          acc,
          layer["asset_id"],
          dgettext("flows", "Node #%{n} sequence visual layer #%{layer}",
            n: node_index,
            layer: layer_index
          ),
          "image/"
        )

      {_layer, _layer_index}, acc ->
        acc
    end)
  end

  defp scan_localization(snapshot, refs) do
    snapshot
    |> collection("localization")
    |> Enum.with_index(1)
    |> Enum.reduce(refs, fn
      {%{} = row, index}, acc ->
        acc
        |> maybe_add_asset(
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

  defp collection(snapshot, key) when is_map(snapshot) do
    case Map.get(snapshot, key, []) do
      values when is_list(values) -> values
      _malformed -> []
    end
  end

  defp collection(_snapshot, _key), do: []
end

defmodule Storyarn.Projects.Versioning.SnapshotReferences.SceneScanner do
  @moduledoc "Extracts portable references from a Scene snapshot without I/O."

  use Gettext, backend: Storyarn.Gettext

  @target_type_mapping %{
    "sheet" => :sheet,
    "flow" => :flow,
    "scene" => :scene
  }

  @spec scan(map()) :: [map()]
  def scan(snapshot) do
    refs = []

    refs =
      maybe_add_ref(
        refs,
        :asset,
        snapshot["background_asset_id"],
        dgettext("scenes", "Background image")
      )

    refs =
      (snapshot["layers"] || [])
      |> Enum.with_index(1)
      |> Enum.reduce(refs, fn {layer, layer_idx}, acc ->
        acc
        |> scan_pin_refs(layer["pins"] || [], layer_idx)
        |> scan_zone_refs(layer["zones"] || [], layer_idx)
      end)
      |> scan_orphan_pin_refs(snapshot["orphan_pins"] || [])
      |> scan_orphan_zone_refs(snapshot["orphan_zones"] || [])
      |> scan_ambient_flow_refs(snapshot["ambient_flows"] || [])

    refs
  end

  defp scan_pin_refs(refs, pins, layer_idx) do
    pins
    |> Enum.with_index(1)
    |> Enum.reduce(refs, fn {pin, pin_idx}, acc ->
      prefix =
        dgettext("scenes", "Layer %{l}, Pin %{p}", l: layer_idx, p: pin_idx)

      acc
      |> maybe_add_ref(:sheet, pin["sheet_id"], prefix <> " — sheet")
      |> maybe_add_ref(:asset, pin["icon_asset_id"], prefix <> " — icon asset")
      |> maybe_add_ref(:flow, pin["flow_id"], prefix <> " — flow")
    end)
  end

  defp scan_zone_refs(refs, zones, layer_idx) do
    zones
    |> Enum.with_index(1)
    |> Enum.reduce(refs, fn {zone, zone_idx}, acc ->
      prefix =
        dgettext("scenes", "Layer %{l}, Zone %{z}", l: layer_idx, z: zone_idx)

      acc
      |> maybe_add_target_ref(zone["target_type"], zone["target_id"], prefix <> " — target")
      |> maybe_add_ref(:asset, zone["label_icon_asset_id"], prefix <> " — label icon")
      |> scan_zone_collection_sheet_refs(zone, prefix)
    end)
  end

  defp scan_orphan_pin_refs(refs, pins) do
    pins
    |> Enum.with_index(1)
    |> Enum.reduce(refs, fn {pin, pin_idx}, acc ->
      prefix = dgettext("scenes", "Scene Pin %{p}", p: pin_idx)

      acc
      |> maybe_add_ref(:sheet, pin["sheet_id"], prefix <> " — sheet")
      |> maybe_add_ref(:asset, pin["icon_asset_id"], prefix <> " — icon asset")
      |> maybe_add_ref(:flow, pin["flow_id"], prefix <> " — flow")
    end)
  end

  defp scan_orphan_zone_refs(refs, zones) do
    zones
    |> Enum.with_index(1)
    |> Enum.reduce(refs, fn {zone, zone_idx}, acc ->
      prefix = dgettext("scenes", "Scene Zone %{z}", z: zone_idx)

      acc
      |> maybe_add_target_ref(zone["target_type"], zone["target_id"], prefix <> " — target")
      |> maybe_add_ref(:asset, zone["label_icon_asset_id"], prefix <> " — label icon")
      |> scan_zone_collection_sheet_refs(zone, prefix)
    end)
  end

  defp scan_zone_collection_sheet_refs(
         refs,
         %{"action_type" => "collection", "action_data" => %{"items" => items}},
         prefix
       )
       when is_list(items) do
    items
    |> Enum.with_index(1)
    |> Enum.reduce(refs, fn
      {%{"sheet_id" => sheet_id}, item_index}, acc ->
        maybe_add_ref(
          acc,
          :sheet,
          sheet_id,
          prefix <>
            dgettext(
              "scenes",
              " — collection item %{item} sheet",
              item: item_index
            )
        )

      {_item, _item_index}, acc ->
        acc
    end)
  end

  defp scan_zone_collection_sheet_refs(refs, _zone, _prefix), do: refs

  defp scan_ambient_flow_refs(refs, ambient_flows) do
    ambient_flows
    |> Enum.with_index(1)
    |> Enum.reduce(refs, fn {ambient_flow, index}, acc ->
      maybe_add_ref(
        acc,
        :flow,
        ambient_flow["flow_id"],
        dgettext("scenes", "Ambient flow %{index}", index: index)
      )
    end)
  end

  defp maybe_add_target_ref(refs, target_type, target_id, context) do
    case Map.get(@target_type_mapping, target_type) do
      nil -> refs
      type -> maybe_add_ref(refs, type, target_id, context)
    end
  end

  defp maybe_add_ref(refs, _type, nil, _context), do: refs

  defp maybe_add_ref(refs, type, id, context), do: [%{type: type, id: id, context: context} | refs]
end

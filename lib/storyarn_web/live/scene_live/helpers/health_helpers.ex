defmodule StoryarnWeb.SceneLive.Helpers.HealthHelpers do
  @moduledoc """
  Builds the enriched snapshot used by the scene health checker and serializes
  its findings for the Vue header.
  """

  import Phoenix.Component, only: [assign: 3]

  alias Storyarn.Scenes.HealthChecker

  @empty_health %{errorItems: [], warningItems: [], infoItems: []}

  @doc "Returns an empty health payload suitable for the initial socket assign."
  def empty_health, do: @empty_health

  @doc "Checks the current scene assigns and stores their grouped UI payload."
  def assign_scene_health(%{assigns: %{scene: nil}} = socket), do: assign(socket, :scene_health, @empty_health)

  def assign_scene_health(socket) do
    assigns = socket.assigns
    collections = scene_collections(assigns)
    snapshot = health_snapshot(assigns, collections)
    findings = HealthChecker.check(snapshot)

    assign(
      socket,
      :scene_health,
      health_payload(
        findings,
        assigns.scene,
        collections.layers,
        collections.zones,
        collections.pins,
        collections.connections,
        collections.annotations,
        collections.ambient_flows
      )
    )
  end

  defp scene_collections(assigns) do
    %{
      layers: list(assigns.layers),
      zones: list(assigns.zones),
      pins: list(assigns.pins),
      connections: list(assigns.connections),
      annotations: list(assigns.annotations),
      ambient_flows: list(assigns.ambient_flows)
    }
  end

  defp health_snapshot(assigns, collections) do
    %{
      scene: assigns.scene,
      layers: collections.layers,
      zones: collections.zones,
      pins: collections.pins,
      connections: collections.connections,
      annotations: collections.annotations,
      ambient_flows: collections.ambient_flows,
      scene_layer_ids: MapSet.new(collections.layers, & &1.id),
      scene_pin_ids: MapSet.new(collections.pins, & &1.id),
      references_loaded: assigns.health_references_loaded,
      valid_scene_ids: MapSet.new(list(assigns.project_scenes), & &1.id),
      valid_sheet_ids: assigns.project_sheets |> flatten_tree() |> MapSet.new(& &1.id),
      valid_flow_ids: MapSet.new(list(assigns.project_flows), & &1.id),
      valid_asset_ids: MapSet.new(list(assigns.project_asset_ids)),
      project_variables: list(assigns.project_variables)
    }
  end

  @doc "Serializes checker findings into stable, grouped UI payloads."
  def health_payload(findings, scene, layers, zones, pins, connections, annotations, ambient_flows) do
    context = label_context(scene, layers, zones, pins, connections, annotations, ambient_flows)

    %{
      errorItems: health_items(findings, :error, context),
      warningItems: health_items(findings, :warning, context),
      infoItems: health_items(findings, :info, context)
    }
  end

  defp health_items(findings, severity, context) do
    findings
    |> Enum.filter(&(&1.severity == severity))
    |> Enum.group_by(&{&1.entity_type, &1.entity_id})
    |> Enum.map(fn {_location, grouped_findings} -> health_item(grouped_findings, context) end)
    |> Enum.sort_by(&{&1.entityType == "scene", &1.label, to_string(&1.entityId || "")})
  end

  defp health_item([finding | _] = findings, context) do
    %{
      entityType: finding.entity_type,
      entityId: finding.entity_id,
      label: health_label(finding, context),
      reasons:
        Enum.map(findings, fn item ->
          %{code: Atom.to_string(item.code), details: item.details}
        end)
    }
  end

  defp health_label(%{entity_type: "scene"}, context), do: context.scene_name

  defp health_label(%{entity_type: entity_type, entity_id: entity_id, details: details}, context) do
    case entity_type do
      "collection_item" ->
        item_label = Map.get(context.collection_items, entity_id, "Item #{entity_id}")
        zone_label = Map.get(context.zones, details[:zone_id] || details["zone_id"], "Collection")
        "#{zone_label} · #{item_label}"

      _ ->
        context.labels
        |> Map.get(entity_type, %{})
        |> Map.get(entity_id, fallback_label(entity_type, entity_id))
    end
  end

  defp label_context(scene, layers, zones, pins, connections, annotations, ambient_flows) do
    %{
      scene_name: present_label(scene.name, "Scene"),
      zones: label_map(zones, :name, "Zone"),
      collection_items: collection_item_labels(zones),
      labels: %{
        "layer" => label_map(layers, :name, "Layer"),
        "zone" => label_map(zones, :name, "Zone"),
        "pin" => label_map(pins, :label, "Pin"),
        "connection" => label_map(connections, :label, "Connection"),
        "annotation" => label_map(annotations, :text, "Annotation"),
        "ambient_flow" => ambient_flow_labels(ambient_flows)
      }
    }
  end

  defp label_map(items, field, fallback) do
    Map.new(items || [], fn item ->
      {item.id, present_label(Map.get(item, field), "#{fallback} ##{item.id}")}
    end)
  end

  defp ambient_flow_labels(ambient_flows) do
    Map.new(ambient_flows || [], fn ambient_flow ->
      flow_name = get_in(ambient_flow, [Access.key(:flow), Access.key(:name)])
      {ambient_flow.id, present_label(flow_name, "Ambient flow ##{ambient_flow.id}")}
    end)
  end

  defp collection_item_labels(zones) do
    zones
    |> Enum.flat_map(fn zone ->
      zone
      |> Map.get(:action_data, %{})
      |> Map.get("items", [])
      |> case do
        items when is_list(items) -> items
        _ -> []
      end
    end)
    |> Enum.filter(&is_map/1)
    |> Map.new(fn item ->
      id = item["id"]
      {id, present_label(item["label"], "Item #{id}")}
    end)
  end

  defp flatten_tree(nil), do: []

  defp flatten_tree(items) when is_list(items) do
    Enum.flat_map(items, fn item ->
      [item | flatten_tree(Map.get(item, :children, []))]
    end)
  end

  defp flatten_tree(_), do: []

  defp list(value) when is_list(value), do: value
  defp list(_value), do: []

  defp present_label(value, fallback) when is_binary(value) do
    if String.trim(value) == "", do: fallback, else: value
  end

  defp present_label(_value, fallback), do: fallback

  defp fallback_label(entity_type, entity_id) do
    entity_type |> String.replace("_", " ") |> String.capitalize() |> Kernel.<>(" ##{entity_id}")
  end
end

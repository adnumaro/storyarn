defmodule StoryarnWeb.SceneLive.Helpers.HealthHelpers do
  @moduledoc """
  Builds the enriched snapshot used by the scene health checker and serializes
  its findings for the Vue header.

  The check itself runs through `Scenes.scene_health_findings/3` — the same
  composition point the project-wide dashboard sweep enters — so the editor and
  the dashboard cannot feed the checker differently for the same scene.
  """

  use Gettext, backend: Storyarn.Gettext

  import Phoenix.Component, only: [assign: 3]

  alias Storyarn.Platform.Shared.StringUtils
  alias Storyarn.Scenes
  alias StoryarnWeb.SceneLive.Helpers.SceneHelpers

  @empty_health %{errorItems: [], warningItems: [], infoItems: []}

  @doc "Returns an empty health payload suitable for the initial socket assign."
  def empty_health, do: @empty_health

  @doc "Checks the current scene assigns and stores their grouped UI payload."
  def assign_scene_health(%{assigns: %{scene: nil}} = socket), do: assign(socket, :scene_health, @empty_health)

  def assign_scene_health(socket) do
    assigns = socket.assigns
    collections = scene_collections(assigns)
    findings = Scenes.scene_health_findings(assigns.scene, collections, health_references(assigns))

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

  # `health_references_loaded` stays the gate: until the async sidebar load
  # lands, every project reference set is empty and reporting them as stale
  # would flag the whole scene.
  defp health_references(assigns) do
    Scenes.scene_health_references(%{
      loaded?: assigns.health_references_loaded,
      scene_ids: entity_ids(assigns.project_scenes),
      sheet_ids: assigns.project_sheets |> flatten_tree() |> Enum.map(& &1.id),
      flow_ids: entity_ids(assigns.project_flows),
      asset_ids: list(assigns.project_asset_ids),
      variables: list(assigns.project_variables)
    })
  end

  defp entity_ids(entities), do: entities |> list() |> Enum.map(& &1.id)

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

  # The Scenes health contract builds every `details` map with atom keys —
  # `finding/2` is its only constructor and no caller outside it supplies one —
  # so `details[:zone_id]` is the whole access, not half of it.
  defp health_label(%{entity_type: "collection_item", entity_id: entity_id, details: details}, context) do
    zone_id = details[:zone_id]
    item_label = Map.get(context.collection_items, entity_id, element_label("collection_item", entity_id))
    zone_label = Map.get(context.zones, zone_id, element_label("zone", zone_id))
    "#{zone_label} · #{item_label}"
  end

  defp health_label(%{entity_type: entity_type, entity_id: entity_id}, context) do
    context.labels
    |> Map.get(entity_type, %{})
    |> Map.get(entity_id, element_label(entity_type, entity_id))
  end

  defp label_context(scene, layers, zones, pins, connections, annotations, ambient_flows) do
    %{
      scene_name: StringUtils.present_label(scene.name, SceneHelpers.element_type_label("scene")),
      zones: label_map(zones, :name, "zone"),
      collection_items: collection_item_labels(zones),
      labels: %{
        "layer" => label_map(layers, :name, "layer"),
        "zone" => label_map(zones, :name, "zone"),
        "pin" => label_map(pins, :label, "pin"),
        "connection" => label_map(connections, :label, "connection"),
        "annotation" => label_map(annotations, :text, "annotation"),
        "ambient_flow" => ambient_flow_labels(ambient_flows)
      }
    }
  end

  defp label_map(items, field, entity_type) do
    Map.new(items || [], fn item ->
      {item.id, StringUtils.present_label(Map.get(item, field), element_label(entity_type, item.id))}
    end)
  end

  defp ambient_flow_labels(ambient_flows) do
    Map.new(ambient_flows || [], fn ambient_flow ->
      flow_name = get_in(ambient_flow, [Access.key(:flow), Access.key(:name)])
      {ambient_flow.id, StringUtils.present_label(flow_name, element_label("ambient_flow", ambient_flow.id))}
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
      {id, StringUtils.present_label(item["label"], element_label("collection_item", id))}
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

  # "Zona #12" — the element's type plus its id, for anything the author never
  # named. Same shape as the flows sibling's `"%{type} #%{id}"`.
  defp element_label(entity_type, entity_id) do
    dgettext("scenes", "%{type} #%{id}",
      type: SceneHelpers.element_type_label(entity_type),
      id: entity_id
    )
  end
end

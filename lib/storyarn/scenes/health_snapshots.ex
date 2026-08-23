defmodule Storyarn.Scenes.HealthSnapshots do
  @moduledoc """
  Builds the enriched snapshots `Storyarn.Scenes.HealthChecker` consumes, and is
  the one composition point both scene health surfaces enter through.

  One constructor, two feeders. The editor holds a single scene and its elements
  in socket assigns; the dashboard needs every scene of a project. Both call
  `findings/3`, so the snapshot shape cannot drift between the two surfaces —
  which is what lets them report the same findings for the same scene.

  `load_project/1` pays a FIXED number of queries for a whole project (one per
  element table plus the shared project references), never one round trip per
  scene: O(1) in queries, O(N) in CPU. Measured on the dev DB it is 14 queries
  for 1 scene and the same 14 for 201.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Repo
  alias Storyarn.Scenes.HealthChecker
  alias Storyarn.Scenes.Instruction
  alias Storyarn.Scenes.Persistence.AssetRecord
  alias Storyarn.Scenes.Persistence.FlowRecord
  alias Storyarn.Scenes.Persistence.SheetRecord
  alias Storyarn.Scenes.Scene
  alias Storyarn.Scenes.SceneAmbientFlow
  alias Storyarn.Scenes.SceneAnnotation
  alias Storyarn.Scenes.SceneConnection
  alias Storyarn.Scenes.SceneCrud
  alias Storyarn.Scenes.SceneLayer
  alias Storyarn.Scenes.ScenePin
  alias Storyarn.Scenes.SceneZone
  alias Storyarn.Scenes.VariableCatalog

  @collection_keys [:layers, :zones, :pins, :connections, :annotations, :ambient_flows]

  # The entity_type -> naming column table. A finding carries a code and an
  # entity id; a project-wide list also has to say WHICH pin, so this is where
  # "a pin is named by `label`, a zone by `name`" lives.
  @label_fields [
    {"zone", :zones, :name},
    {"pin", :pins, :label},
    {"connection", :connections, :label},
    {"annotation", :annotations, :text}
  ]

  @type collections :: %{optional(atom()) => list()}
  @type references :: %{
          loaded?: boolean(),
          scene_ids: MapSet.t(),
          sheet_ids: MapSet.t(),
          flow_ids: MapSet.t(),
          asset_ids: MapSet.t(),
          variables: list()
        }
  @type entry :: %{
          scene: Scene.t(),
          collections: collections(),
          references: references(),
          labels: %{{String.t(), term()} => String.t()}
        }

  @doc """
  Checks one scene: build its snapshot, then run the canonical checker.

  `collections` holds this scene's own elements, `references` the project-wide
  reference sets from `references/1`. The `references_loaded` gate is passed
  through verbatim: a caller that has not loaded the project references yet
  must say so, and every reference-integrity check then stays silent instead of
  reporting every reference as stale.
  """
  @spec findings(map(), collections(), references()) :: [HealthChecker.finding()]
  def findings(scene, collections, references) do
    scene |> build(collections, references) |> HealthChecker.check()
  end

  defp build(scene, collections, references) do
    layers = collection(collections, :layers)
    pins = collection(collections, :pins)

    %{
      scene: scene,
      layers: layers,
      zones: collection(collections, :zones),
      pins: pins,
      connections: collection(collections, :connections),
      annotations: collection(collections, :annotations),
      ambient_flows: collection(collections, :ambient_flows),
      scene_layer_ids: MapSet.new(layers, & &1.id),
      scene_pin_ids: MapSet.new(pins, & &1.id),
      references_loaded: references.loaded?,
      valid_scene_ids: references.scene_ids,
      valid_sheet_ids: references.sheet_ids,
      valid_flow_ids: references.flow_ids,
      valid_asset_ids: references.asset_ids,
      project_variables: references.variables,
      # Built ONCE per scene rather than once per zone, pin and collection item:
      # the checker's `variable_types/1` reads this key when it is present, and
      # `Instruction.has_type_warnings?/2` now takes the prepared map for the
      # same reason. `Instruction.variable_type_map/1` is the one builder — the
      # key format decides whether a reference is stale, so both scene surfaces
      # and the flow checkers must spell it identically.
      variable_types: Instruction.variable_type_map(references.variables)
    }
  end

  @doc """
  Normalizes the project-wide reference sets `findings/3` expects.

  The editor reads them from socket assigns filled by an async load, the
  dashboard from batched queries; this is where the two become the same thing.
  Accepts either MapSets or plain id enumerables.
  """
  @spec references(map()) :: references()
  def references(attrs) when is_map(attrs) do
    %{
      loaded?: Map.get(attrs, :loaded?, false) == true,
      scene_ids: id_set(attrs[:scene_ids]),
      sheet_ids: id_set(attrs[:sheet_ids]),
      flow_ids: id_set(attrs[:flow_ids]),
      asset_ids: id_set(attrs[:asset_ids]),
      variables: list(attrs[:variables])
    }
  end

  @doc """
  Loads the `findings/3` inputs for every active scene of a project, in sidebar
  order.

  Each entry also carries the `labels` its findings need, derived from the
  elements already in memory rather than from extra queries.
  """
  @spec load_project(pos_integer()) :: [entry()]
  def load_project(project_id) do
    scenes = SceneCrud.list_scenes(project_id)
    flow_names = flow_names(project_id)
    collections = load_collections(Enum.map(scenes, & &1.id))
    references = load_references(project_id, scenes, flow_names)

    Enum.map(scenes, fn scene ->
      scene_collections = collections_for(collections, scene.id)

      %{
        scene: scene,
        collections: scene_collections,
        references: references,
        labels: labels(scene_collections, flow_names)
      }
    end)
  end

  # ===========================================================================
  # Project references
  # ===========================================================================

  defp load_references(project_id, scenes, flow_names) do
    references(%{
      loaded?: true,
      scene_ids: Enum.map(scenes, & &1.id),
      sheet_ids: active_ids(SheetRecord, project_id),
      flow_ids: Map.keys(flow_names),
      asset_ids: active_image_asset_ids(project_id),
      # The ONE definition of what a reference can point at: sheet block and
      # table variables plus the pin and zone boolean properties. The editor
      # reaches it through `VariableHelpers.list_all_variables/1`, which
      # delegates to the same function; a surface that only read sheet variables
      # would report every pin/zone property reference as stale.
      variables: VariableCatalog.list_referenceable(project_id)
    })
  end

  defp active_ids(schema, project_id) do
    Repo.all(from(e in schema, where: e.project_id == ^project_id and is_nil(e.deleted_at), select: e.id))
  end

  defp active_image_asset_ids(project_id) do
    Repo.all(
      from asset in AssetRecord,
        where:
          asset.project_id == ^project_id and is_nil(asset.deleted_at) and
            ilike(asset.content_type, "image/%"),
        select: asset.id
    )
  end

  defp flow_names(project_id) do
    from(f in FlowRecord,
      where: f.project_id == ^project_id and is_nil(f.deleted_at),
      select: {f.id, f.name}
    )
    |> Repo.all()
    |> Map.new()
  end

  # ===========================================================================
  # Scene elements
  # ===========================================================================

  defp load_collections([]), do: %{}

  # Every order ends in `:id`. `position` is not unique — elements created
  # together share it — and findings are emitted in element order, so without a
  # total order two equally named elements swap their dashboard rows, and their
  # deep links with them, between runs.
  defp load_collections(scene_ids) do
    %{
      layers: grouped(SceneLayer, scene_ids, asc: :position, asc: :id),
      zones: grouped(SceneZone, scene_ids, asc: :position, asc: :id),
      pins: grouped(ScenePin, scene_ids, asc: :position, asc: :id),
      connections: grouped(SceneConnection, scene_ids, asc: :id),
      annotations: grouped(SceneAnnotation, scene_ids, asc: :position, asc: :id),
      ambient_flows: grouped(SceneAmbientFlow, scene_ids, asc: :position, desc: :priority, asc: :id)
    }
  end

  defp grouped(schema, scene_ids, order) do
    from(e in schema, where: e.scene_id in ^scene_ids, order_by: ^order)
    |> Repo.all()
    |> Enum.group_by(& &1.scene_id)
  end

  defp collections_for(collections, scene_id) do
    Map.new(@collection_keys, fn key ->
      {key, collections |> Map.get(key, %{}) |> Map.get(scene_id, [])}
    end)
  end

  # ===========================================================================
  # Entity labels
  # ===========================================================================

  defp labels(collections, flow_names) do
    element_labels =
      for {entity_type, key, field} <- @label_fields,
          element <- collection(collections, key),
          label = present(Map.get(element, field)),
          into: %{},
          do: {{entity_type, element.id}, label}

    element_labels
    |> Map.merge(ambient_flow_labels(collection(collections, :ambient_flows), flow_names))
    |> Map.merge(collection_item_labels(collection(collections, :zones)))
  end

  defp ambient_flow_labels(ambient_flows, flow_names) do
    for ambient_flow <- ambient_flows,
        label = present(Map.get(flow_names, ambient_flow.flow_id)),
        into: %{},
        do: {{"ambient_flow", ambient_flow.id}, label}
  end

  defp collection_item_labels(zones) do
    for zone <- zones,
        items = zone |> Map.get(:action_data) |> items(),
        item <- items,
        is_map(item),
        label = present(item["label"]),
        into: %{},
        do: {{"collection_item", item["id"]}, label}
  end

  defp items(%{"items" => items}) when is_list(items), do: items
  defp items(_action_data), do: []

  # ===========================================================================
  # Normalization
  # ===========================================================================

  defp collection(collections, key), do: collections |> Map.get(key) |> list()

  defp list(value) when is_list(value), do: value
  defp list(_value), do: []

  defp id_set(%MapSet{} = set), do: set
  defp id_set(ids) when is_list(ids), do: MapSet.new(ids)
  defp id_set(_ids), do: MapSet.new()

  defp present(value) when is_binary(value) do
    if String.trim(value) == "", do: nil, else: value
  end

  defp present(_value), do: nil
end

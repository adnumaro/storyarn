defmodule Storyarn.Scenes do
  @moduledoc """
  The Scenes context.

  Manages scenes (visual world-building canvases), layers, zones, pins,
  and connections within a project. Scenes provide a spatial interface
  to navigate and understand the narrative world.

  This module serves as a facade, delegating to specialized submodules:
  - `SceneCrud` - CRUD operations for scenes
  - `LayerCrud` - CRUD operations for layers
  - `ZoneCrud` - CRUD operations for zones
  - `PinCrud` - CRUD operations for pins
  - `ConnectionCrud` - CRUD operations for connections
  - `TreeOperations` - Reorder and move operations
  """

  alias Storyarn.Repo
  alias Storyarn.Scenes.AmbientFlowCrud
  alias Storyarn.Scenes.AnnotationCrud
  alias Storyarn.Scenes.AssetCatalog
  alias Storyarn.Scenes.AssetCommands
  alias Storyarn.Scenes.ConnectionCrud
  alias Storyarn.Scenes.Events
  alias Storyarn.Scenes.ExplorationSessionCrud
  alias Storyarn.Scenes.FlowCatalog
  alias Storyarn.Scenes.FlowRuntime.ConditionEval
  alias Storyarn.Scenes.FlowRuntime.Engine
  alias Storyarn.Scenes.FlowRuntime.EngineHelpers
  alias Storyarn.Scenes.FlowRuntime.FormulaRuntime
  alias Storyarn.Scenes.FlowRuntime.InstructionExec
  alias Storyarn.Scenes.FlowRuntime.PlayerEngine
  alias Storyarn.Scenes.FlowRuntime.Slide
  alias Storyarn.Scenes.FlowRuntime.Variables
  alias Storyarn.Scenes.HealthSnapshots
  alias Storyarn.Scenes.LayerCrud
  alias Storyarn.Scenes.Limits
  alias Storyarn.Scenes.PinCrud
  alias Storyarn.Scenes.ProjectAccess
  alias Storyarn.Scenes.RoutePoints
  alias Storyarn.Scenes.Scene
  alias Storyarn.Scenes.SceneAmbientFlow
  alias Storyarn.Scenes.SceneAnnotation
  alias Storyarn.Scenes.SceneConnection
  alias Storyarn.Scenes.SceneCrud
  alias Storyarn.Scenes.SceneLayer
  alias Storyarn.Scenes.ScenePin
  alias Storyarn.Scenes.SceneStats
  alias Storyarn.Scenes.SceneZone
  alias Storyarn.Scenes.Severity
  alias Storyarn.Scenes.SheetCatalog
  alias Storyarn.Scenes.TrackedCommands
  alias Storyarn.Scenes.TreeOperations
  alias Storyarn.Scenes.VariableCatalog
  alias Storyarn.Scenes.Versioning
  alias Storyarn.Scenes.ZoneCrud
  alias Storyarn.Scenes.ZoneImageExtractor

  # =============================================================================
  # Type Definitions
  # =============================================================================

  @type scene_record :: Scene.t()
  @type layer :: SceneLayer.t()
  @type zone :: SceneZone.t()
  @type pin :: ScenePin.t()
  @type connection :: SceneConnection.t()
  @type annotation :: SceneAnnotation.t()
  @type ambient_flow :: SceneAmbientFlow.t()
  @type changeset :: Ecto.Changeset.t()
  @type attrs :: map()

  # =============================================================================
  # Scenes - CRUD Operations
  # =============================================================================

  @doc """
  Lists all non-deleted scenes for a project.
  Returns scenes ordered by position then name.
  """
  @spec list_scenes(integer()) :: [scene_record()]
  defdelegate list_scenes(project_id), to: SceneCrud

  @doc """
  Lists scenes as a tree structure.
  Returns root-level scenes with their children preloaded recursively.
  """
  @spec list_scenes_tree(integer()) :: [scene_record()]
  defdelegate list_scenes_tree(project_id), to: SceneCrud

  @doc """
  Searches scenes by name or shortcut for reference selection.
  Returns scenes matching the query, limited to 10 results.
  """
  @spec search_scenes(integer(), String.t(), keyword()) :: [scene_record()]
  defdelegate search_scenes(project_id, query, opts \\ []), to: SceneCrud

  @doc "Searches scene metadata and authored layer, pin, zone, and annotation text."
  @spec search_scenes_deep(integer(), String.t(), keyword()) :: [scene_record()]
  defdelegate search_scenes_deep(project_id, query, opts \\ []), to: SceneCrud

  @doc """
  Gets a single scene by ID within a project, with all associations preloaded.
  Returns `nil` if the scene doesn't exist or doesn't belong to the project.
  """
  @spec get_scene(integer(), integer()) :: scene_record() | nil
  defdelegate get_scene(project_id, scene_id), to: SceneCrud

  @doc """
  Gets a single scene by ID within a project, with all associations preloaded.
  Raises `Ecto.NoResultsError` if not found.
  """
  @spec get_scene!(integer(), integer()) :: scene_record()
  defdelegate get_scene!(project_id, scene_id), to: SceneCrud

  @doc """
  Gets a scene with only basic fields (no preloads).
  Used for breadcrumbs and lightweight lookups.
  """
  @spec get_scene_brief(integer(), integer()) :: scene_record() | nil
  defdelegate get_scene_brief(project_id, scene_id), to: SceneCrud

  @doc """
  Gets a scene by project_id and scene_id, including soft-deleted records.
  """
  @spec get_scene_including_deleted(integer(), integer()) :: scene_record() | nil
  defdelegate get_scene_including_deleted(project_id, scene_id), to: SceneCrud

  @doc """
  Creates a new scene in a project.
  Auto-creates a default layer and generates a shortcut from the name.
  """
  @spec create_scene(map() | integer(), attrs()) :: {:ok, scene_record()} | {:error, changeset()}
  defdelegate create_scene(project, attrs), to: SceneCrud
  defdelegate create_scene(actor_scope, project, attrs), to: SceneCrud

  @doc false
  defdelegate create_scene_in_transaction(project, attrs), to: SceneCrud
  defdelegate create_scene_in_transaction(actor_scope, project, attrs), to: SceneCrud

  @doc """
  Updates a scene.
  Auto-regenerates shortcut on name change.
  """
  @spec update_scene(scene_record(), attrs()) :: {:ok, scene_record()} | {:error, changeset()}
  defdelegate update_scene(scene, attrs), to: SceneCrud

  @doc """
  Soft-deletes a scene by setting deleted_at.
  Also soft-deletes all children recursively.
  """
  @spec delete_scene(scene_record()) :: {:ok, scene_record()} | {:error, term()}
  defdelegate delete_scene(scene), to: SceneCrud
  defdelegate delete_scene(actor_scope, scene), to: SceneCrud

  @doc """
  Soft deletes a scene and its descendants, returning the committed cascade
  ids (collected under the delete's own lock).
  """
  @spec delete_scene_subtree(scene_record()) ::
          {:ok, %{entity: scene_record(), deleted_ids: [integer()]}} | {:error, term()}
  defdelegate delete_scene_subtree(scene), to: SceneCrud
  defdelegate delete_scene_subtree(actor_scope, scene), to: SceneCrud

  @doc false
  defdelegate delete_scene_subtree_in_transaction(scene), to: SceneCrud
  defdelegate delete_scene_subtree_in_transaction(actor_scope, scene), to: SceneCrud

  @doc """
  Permanently deletes a scene from the database.
  Use with caution - this cannot be undone.
  """
  @spec hard_delete_scene(scene_record()) :: {:ok, scene_record()} | {:error, changeset()}
  defdelegate hard_delete_scene(scene), to: SceneCrud

  @doc """
  Restores a soft-deleted scene.
  """
  @spec restore_scene(scene_record()) :: {:ok, scene_record()} | {:error, changeset()}
  defdelegate restore_scene(scene), to: SceneCrud

  @doc """
  Lists all soft-deleted scenes for a project (trash).
  """
  @spec list_deleted_scenes(integer()) :: [scene_record()]
  defdelegate list_deleted_scenes(project_id), to: SceneCrud

  @doc """
  Lists scenes as a tree with limited zone/pin elements for the sidebar.
  """
  defdelegate list_scenes_tree_with_elements(project_id), to: SceneCrud

  @doc """
  Returns ancestors from root to direct parent, ordered top-down.
  """
  defdelegate list_ancestors(scene), to: SceneCrud

  @doc """
  Returns a changeset for tracking scene changes.
  """
  @spec change_scene(scene_record(), attrs()) :: changeset()
  defdelegate change_scene(scene, attrs \\ %{}), to: SceneCrud

  @doc "Soft-deletes a scene subtree by ids inside the caller's transaction (command palette)."
  defdelegate delete_scene_subtree_by_id_in_transaction(actor_scope, project_id, scene_id),
    to: SceneCrud

  @doc "Returns a Scene-owned project projection after authorization."
  defdelegate get_project(scope, project_id), to: ProjectAccess

  @doc "Returns a Scene-owned project projection by workspace and project slugs."
  defdelegate get_project_by_slugs(scope, workspace_slug, project_slug), to: ProjectAccess

  @doc "Lists active image assets available to the Scene editor."
  defdelegate list_image_asset_ids(project_id), to: AssetCatalog

  @doc "Gets an asset through the Scene-owned read projection."
  defdelegate get_asset(project_id, asset_id), to: AssetCatalog

  @doc "Consumes a Scene editor upload through the Scene-owned asset command."
  defdelegate upload_asset(path, entry, project, user, opts), to: AssetCommands

  @doc "Creates a sanitized SVG through the Scene-owned asset command."
  defdelegate create_sanitized_svg_asset(binary, attrs, project, user), to: AssetCommands

  @doc "Creates a binary asset through the Scene-owned asset command."
  defdelegate create_binary_asset(binary, attrs, project, user), to: AssetCommands

  @doc "Identifies a Scene pin without exposing the internal schema module to adapters."
  def scene_pin?(%ScenePin{}), do: true
  def scene_pin?(_term), do: false

  @doc "Identifies a Scene zone without exposing the internal schema module to adapters."
  def scene_zone?(%SceneZone{}), do: true
  def scene_zone?(_term), do: false

  @doc "Returns the Scene-owned health severity ordering."
  defdelegate health_severity_rank(severity), to: Severity, as: :rank

  @doc "Normalizes a route waypoint pause in Scene vocabulary."
  defdelegate waypoint_pause_ms(waypoint), to: RoutePoints

  # =============================================================================
  # Tree Operations
  # =============================================================================

  @doc """
  Moves a scene to a new parent at a specific position.
  """
  @spec move_scene_to_position(scene_record(), integer() | nil, integer()) ::
          {:ok, scene_record()} | {:error, term()}
  defdelegate move_scene_to_position(scene, new_parent_id, new_position), to: TreeOperations

  # =============================================================================
  # Layers
  # =============================================================================

  @doc """
  Lists all layers for a scene, ordered by position.
  """
  @spec list_layers(integer()) :: [layer()]
  defdelegate list_layers(scene_id), to: LayerCrud

  @doc """
  Gets a single layer by ID within a scene.
  Returns `nil` if not found.
  """
  @spec get_layer(integer(), integer()) :: layer() | nil
  defdelegate get_layer(scene_id, layer_id), to: LayerCrud

  @doc """
  Gets a single layer by ID within a scene.
  Raises `Ecto.NoResultsError` if not found.
  """
  @spec get_layer!(integer(), integer()) :: layer()
  defdelegate get_layer!(scene_id, layer_id), to: LayerCrud

  @doc """
  Creates a new layer in a scene with auto-assigned position.
  """
  @spec create_layer(integer(), attrs()) :: {:ok, layer()} | {:error, changeset()}
  defdelegate create_layer(scene_id, attrs), to: LayerCrud

  @doc """
  Updates a layer.
  """
  @spec update_layer(layer(), attrs()) :: {:ok, layer()} | {:error, changeset()}
  defdelegate update_layer(layer, attrs), to: LayerCrud

  @doc """
  Toggles the visibility of a layer.
  """
  @spec toggle_layer_visibility(layer()) :: {:ok, layer()} | {:error, changeset()}
  defdelegate toggle_layer_visibility(layer), to: LayerCrud

  @doc """
  Deletes a layer. Returns `{:error, :cannot_delete_last_layer}` if it's the only layer.
  Zones and pins on this layer have their layer_id nullified.
  """
  @spec delete_layer(layer()) ::
          {:ok, layer()} | {:error, :cannot_delete_last_layer | changeset()}
  defdelegate delete_layer(layer), to: LayerCrud

  @doc """
  Reorders layers by updating positions.
  """
  @spec reorder_layers(integer(), [integer()]) :: {:ok, [layer()]} | {:error, term()}
  defdelegate reorder_layers(scene_id, layer_ids), to: LayerCrud

  # =============================================================================
  # Zones
  # =============================================================================

  @doc """
  Lists zones for a scene, with optional `:layer_id` filter.
  """
  @spec list_zones(integer(), keyword()) :: [zone()]
  defdelegate list_zones(scene_id, opts \\ []), to: ZoneCrud

  @doc """
  Gets a zone by ID. Returns `nil` if not found.
  """
  @spec get_zone(integer()) :: zone() | nil
  defdelegate get_zone(zone_id), to: ZoneCrud

  @doc """
  Gets a zone by ID, scoped to a specific scene. Returns `nil` if not found.
  """
  @spec get_zone(integer(), integer()) :: zone() | nil
  defdelegate get_zone(scene_id, zone_id), to: ZoneCrud

  @doc """
  Gets a zone by ID. Raises if not found.
  """
  @spec get_zone!(integer()) :: zone()
  defdelegate get_zone!(zone_id), to: ZoneCrud

  @doc """
  Gets a zone by ID, scoped to a specific scene. Raises if not found.
  """
  @spec get_zone!(integer(), integer()) :: zone()
  defdelegate get_zone!(scene_id, zone_id), to: ZoneCrud

  @doc """
  Creates a zone in a scene with auto-assigned position.
  """
  @spec create_zone(integer(), attrs()) :: {:ok, zone()} | {:error, changeset()}
  defdelegate create_zone(scene_id, attrs), to: ZoneCrud

  @doc """
  Updates a zone.
  """
  @spec update_zone(zone(), attrs()) :: {:ok, zone()} | {:error, changeset()}
  defdelegate update_zone(zone, attrs), to: ZoneCrud

  @doc """
  Updates only the vertices of a zone (optimized for drag operations).
  """
  @spec update_zone_vertices(zone(), attrs()) :: {:ok, zone()} | {:error, changeset()}
  defdelegate update_zone_vertices(zone, attrs), to: ZoneCrud

  @doc """
  Deletes a zone (hard delete).
  """
  @spec delete_zone(zone()) :: {:ok, zone()} | {:error, changeset()}
  defdelegate delete_zone(zone), to: ZoneCrud

  @doc """
  Finds the zone on a parent scene that targets a child scene.
  """
  defdelegate get_zone_linking_to_scene(parent_scene_id, child_scene_id), to: ZoneCrud

  @doc """
  Lists zones with a non-navigate action_type, ordered by position.
  """
  @spec list_actionable_zones(integer()) :: [zone()]
  defdelegate list_actionable_zones(scene_id), to: ZoneCrud

  # =============================================================================
  # Zone Image Extraction
  # =============================================================================

  @doc """
  Extracts a zone's bounding-box region from the parent scene's background image,
  upscales to a minimum usable size, and returns the new Asset with dimensions.

  The `parent_scene` must have `:background_asset` preloaded.
  """
  defdelegate extract_zone_image(parent_scene, zone, project),
    to: ZoneImageExtractor,
    as: :extract

  @doc """
  Computes the bounding box of zone vertices as {min_x, min_y, max_x, max_y} in percentages.
  """
  defdelegate zone_bounding_box(vertices), to: ZoneImageExtractor, as: :bounding_box

  @doc """
  Normalizes zone vertices into child coordinate space (0-100% relative to bounding box).
  """
  defdelegate normalize_zone_vertices(vertices),
    to: ZoneImageExtractor,
    as: :normalize_vertices_to_bbox

  # =============================================================================
  # Pins
  # =============================================================================

  @doc """
  Lists pins for a scene, with optional `:layer_id` filter.
  """
  @spec list_pins(integer(), keyword()) :: [pin()]
  defdelegate list_pins(scene_id, opts \\ []), to: PinCrud

  @doc """
  Gets a pin by ID. Returns `nil` if not found.
  """
  @spec get_pin(integer()) :: pin() | nil
  defdelegate get_pin(pin_id), to: PinCrud

  @doc """
  Gets a pin by ID, scoped to a specific scene. Returns `nil` if not found.
  """
  @spec get_pin(integer(), integer()) :: pin() | nil
  defdelegate get_pin(scene_id, pin_id), to: PinCrud

  @doc """
  Gets a pin by ID. Raises if not found.
  """
  @spec get_pin!(integer()) :: pin()
  defdelegate get_pin!(pin_id), to: PinCrud

  @doc """
  Gets a pin by ID, scoped to a specific scene. Raises if not found.
  """
  @spec get_pin!(integer(), integer()) :: pin()
  defdelegate get_pin!(scene_id, pin_id), to: PinCrud

  @doc """
  Creates a pin in a scene with auto-assigned position.
  """
  @spec create_pin(integer(), attrs()) :: {:ok, pin()} | {:error, changeset()}
  defdelegate create_pin(scene_id, attrs), to: PinCrud

  @doc """
  Updates a pin.
  """
  @spec update_pin(pin(), attrs()) :: {:ok, pin()} | {:error, changeset()}
  defdelegate update_pin(pin, attrs), to: PinCrud

  @doc """
  Moves a pin to new coordinates (position_x/position_y only — drag optimization).
  """
  @spec move_pin(pin(), float(), float()) :: {:ok, pin()} | {:error, changeset()}
  defdelegate move_pin(pin, position_x, position_y), to: PinCrud

  @doc """
  Deletes a pin (hard delete). Connections to/from this pin are cascaded via FK.
  """
  @spec delete_pin(pin()) :: {:ok, pin()} | {:error, changeset()}
  defdelegate delete_pin(pin), to: PinCrud

  # =============================================================================
  # Connections
  # =============================================================================

  @doc """
  Lists all connections for a scene, with from_pin and to_pin preloaded.
  """
  @spec list_connections(integer()) :: [connection()]
  defdelegate list_connections(scene_id), to: ConnectionCrud

  @doc """
  Gets a connection by ID, scoped to a specific scene. Returns `nil` if not found.
  """
  @spec get_connection(integer(), integer()) :: connection() | nil
  defdelegate get_connection(scene_id, connection_id), to: ConnectionCrud

  @doc """
  Gets a connection by ID, scoped to a specific scene. Raises if not found.
  """
  @spec get_connection!(integer(), integer()) :: connection()
  defdelegate get_connection!(scene_id, connection_id), to: ConnectionCrud

  @doc """
  Creates a connection between two pins in a scene.
  Validates both pins belong to the same scene.
  """
  @spec create_connection(integer(), attrs()) ::
          {:ok, connection()} | {:error, changeset() | atom()}
  defdelegate create_connection(scene_id, attrs), to: ConnectionCrud

  @doc """
  Updates a connection.
  """
  @spec update_connection(connection(), attrs()) :: {:ok, connection()} | {:error, changeset()}
  defdelegate update_connection(connection, attrs), to: ConnectionCrud

  @spec update_connection_waypoints(connection(), attrs()) ::
          {:ok, connection()} | {:error, changeset()}
  defdelegate update_connection_waypoints(connection, attrs), to: ConnectionCrud

  @doc """
  Deletes a connection (hard delete).
  """
  @spec delete_connection(connection()) :: {:ok, connection()} | {:error, changeset()}
  defdelegate delete_connection(connection), to: ConnectionCrud

  # =============================================================================
  # Annotations
  # =============================================================================

  @spec list_annotations(integer()) :: [annotation()]
  defdelegate list_annotations(scene_id), to: AnnotationCrud

  @spec get_annotation(integer(), integer()) :: annotation() | nil
  defdelegate get_annotation(scene_id, annotation_id), to: AnnotationCrud

  @spec get_annotation!(integer(), integer()) :: annotation()
  defdelegate get_annotation!(scene_id, annotation_id), to: AnnotationCrud

  @spec create_annotation(integer(), attrs()) :: {:ok, annotation()} | {:error, changeset()}
  defdelegate create_annotation(scene_id, attrs), to: AnnotationCrud

  @spec update_annotation(annotation(), attrs()) :: {:ok, annotation()} | {:error, changeset()}
  defdelegate update_annotation(annotation, attrs), to: AnnotationCrud

  @spec move_annotation(annotation(), float(), float()) ::
          {:ok, annotation()} | {:error, changeset()}
  defdelegate move_annotation(annotation, position_x, position_y), to: AnnotationCrud

  @spec delete_annotation(annotation()) :: {:ok, annotation()} | {:error, changeset()}
  defdelegate delete_annotation(annotation), to: AnnotationCrud

  # =============================================================================
  # Ambient Flows
  # =============================================================================

  @doc "Lists ambient flows for a scene, ordered by position. Preloads `:flow`."
  @spec list_ambient_flows(integer()) :: [ambient_flow()]
  defdelegate list_ambient_flows(scene_id), to: AmbientFlowCrud

  @doc "Gets a single ambient flow scoped to a scene. Returns `nil` if not found."
  @spec get_ambient_flow(integer(), integer()) :: ambient_flow() | nil
  defdelegate get_ambient_flow(scene_id, id), to: AmbientFlowCrud

  @doc "Creates an ambient flow link. Validates flow belongs to same project."
  @spec create_ambient_flow(integer(), attrs()) :: {:ok, ambient_flow()} | {:error, term()}
  defdelegate create_ambient_flow(scene_id, attrs), to: AmbientFlowCrud

  @doc "Updates an ambient flow (enabled, trigger_type, position)."
  @spec update_ambient_flow(ambient_flow(), attrs()) ::
          {:ok, ambient_flow()} | {:error, changeset()}
  defdelegate update_ambient_flow(ambient_flow, attrs), to: AmbientFlowCrud

  @doc "Deletes an ambient flow link."
  @spec delete_ambient_flow(ambient_flow()) :: {:ok, ambient_flow()} | {:error, changeset()}
  defdelegate delete_ambient_flow(ambient_flow), to: AmbientFlowCrud

  @doc "Reorders ambient flows by updating positions from ordered ID list."
  @spec reorder_ambient_flows(integer(), [integer()]) ::
          {:ok, [ambient_flow()]} | {:error, term()}
  defdelegate reorder_ambient_flows(scene_id, ordered_ids), to: AmbientFlowCrud

  # =============================================================================
  # Scene-owned Flow and Sheet projections
  # =============================================================================

  @doc "Returns a bounded page of active assets for Scene pickers."
  defdelegate search_asset_options(project_id, kind, opts \\ []), to: AssetCatalog, as: :asset_options

  @doc "Builds an initial Scene asset picker page retaining every selected asset."
  defdelegate initial_asset_options(project_id, kind, selected_ids), to: AssetCatalog

  @doc "Lists the active Flow identities visible to Scenes."
  defdelegate list_flows(project_id), to: FlowCatalog

  @doc "Searches active Flow identities for Scene pickers."
  defdelegate search_flows(project_id, query, opts \\ []), to: FlowCatalog

  @doc "Gets an active Flow identity scoped to the Scene project."
  defdelegate get_flow(project_id, flow_id), to: FlowCatalog

  @doc "Gets a lightweight active Flow identity scoped to the Scene project."
  def get_flow_brief(project_id, flow_id), do: FlowCatalog.get_flow(project_id, flow_id)

  @doc "Loads the executable graph projection owned by Scene exploration."
  defdelegate get_runtime_flow(project_id, flow_id), to: FlowCatalog, as: :get_runtime_graph

  @doc "Loads the active node map for a Scene-owned Flow runtime graph."
  defdelegate runtime_nodes(project_id, flow_id), to: FlowCatalog

  @doc "Loads the connections for a Scene-owned Flow runtime graph."
  defdelegate runtime_connections(project_id, flow_id), to: FlowCatalog

  @doc "Lists active Sheets as a tree for Scene editor selectors."
  defdelegate list_sheets_tree(project_id), to: SheetCatalog

  @doc "Lists active Sheet speaker records for Scene exploration."
  defdelegate list_all_sheets(project_id), to: SheetCatalog

  @doc "Searches active Sheet identities for Scene pickers."
  defdelegate search_sheets(project_id, query, opts \\ []), to: SheetCatalog

  @doc "Gets an active Sheet identity scoped to the Scene project."
  defdelegate get_sheet(project_id, sheet_id), to: SheetCatalog

  @doc "Returns every variable addressable by Scene conditions and instructions."
  defdelegate list_referenceable_variables(project_id), to: VariableCatalog, as: :list_referenceable

  @doc "Builds the in-memory variable state used by Scene exploration."
  defdelegate build_runtime_variables(project_id), to: Variables, as: :build_variables

  # =============================================================================
  # Scene exploration Flow runtime
  # =============================================================================

  @doc "Initializes Scene-owned Flow execution state."
  defdelegate runtime_init(variables, entry_id), to: Engine, as: :init

  @doc "Advances execution until the next interactive node."
  defdelegate runtime_step_until_interactive(state, nodes, connections, opts \\ []),
    to: PlayerEngine,
    as: :step_until_interactive

  @doc "Selects a dialogue response in Scene exploration."
  defdelegate runtime_choose_response(state, response_id, connections),
    to: Engine,
    as: :choose_response

  @doc "Steps Scene exploration back to its previous execution snapshot."
  defdelegate runtime_step_back(state), to: Engine, as: :step_back

  @doc "Pushes a parent graph before entering a nested Flow."
  defdelegate runtime_push_flow_context(state, node_id, nodes, connections, flow_name),
    to: Engine,
    as: :push_flow_context

  @doc "Restores the parent graph after returning from a nested Flow."
  defdelegate runtime_pop_flow_context(state), to: Engine, as: :pop_flow_context

  @doc "Finds the parent connection associated with a returned Flow exit."
  defdelegate runtime_find_return_connection(connections, return_node_id, returned_exit_node_id),
    to: EngineHelpers,
    as: :find_return_connection

  @doc "Evaluates a condition against the Scene exploration variable state."
  defdelegate evaluate_runtime_condition(condition, variables), to: ConditionEval, as: :evaluate

  @doc "Executes variable assignments in the Scene exploration variable state."
  defdelegate execute_runtime_instructions(assignments, variables), to: InstructionExec, as: :execute

  @doc "Builds the browser-neutral slide projected by Scene exploration."
  defdelegate build_runtime_slide(node, state, speakers_map, project_id), to: Slide, as: :build

  @doc "Formats a runtime value for Scene presentation."
  defdelegate format_runtime_value(value), to: Storyarn.Scenes.FlowRuntime.Helpers, as: :format_value

  @doc "Returns the entry node ID from a Scene-owned runtime graph."
  def runtime_entry_node(nodes) when is_map(nodes) do
    Enum.find_value(nodes, fn {id, node} -> if node.type == "entry", do: id end)
  end

  # =============================================================================
  # Preload Helpers (wrap Repo.preload to keep web layer clean)
  # =============================================================================

  @doc "Preloads pin associations (icon_asset, sheet with avatars)."
  def preload_pin_associations(pin) do
    Repo.preload(pin, [:icon_asset, sheet: [avatars: :asset]], force: true)
  end

  @doc "Preloads scene background_asset association."
  def preload_scene_background(scene) do
    Repo.preload(scene, :background_asset, force: true)
  end

  @doc "Preloads sheet avatars association."
  def preload_sheet_avatar(sheet) do
    Repo.preload(sheet, avatars: :asset)
  end

  # =============================================================================
  # Dashboard Stats
  # =============================================================================

  @doc "Returns per-scene zone, pin, and connection counts. %{scene_id => %{zone_count, pin_count, connection_count}}."
  defdelegate scene_stats_for_project(project_id), to: SceneStats

  @doc "Returns the count of scenes that have a background image."
  defdelegate scenes_with_background_count(project_id), to: SceneStats

  @doc "Returns the canonical project-wide scene health findings, one checker run per scene."
  defdelegate list_dashboard_health_findings(project_id), to: SceneStats

  @doc "Normalizes the project-wide reference sets a scene health check needs."
  defdelegate scene_health_references(attrs), to: HealthSnapshots, as: :references

  @doc "Returns the canonical health findings for one scene and its elements."
  defdelegate scene_health_findings(scene, collections, references), to: HealthSnapshots, as: :findings

  # =============================================================================
  # Exploration Sessions
  # =============================================================================

  @doc "Gets an existing exploration session for a user and project."
  defdelegate get_exploration_session(user_id, project_id),
    to: ExplorationSessionCrud,
    as: :get_session

  @doc "Upserts an exploration session (create or update, includes positions)."
  defdelegate save_exploration_session(user_id, project_id, attrs),
    to: ExplorationSessionCrud,
    as: :save_session

  @doc "Deletes an exploration session (new game)."
  defdelegate delete_exploration_session(user_id, project_id),
    to: ExplorationSessionCrud,
    as: :delete_session

  @doc "Deletes exploration sessions older than N days."
  defdelegate cleanup_old_exploration_sessions(days \\ 30),
    to: ExplorationSessionCrud,
    as: :cleanup_old_sessions

  @doc "Recomputes Scene exploration formula variables."
  defdelegate recompute_runtime_formulas(variables),
    to: FormulaRuntime,
    as: :recompute_formulas

  @doc "Emits the typed Scene fact that an exploration session started."
  defdelegate record_exploration_started(scope, scene, has_saved_session),
    to: Events,
    as: :exploration_started

  @doc "Emits the typed Scene fact that the version panel was opened."
  defdelegate record_version_panel_opened(scope, scene),
    to: TrackedCommands

  @doc "Emits the typed Scene fact that a version comparison was opened."
  defdelegate record_version_compared(scope, scene), to: TrackedCommands

  @doc "Creates a named Scene version and emits its Scene-owned fact."
  defdelegate create_named_version(scope, scene, opts), to: TrackedCommands

  @doc "Restores a Scene version and emits its Scene-owned fact on success."
  defdelegate restore_tracked_version(scope, scene, version, opts),
    to: TrackedCommands,
    as: :restore_version

  # =============================================================================
  # Versioning
  # =============================================================================

  @doc "Returns whether in-place Scene version restore is enabled."
  def restore_enabled?, do: Versioning.restore_enabled?()

  @doc """
  Creates a new version snapshot of the given scene.
  """
  def create_version(%Scene{} = scene, user_id, opts \\ []) do
    Versioning.create_version(scene, user_id, opts)
  end

  @doc """
  Lists all versions for a scene.
  """
  def list_versions(scene_id, opts \\ []) do
    Versioning.list_versions(scene_id, opts)
  end

  @doc """
  Gets a specific version by scene_id and version_number.
  """
  def get_version(scene_id, version_number) do
    Versioning.get_version(scene_id, version_number)
  end

  @doc """
  Gets the latest version for a scene.
  """
  def get_latest_version(scene_id) do
    Versioning.get_latest_version(scene_id)
  end

  @doc """
  Returns the total number of versions for a scene.
  """
  def count_versions(scene_id) do
    Versioning.count_versions(scene_id)
  end

  @doc """
  Creates a version if enough time has passed since the last version.
  """
  def maybe_create_version(%Scene{} = scene, user_id, opts \\ []) do
    Versioning.maybe_create_version(scene, user_id, opts)
  end

  @doc """
  Deletes a version and its snapshot.
  """
  def delete_version(version) do
    Versioning.delete_version(version)
  end

  @doc "Updates the name and description of a Scene version."
  def update_version(version, attrs), do: Versioning.update_version(version, attrs)

  @doc false
  def load_version_snapshot(version), do: Versioning.load_version_snapshot(version)

  @doc "Decides whether restore must first warn about unsaved changes."
  def prepare_version_restore(%Scene{} = scene, version), do: Versioning.prepare_restore(scene, version)

  @doc "Loads a target Scene version and builds its restore conflict report."
  def prepare_version_restore_conflicts(%Scene{} = scene, version),
    do: Versioning.prepare_restore_conflicts(scene, version)

  @doc """
  Restores a scene to a specific version.
  """
  def restore_version(%Scene{} = scene, version, opts \\ []) do
    Versioning.restore_version(scene, version, opts)
  end

  @doc "Ensures that Scene version restore is currently enabled."
  def ensure_version_restore_enabled, do: Versioning.ensure_restore_enabled()

  @doc "Builds the Scene-owned restore-conflict preview."
  def detect_version_restore_conflicts(snapshot, %Scene{} = scene),
    do: Versioning.detect_restore_conflicts(snapshot, scene)

  @doc "Returns the previous and next stored Scene version numbers."
  def get_adjacent_version_numbers(scene_id, current_number),
    do: Versioning.get_adjacent_version_numbers(scene_id, current_number)

  @doc "Returns whether this project can create another named Scene version."
  defdelegate can_create_named_version?(project_id, workspace_id), to: Limits

  @doc """
  Sets the current version for a scene.
  """
  def set_current_version(%Scene{} = scene, version_or_nil) do
    version_id = if version_or_nil, do: version_or_nil.id

    scene
    |> Scene.version_changeset(%{current_version_id: version_id})
    |> Repo.update()
  end
end

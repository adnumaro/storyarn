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

  import Ecto.Query, warn: false

  alias Storyarn.Scenes.{
    AnnotationCrud,
    ConnectionCrud,
    LayerCrud,
    PinCrud,
    Scene,
    SceneAnnotation,
    SceneConnection,
    SceneCrud,
    SceneLayer,
    ScenePin,
    SceneZone,
    TreeOperations,
    ZoneCrud,
    ZoneImageExtractor
  }

  alias Storyarn.Projects.Project
  alias Storyarn.Repo

  # =============================================================================
  # Type Definitions
  # =============================================================================

  @type scene_record :: Scene.t()
  @type layer :: SceneLayer.t()
  @type zone :: SceneZone.t()
  @type pin :: ScenePin.t()
  @type connection :: SceneConnection.t()
  @type annotation :: SceneAnnotation.t()
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
  @spec search_scenes(integer(), String.t()) :: [scene_record()]
  defdelegate search_scenes(project_id, query), to: SceneCrud

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
  Gets a scene by ID without project scoping (no preloads).
  Used for canvas data enrichment where the scene reference is already project-scoped.
  """
  @spec get_scene_by_id(integer()) :: scene_record() | nil
  defdelegate get_scene_by_id(scene_id), to: SceneCrud

  @doc """
  Gets a scene with only basic fields (no preloads).
  Used for breadcrumbs and lightweight lookups.
  """
  @spec get_scene_brief(integer(), integer()) :: scene_record() | nil
  defdelegate get_scene_brief(project_id, scene_id), to: SceneCrud

  @doc """
  Gets a scene with only background_asset preloaded.
  Used for rendering scene backdrops in the flow player.
  """
  @spec get_scene_backdrop(integer()) :: scene_record() | nil
  defdelegate get_scene_backdrop(scene_id), to: SceneCrud

  @doc """
  Returns the project_id for a given scene_id.
  Used by reference trackers that need the project scope from a scene.
  """
  @spec get_scene_project_id(integer()) :: integer() | nil
  defdelegate get_scene_project_id(scene_id), to: SceneCrud

  @doc """
  Gets a scene including soft-deleted ones (for trash/restore).
  Returns `nil` if not found.
  """
  @spec get_scene_including_deleted(integer(), integer()) :: scene_record() | nil
  defdelegate get_scene_including_deleted(project_id, scene_id), to: SceneCrud

  @doc """
  Creates a new scene in a project.
  Auto-creates a default layer and generates a shortcut from the name.
  """
  @spec create_scene(Project.t(), attrs()) :: {:ok, scene_record()} | {:error, changeset()}
  defdelegate create_scene(project, attrs), to: SceneCrud

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

  # =============================================================================
  # Tree Operations
  # =============================================================================

  @doc """
  Reorders scenes within a parent container.
  Takes a project_id, parent_id (nil for root level), and a list of scene IDs
  in the desired order.
  """
  @spec reorder_scenes(integer(), integer() | nil, [integer()]) ::
          {:ok, [scene_record()]} | {:error, term()}
  defdelegate reorder_scenes(project_id, parent_id, scene_ids), to: TreeOperations

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

  @doc """
  Returns a changeset for tracking layer changes.
  """
  @spec change_layer(layer(), attrs()) :: changeset()
  defdelegate change_layer(layer, attrs \\ %{}), to: LayerCrud

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
  Returns a changeset for tracking zone changes.
  """
  @spec change_zone(zone(), attrs()) :: changeset()
  defdelegate change_zone(zone, attrs \\ %{}), to: ZoneCrud

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

  @doc """
  Returns a changeset for tracking pin changes.
  """
  @spec change_pin(pin(), attrs()) :: changeset()
  defdelegate change_pin(pin, attrs \\ %{}), to: PinCrud

  # =============================================================================
  # Connections
  # =============================================================================

  @doc """
  Lists all connections for a scene, with from_pin and to_pin preloaded.
  """
  @spec list_connections(integer()) :: [connection()]
  defdelegate list_connections(scene_id), to: ConnectionCrud

  @doc """
  Gets a connection by ID with pins preloaded. Returns `nil` if not found.
  """
  @spec get_connection(integer()) :: connection() | nil
  defdelegate get_connection(connection_id), to: ConnectionCrud

  @doc """
  Gets a connection by ID, scoped to a specific scene. Returns `nil` if not found.
  """
  @spec get_connection(integer(), integer()) :: connection() | nil
  defdelegate get_connection(scene_id, connection_id), to: ConnectionCrud

  @doc """
  Gets a connection by ID with pins preloaded. Raises if not found.
  """
  @spec get_connection!(integer()) :: connection()
  defdelegate get_connection!(connection_id), to: ConnectionCrud

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

  @doc """
  Returns a changeset for tracking connection changes.
  """
  @spec change_connection(connection(), attrs()) :: changeset()
  defdelegate change_connection(connection, attrs \\ %{}), to: ConnectionCrud

  # =============================================================================
  # Annotations
  # =============================================================================

  @spec list_annotations(integer()) :: [annotation()]
  defdelegate list_annotations(scene_id), to: AnnotationCrud

  @spec get_annotation(integer()) :: annotation() | nil
  defdelegate get_annotation(annotation_id), to: AnnotationCrud

  @spec get_annotation(integer(), integer()) :: annotation() | nil
  defdelegate get_annotation(scene_id, annotation_id), to: AnnotationCrud

  @spec get_annotation!(integer()) :: annotation()
  defdelegate get_annotation!(annotation_id), to: AnnotationCrud

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
  # Target Queries (backlinks)
  # =============================================================================

  @doc """
  Finds all scene elements (zones and pins) that link to a given target.
  Used for backlinks (e.g., "Appears on these scenes" in sheet references).

  Returns `%{zones: [...], pins: [...]}` with parent scene preloaded.
  """
  @spec get_elements_for_target(String.t(), integer()) :: %{zones: [zone()], pins: [pin()]}
  def get_elements_for_target(target_type, target_id) do
    zones =
      from(z in SceneZone,
        where: z.target_type == ^target_type and z.target_id == ^target_id,
        preload: [:scene]
      )
      |> Repo.all()

    pins =
      from(p in ScenePin,
        where: p.target_type == ^target_type and p.target_id == ^target_id,
        preload: [:scene]
      )
      |> Repo.all()

    %{zones: zones, pins: pins}
  end

  # =============================================================================
  # Preload Helpers (wrap Repo.preload to keep web layer clean)
  # =============================================================================

  @doc "Preloads pin associations (icon_asset, sheet with avatar_asset)."
  def preload_pin_associations(pin) do
    Repo.preload(pin, [:icon_asset, sheet: :avatar_asset], force: true)
  end

  @doc "Preloads scene background_asset association."
  def preload_scene_background(scene) do
    Repo.preload(scene, :background_asset, force: true)
  end

  @doc "Preloads sheet avatar_asset association."
  def preload_sheet_avatar(sheet) do
    Repo.preload(sheet, avatar_asset: [])
  end

  # =============================================================================
  # Export / Import helpers
  # =============================================================================

  @doc "Lists scenes with all associations preloaded. Opts: [filter_ids: :all | [ids]]."
  defdelegate list_scenes_for_export(project_id, opts \\ []), to: SceneCrud

  @doc "Counts non-deleted scenes for a project."
  defdelegate count_scenes(project_id), to: SceneCrud

  @doc "Returns variable usage for a block from scene zones."
  defdelegate get_scene_zone_variable_usage(block_id, project_id), to: SceneCrud

  @doc "Returns variable usage for a block from scene pins."
  defdelegate get_scene_pin_variable_usage(block_id, project_id), to: SceneCrud

  @doc "Returns stale variable reference data for scene zones."
  defdelegate check_stale_scene_zone_variable_references(block_id, project_id), to: SceneCrud

  @doc "Returns stale variable reference data for scene pins."
  defdelegate check_stale_scene_pin_variable_references(block_id, project_id), to: SceneCrud

  @doc "Resolves scene pin backlinks for entity reference tracking."
  defdelegate query_scene_pin_backlinks(target_type, target_id, project_id), to: SceneCrud

  @doc "Resolves scene zone backlinks for entity reference tracking."
  defdelegate query_scene_zone_backlinks(target_type, target_id, project_id), to: SceneCrud

  @doc "Lists sheet IDs referenced by scene pins in a project."
  defdelegate list_pin_referenced_sheet_ids(project_id), to: SceneCrud

  @doc "Lists active scene IDs for a project."
  defdelegate list_active_scene_ids(project_id), to: SceneCrud

  @doc "Lists existing scene shortcuts for a project."
  defdelegate list_scene_shortcuts(project_id), to: SceneCrud, as: :list_shortcuts

  @doc "Detects shortcut conflicts between imported scenes and existing ones."
  defdelegate detect_scene_shortcut_conflicts(project_id, shortcuts),
    to: SceneCrud,
    as: :detect_shortcut_conflicts

  @doc "Soft-deletes existing scenes with the given shortcut (overwrite import strategy)."
  defdelegate soft_delete_scene_by_shortcut(project_id, shortcut),
    to: SceneCrud,
    as: :soft_delete_by_shortcut

  @doc "Bulk-inserts scene connections from a list of attr maps."
  defdelegate bulk_import_scene_connections(attrs_list),
    to: SceneCrud,
    as: :bulk_import_connections

  @doc "Bulk-inserts scene annotations from a list of attr maps."
  defdelegate bulk_import_scene_annotations(attrs_list),
    to: SceneCrud,
    as: :bulk_import_annotations

  @doc "Creates a scene for import (raw insert, no side effects)."
  defdelegate import_scene(project_id, attrs), to: SceneCrud

  @doc "Creates a scene layer for import (raw insert, no side effects)."
  defdelegate import_layer(scene_id, attrs), to: SceneCrud

  @doc "Creates a scene pin for import (raw insert, no side effects)."
  defdelegate import_pin(scene_id, attrs), to: SceneCrud

  @doc "Creates a scene zone for import (raw insert, no side effects)."
  defdelegate import_zone(scene_id, attrs), to: SceneCrud

  @doc "Updates a scene's parent_id after import."
  defdelegate link_scene_import_parent(scene, parent_id), to: SceneCrud, as: :link_import_parent
end

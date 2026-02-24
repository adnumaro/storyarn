defmodule Storyarn.Maps do
  @moduledoc """
  The Maps context.

  Manages maps (visual world-building canvases), layers, zones, pins,
  and connections within a project. Maps provide a spatial interface
  to navigate and understand the narrative world.

  This module serves as a facade, delegating to specialized submodules:
  - `MapCrud` - CRUD operations for maps
  - `LayerCrud` - CRUD operations for layers
  - `ZoneCrud` - CRUD operations for zones
  - `PinCrud` - CRUD operations for pins
  - `ConnectionCrud` - CRUD operations for connections
  - `TreeOperations` - Reorder and move operations
  """

  import Ecto.Query, warn: false

  alias Storyarn.Maps.{
    AnnotationCrud,
    ConnectionCrud,
    LayerCrud,
    Map,
    MapAnnotation,
    MapConnection,
    MapCrud,
    MapLayer,
    MapPin,
    MapZone,
    PinCrud,
    TreeOperations,
    ZoneCrud
  }

  alias Storyarn.Projects.Project
  alias Storyarn.Repo

  # =============================================================================
  # Type Definitions
  # =============================================================================

  @type map_record :: Map.t()
  @type layer :: MapLayer.t()
  @type zone :: MapZone.t()
  @type pin :: MapPin.t()
  @type connection :: MapConnection.t()
  @type annotation :: MapAnnotation.t()
  @type changeset :: Ecto.Changeset.t()
  @type attrs :: map()

  # =============================================================================
  # Maps - CRUD Operations
  # =============================================================================

  @doc """
  Lists all non-deleted maps for a project.
  Returns maps ordered by position then name.
  """
  @spec list_maps(integer()) :: [map_record()]
  defdelegate list_maps(project_id), to: MapCrud

  @doc """
  Lists maps as a tree structure.
  Returns root-level maps with their children preloaded recursively.
  """
  @spec list_maps_tree(integer()) :: [map_record()]
  defdelegate list_maps_tree(project_id), to: MapCrud

  @doc """
  Searches maps by name or shortcut for reference selection.
  Returns maps matching the query, limited to 10 results.
  """
  @spec search_maps(integer(), String.t()) :: [map_record()]
  defdelegate search_maps(project_id, query), to: MapCrud

  @doc """
  Gets a single map by ID within a project, with all associations preloaded.
  Returns `nil` if the map doesn't exist or doesn't belong to the project.
  """
  @spec get_map(integer(), integer()) :: map_record() | nil
  defdelegate get_map(project_id, map_id), to: MapCrud

  @doc """
  Gets a single map by ID within a project, with all associations preloaded.
  Raises `Ecto.NoResultsError` if not found.
  """
  @spec get_map!(integer(), integer()) :: map_record()
  defdelegate get_map!(project_id, map_id), to: MapCrud

  @doc """
  Gets a map by ID without project scoping (no preloads).
  Used for canvas data enrichment where the map reference is already project-scoped.
  """
  @spec get_map_by_id(integer()) :: map_record() | nil
  defdelegate get_map_by_id(map_id), to: MapCrud

  @doc """
  Gets a map with only basic fields (no preloads).
  Used for breadcrumbs and lightweight lookups.
  """
  @spec get_map_brief(integer(), integer()) :: map_record() | nil
  defdelegate get_map_brief(project_id, map_id), to: MapCrud

  @doc """
  Gets a map with only background_asset preloaded.
  Used for rendering scene backdrops in the flow player.
  """
  @spec get_map_backdrop(integer()) :: map_record() | nil
  defdelegate get_map_backdrop(map_id), to: MapCrud

  @doc """
  Returns the project_id for a given map_id.
  Used by reference trackers that need the project scope from a map.
  """
  @spec get_map_project_id(integer()) :: integer() | nil
  defdelegate get_map_project_id(map_id), to: MapCrud

  @doc """
  Gets a map including soft-deleted ones (for trash/restore).
  Returns `nil` if not found.
  """
  @spec get_map_including_deleted(integer(), integer()) :: map_record() | nil
  defdelegate get_map_including_deleted(project_id, map_id), to: MapCrud

  @doc """
  Creates a new map in a project.
  Auto-creates a default layer and generates a shortcut from the name.
  """
  @spec create_map(Project.t(), attrs()) :: {:ok, map_record()} | {:error, changeset()}
  defdelegate create_map(project, attrs), to: MapCrud

  @doc """
  Updates a map.
  Auto-regenerates shortcut on name change.
  """
  @spec update_map(map_record(), attrs()) :: {:ok, map_record()} | {:error, changeset()}
  defdelegate update_map(map, attrs), to: MapCrud

  @doc """
  Soft-deletes a map by setting deleted_at.
  Also soft-deletes all children recursively.
  """
  @spec delete_map(map_record()) :: {:ok, map_record()} | {:error, term()}
  defdelegate delete_map(map), to: MapCrud

  @doc """
  Permanently deletes a map from the database.
  Use with caution - this cannot be undone.
  """
  @spec hard_delete_map(map_record()) :: {:ok, map_record()} | {:error, changeset()}
  defdelegate hard_delete_map(map), to: MapCrud

  @doc """
  Restores a soft-deleted map.
  """
  @spec restore_map(map_record()) :: {:ok, map_record()} | {:error, changeset()}
  defdelegate restore_map(map), to: MapCrud

  @doc """
  Lists all soft-deleted maps for a project (trash).
  """
  @spec list_deleted_maps(integer()) :: [map_record()]
  defdelegate list_deleted_maps(project_id), to: MapCrud

  @doc """
  Lists maps as a tree with limited zone/pin elements for the sidebar.
  """
  defdelegate list_maps_tree_with_elements(project_id), to: MapCrud

  @doc """
  Returns ancestors from root to direct parent, ordered top-down.
  """
  defdelegate list_ancestors(map), to: MapCrud

  @doc """
  Returns a changeset for tracking map changes.
  """
  @spec change_map(map_record(), attrs()) :: changeset()
  defdelegate change_map(map, attrs \\ %{}), to: MapCrud

  # =============================================================================
  # Tree Operations
  # =============================================================================

  @doc """
  Reorders maps within a parent container.
  Takes a project_id, parent_id (nil for root level), and a list of map IDs
  in the desired order.
  """
  @spec reorder_maps(integer(), integer() | nil, [integer()]) ::
          {:ok, [map_record()]} | {:error, term()}
  defdelegate reorder_maps(project_id, parent_id, map_ids), to: TreeOperations

  @doc """
  Moves a map to a new parent at a specific position.
  """
  @spec move_map_to_position(map_record(), integer() | nil, integer()) ::
          {:ok, map_record()} | {:error, term()}
  defdelegate move_map_to_position(map, new_parent_id, new_position), to: TreeOperations

  # =============================================================================
  # Layers
  # =============================================================================

  @doc """
  Lists all layers for a map, ordered by position.
  """
  @spec list_layers(integer()) :: [layer()]
  defdelegate list_layers(map_id), to: LayerCrud

  @doc """
  Gets a single layer by ID within a map.
  Returns `nil` if not found.
  """
  @spec get_layer(integer(), integer()) :: layer() | nil
  defdelegate get_layer(map_id, layer_id), to: LayerCrud

  @doc """
  Gets a single layer by ID within a map.
  Raises `Ecto.NoResultsError` if not found.
  """
  @spec get_layer!(integer(), integer()) :: layer()
  defdelegate get_layer!(map_id, layer_id), to: LayerCrud

  @doc """
  Creates a new layer in a map with auto-assigned position.
  """
  @spec create_layer(integer(), attrs()) :: {:ok, layer()} | {:error, changeset()}
  defdelegate create_layer(map_id, attrs), to: LayerCrud

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
  defdelegate reorder_layers(map_id, layer_ids), to: LayerCrud

  @doc """
  Returns a changeset for tracking layer changes.
  """
  @spec change_layer(layer(), attrs()) :: changeset()
  defdelegate change_layer(layer, attrs \\ %{}), to: LayerCrud

  # =============================================================================
  # Zones
  # =============================================================================

  @doc """
  Lists zones for a map, with optional `:layer_id` filter.
  """
  @spec list_zones(integer(), keyword()) :: [zone()]
  defdelegate list_zones(map_id, opts \\ []), to: ZoneCrud

  @doc """
  Gets a zone by ID. Returns `nil` if not found.
  """
  @spec get_zone(integer()) :: zone() | nil
  defdelegate get_zone(zone_id), to: ZoneCrud

  @doc """
  Gets a zone by ID, scoped to a specific map. Returns `nil` if not found.
  """
  @spec get_zone(integer(), integer()) :: zone() | nil
  defdelegate get_zone(map_id, zone_id), to: ZoneCrud

  @doc """
  Gets a zone by ID. Raises if not found.
  """
  @spec get_zone!(integer()) :: zone()
  defdelegate get_zone!(zone_id), to: ZoneCrud

  @doc """
  Gets a zone by ID, scoped to a specific map. Raises if not found.
  """
  @spec get_zone!(integer(), integer()) :: zone()
  defdelegate get_zone!(map_id, zone_id), to: ZoneCrud

  @doc """
  Creates a zone in a map with auto-assigned position.
  """
  @spec create_zone(integer(), attrs()) :: {:ok, zone()} | {:error, changeset()}
  defdelegate create_zone(map_id, attrs), to: ZoneCrud

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
  Finds the zone on a parent map that targets a child map.
  """
  defdelegate get_zone_linking_to_map(parent_map_id, child_map_id), to: ZoneCrud

  @doc """
  Lists zones with a non-navigate action_type, ordered by position.
  """
  @spec list_actionable_zones(integer()) :: [zone()]
  defdelegate list_actionable_zones(map_id), to: ZoneCrud

  # =============================================================================
  # Pins
  # =============================================================================

  @doc """
  Lists pins for a map, with optional `:layer_id` filter.
  """
  @spec list_pins(integer(), keyword()) :: [pin()]
  defdelegate list_pins(map_id, opts \\ []), to: PinCrud

  @doc """
  Gets a pin by ID. Returns `nil` if not found.
  """
  @spec get_pin(integer()) :: pin() | nil
  defdelegate get_pin(pin_id), to: PinCrud

  @doc """
  Gets a pin by ID, scoped to a specific map. Returns `nil` if not found.
  """
  @spec get_pin(integer(), integer()) :: pin() | nil
  defdelegate get_pin(map_id, pin_id), to: PinCrud

  @doc """
  Gets a pin by ID. Raises if not found.
  """
  @spec get_pin!(integer()) :: pin()
  defdelegate get_pin!(pin_id), to: PinCrud

  @doc """
  Gets a pin by ID, scoped to a specific map. Raises if not found.
  """
  @spec get_pin!(integer(), integer()) :: pin()
  defdelegate get_pin!(map_id, pin_id), to: PinCrud

  @doc """
  Creates a pin in a map with auto-assigned position.
  """
  @spec create_pin(integer(), attrs()) :: {:ok, pin()} | {:error, changeset()}
  defdelegate create_pin(map_id, attrs), to: PinCrud

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
  Lists all connections for a map, with from_pin and to_pin preloaded.
  """
  @spec list_connections(integer()) :: [connection()]
  defdelegate list_connections(map_id), to: ConnectionCrud

  @doc """
  Gets a connection by ID with pins preloaded. Returns `nil` if not found.
  """
  @spec get_connection(integer()) :: connection() | nil
  defdelegate get_connection(connection_id), to: ConnectionCrud

  @doc """
  Gets a connection by ID, scoped to a specific map. Returns `nil` if not found.
  """
  @spec get_connection(integer(), integer()) :: connection() | nil
  defdelegate get_connection(map_id, connection_id), to: ConnectionCrud

  @doc """
  Gets a connection by ID with pins preloaded. Raises if not found.
  """
  @spec get_connection!(integer()) :: connection()
  defdelegate get_connection!(connection_id), to: ConnectionCrud

  @doc """
  Gets a connection by ID, scoped to a specific map. Raises if not found.
  """
  @spec get_connection!(integer(), integer()) :: connection()
  defdelegate get_connection!(map_id, connection_id), to: ConnectionCrud

  @doc """
  Creates a connection between two pins in a map.
  Validates both pins belong to the same map.
  """
  @spec create_connection(integer(), attrs()) ::
          {:ok, connection()} | {:error, changeset() | atom()}
  defdelegate create_connection(map_id, attrs), to: ConnectionCrud

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
  defdelegate list_annotations(map_id), to: AnnotationCrud

  @spec get_annotation(integer()) :: annotation() | nil
  defdelegate get_annotation(annotation_id), to: AnnotationCrud

  @spec get_annotation(integer(), integer()) :: annotation() | nil
  defdelegate get_annotation(map_id, annotation_id), to: AnnotationCrud

  @spec get_annotation!(integer()) :: annotation()
  defdelegate get_annotation!(annotation_id), to: AnnotationCrud

  @spec get_annotation!(integer(), integer()) :: annotation()
  defdelegate get_annotation!(map_id, annotation_id), to: AnnotationCrud

  @spec create_annotation(integer(), attrs()) :: {:ok, annotation()} | {:error, changeset()}
  defdelegate create_annotation(map_id, attrs), to: AnnotationCrud

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
  Finds all map elements (zones and pins) that link to a given target.
  Used for backlinks (e.g., "Appears on these maps" in sheet references).

  Returns `%{zones: [...], pins: [...]}` with parent map preloaded.
  """
  @spec get_elements_for_target(String.t(), integer()) :: %{zones: [zone()], pins: [pin()]}
  def get_elements_for_target(target_type, target_id) do
    zones =
      from(z in MapZone,
        where: z.target_type == ^target_type and z.target_id == ^target_id,
        preload: [:map]
      )
      |> Repo.all()

    pins =
      from(p in MapPin,
        where: p.target_type == ^target_type and p.target_id == ^target_id,
        preload: [:map]
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

  @doc "Preloads map background_asset association."
  def preload_map_background(map) do
    Repo.preload(map, :background_asset, force: true)
  end

  @doc "Preloads sheet avatar_asset association."
  def preload_sheet_avatar(sheet) do
    Repo.preload(sheet, avatar_asset: [])
  end
end

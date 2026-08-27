defmodule Storyarn.Scenes do
  @moduledoc """
  The Scenes context.

  Manages scenes (visual world-building canvases), layers, zones, pins,
  and connections within a project. Scenes provide a spatial interface
  to navigate and understand the narrative world.

  The public facade composes the bounded context's capability boundaries. Web
  code depends only on this module; capabilities do not expose their private
  commands, queries, data projections, execution modules, or adapters.
  """

  alias Storyarn.Scenes.Access
  alias Storyarn.Scenes.Assets
  alias Storyarn.Scenes.Editor
  alias Storyarn.Scenes.Exploration
  alias Storyarn.Scenes.Expressions
  alias Storyarn.Scenes.Health
  alias Storyarn.Scenes.Scene
  alias Storyarn.Scenes.SceneAmbientFlow
  alias Storyarn.Scenes.SceneAnnotation
  alias Storyarn.Scenes.SceneConnection
  alias Storyarn.Scenes.SceneLayer
  alias Storyarn.Scenes.ScenePin
  alias Storyarn.Scenes.SceneZone
  alias Storyarn.Scenes.Versioning

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
  defdelegate list_scenes(project_id), to: Editor

  @doc """
  Lists scenes as a tree structure.
  Returns root-level scenes with their children preloaded recursively.
  """
  @spec list_scenes_tree(integer()) :: [scene_record()]
  defdelegate list_scenes_tree(project_id), to: Editor

  @doc """
  Searches scenes by name or shortcut for reference selection.
  Returns scenes matching the query, limited to 10 results.
  """
  @spec search_scenes(integer(), String.t(), keyword()) :: [scene_record()]
  defdelegate search_scenes(project_id, query, opts \\ []), to: Editor

  @doc "Searches scene metadata and authored layer, pin, zone, and annotation text."
  @spec search_scenes_deep(integer(), String.t(), keyword()) :: [scene_record()]
  defdelegate search_scenes_deep(project_id, query, opts \\ []), to: Editor

  @doc """
  Gets a single scene by ID within a project, with all associations preloaded.
  Returns `nil` if the scene doesn't exist or doesn't belong to the project.
  """
  @spec get_scene(integer(), integer()) :: scene_record() | nil
  defdelegate get_scene(project_id, scene_id), to: Editor

  @doc """
  Gets a single scene by ID within a project, with all associations preloaded.
  Raises `Ecto.NoResultsError` if not found.
  """
  @spec get_scene!(integer(), integer()) :: scene_record()
  defdelegate get_scene!(project_id, scene_id), to: Editor

  @doc """
  Gets a scene with only basic fields (no preloads).
  Used for breadcrumbs and lightweight lookups.
  """
  @spec get_scene_brief(integer(), integer()) :: scene_record() | nil
  defdelegate get_scene_brief(project_id, scene_id), to: Editor

  @doc """
  Gets a scene by project_id and scene_id, including soft-deleted records.
  """
  @spec get_scene_including_deleted(integer(), integer()) :: scene_record() | nil
  defdelegate get_scene_including_deleted(project_id, scene_id), to: Editor

  @doc """
  Creates a new scene in a project.
  Auto-creates a default layer and generates a shortcut from the name.
  """
  @spec create_scene(map() | integer(), attrs()) :: {:ok, scene_record()} | {:error, changeset()}
  defdelegate create_scene(project, attrs), to: Editor
  defdelegate create_scene(actor_scope, project, attrs), to: Editor

  @doc false
  defdelegate create_scene_in_transaction(project, attrs), to: Editor
  defdelegate create_scene_in_transaction(actor_scope, project, attrs), to: Editor

  @doc """
  Updates a scene.
  Auto-regenerates shortcut on name change.
  """
  @spec update_scene(scene_record(), attrs()) :: {:ok, scene_record()} | {:error, changeset()}
  defdelegate update_scene(scene, attrs), to: Editor

  @doc """
  Soft-deletes a scene by setting deleted_at.
  Also soft-deletes all children recursively.
  """
  @spec delete_scene(scene_record()) :: {:ok, scene_record()} | {:error, term()}
  defdelegate delete_scene(scene), to: Editor
  defdelegate delete_scene(actor_scope, scene), to: Editor

  @doc """
  Soft deletes a scene and its descendants, returning the committed cascade
  ids (collected under the delete's own lock).
  """
  @spec delete_scene_subtree(scene_record()) ::
          {:ok, %{entity: scene_record(), deleted_ids: [integer()]}} | {:error, term()}
  defdelegate delete_scene_subtree(scene), to: Editor
  defdelegate delete_scene_subtree(actor_scope, scene), to: Editor

  @doc false
  defdelegate delete_scene_subtree_in_transaction(scene), to: Editor
  defdelegate delete_scene_subtree_in_transaction(actor_scope, scene), to: Editor

  @doc """
  Permanently deletes a scene from the database.
  Use with caution - this cannot be undone.
  """
  @spec hard_delete_scene(scene_record()) :: {:ok, scene_record()} | {:error, changeset()}
  defdelegate hard_delete_scene(scene), to: Editor

  @doc """
  Restores a soft-deleted scene.
  """
  @spec restore_scene(scene_record()) :: {:ok, scene_record()} | {:error, changeset()}
  defdelegate restore_scene(scene), to: Editor

  @doc """
  Lists all soft-deleted scenes for a project (trash).
  """
  @spec list_deleted_scenes(integer()) :: [scene_record()]
  defdelegate list_deleted_scenes(project_id), to: Editor

  @doc """
  Lists scenes as a tree with limited zone/pin elements for the sidebar.
  """
  defdelegate list_scenes_tree_with_elements(project_id), to: Editor

  @doc """
  Returns ancestors from root to direct parent, ordered top-down.
  """
  defdelegate list_ancestors(scene), to: Editor

  @doc """
  Returns a changeset for tracking scene changes.
  """
  @spec change_scene(scene_record(), attrs()) :: changeset()
  defdelegate change_scene(scene, attrs \\ %{}), to: Editor

  @doc "Soft-deletes a scene subtree by ids inside the caller's transaction (command palette)."
  defdelegate delete_scene_subtree_by_id_in_transaction(actor_scope, project_id, scene_id),
    to: Editor

  @doc "Returns a Scene-owned project projection after authorization."
  defdelegate get_project(scope, project_id), to: Access

  @doc "Returns a Scene-owned project projection by workspace and project slugs."
  defdelegate get_project_by_slugs(scope, workspace_slug, project_slug), to: Access

  @doc "Lists active image assets available to the Scene editor."
  defdelegate list_image_asset_ids(project_id), to: Assets

  @doc "Gets an asset through the Scene-owned read projection."
  defdelegate get_asset(project_id, asset_id), to: Assets

  @doc "Consumes a Scene editor upload through the Scene-owned asset command."
  defdelegate upload_asset(path, entry, project, user, opts), to: Assets

  @doc "Creates a sanitized SVG through the Scene-owned asset command."
  defdelegate create_sanitized_svg_asset(binary, attrs, project, user), to: Assets

  @doc "Creates a binary asset through the Scene-owned asset command."
  defdelegate create_binary_asset(binary, attrs, project, user), to: Assets

  @doc "Identifies a Scene pin without exposing the internal schema module to adapters."
  def scene_pin?(%ScenePin{}), do: true
  def scene_pin?(_term), do: false

  @doc "Identifies a Scene zone without exposing the internal schema module to adapters."
  def scene_zone?(%SceneZone{}), do: true
  def scene_zone?(_term), do: false

  @doc "Returns the Scene-owned health severity ordering."
  defdelegate health_severity_rank(severity), to: Health, as: :severity_rank

  @doc "Normalizes a route waypoint pause in Scene vocabulary."
  defdelegate waypoint_pause_ms(waypoint), to: Editor

  # =============================================================================
  # Tree Operations
  # =============================================================================

  @doc """
  Moves a scene to a new parent at a specific position.
  """
  @spec move_scene_to_position(scene_record(), integer() | nil, integer()) ::
          {:ok, scene_record()} | {:error, term()}
  defdelegate move_scene_to_position(scene, new_parent_id, new_position), to: Editor

  # =============================================================================
  # Layers
  # =============================================================================

  @doc """
  Lists all layers for a scene, ordered by position.
  """
  @spec list_layers(integer()) :: [layer()]
  defdelegate list_layers(scene_id), to: Editor

  @doc """
  Gets a single layer by ID within a scene.
  Returns `nil` if not found.
  """
  @spec get_layer(integer(), integer()) :: layer() | nil
  defdelegate get_layer(scene_id, layer_id), to: Editor

  @doc """
  Gets a single layer by ID within a scene.
  Raises `Ecto.NoResultsError` if not found.
  """
  @spec get_layer!(integer(), integer()) :: layer()
  defdelegate get_layer!(scene_id, layer_id), to: Editor

  @doc """
  Creates a new layer in a scene with auto-assigned position.
  """
  @spec create_layer(integer(), attrs()) :: {:ok, layer()} | {:error, changeset()}
  defdelegate create_layer(scene_id, attrs), to: Editor

  @doc """
  Updates a layer.
  """
  @spec update_layer(layer(), attrs()) :: {:ok, layer()} | {:error, changeset()}
  defdelegate update_layer(layer, attrs), to: Editor

  @doc """
  Toggles the visibility of a layer.
  """
  @spec toggle_layer_visibility(layer()) :: {:ok, layer()} | {:error, changeset()}
  defdelegate toggle_layer_visibility(layer), to: Editor

  @doc """
  Deletes a layer. Returns `{:error, :cannot_delete_last_layer}` if it's the only layer.
  Zones and pins on this layer have their layer_id nullified.
  """
  @spec delete_layer(layer()) ::
          {:ok, layer()} | {:error, :cannot_delete_last_layer | changeset()}
  defdelegate delete_layer(layer), to: Editor

  @doc """
  Reorders layers by updating positions.
  """
  @spec reorder_layers(integer(), [integer()]) :: {:ok, [layer()]} | {:error, term()}
  defdelegate reorder_layers(scene_id, layer_ids), to: Editor

  # =============================================================================
  # Zones
  # =============================================================================

  @doc """
  Lists zones for a scene, with optional `:layer_id` filter.
  """
  @spec list_zones(integer(), keyword()) :: [zone()]
  defdelegate list_zones(scene_id, opts \\ []), to: Editor

  @doc """
  Gets a zone by ID. Returns `nil` if not found.
  """
  @spec get_zone(integer()) :: zone() | nil
  defdelegate get_zone(zone_id), to: Editor

  @doc """
  Gets a zone by ID, scoped to a specific scene. Returns `nil` if not found.
  """
  @spec get_zone(integer(), integer()) :: zone() | nil
  defdelegate get_zone(scene_id, zone_id), to: Editor

  @doc """
  Gets a zone by ID. Raises if not found.
  """
  @spec get_zone!(integer()) :: zone()
  defdelegate get_zone!(zone_id), to: Editor

  @doc """
  Gets a zone by ID, scoped to a specific scene. Raises if not found.
  """
  @spec get_zone!(integer(), integer()) :: zone()
  defdelegate get_zone!(scene_id, zone_id), to: Editor

  @doc """
  Creates a zone in a scene with auto-assigned position.
  """
  @spec create_zone(integer(), attrs()) :: {:ok, zone()} | {:error, changeset()}
  defdelegate create_zone(scene_id, attrs), to: Editor

  @doc """
  Updates a zone.
  """
  @spec update_zone(zone(), attrs()) :: {:ok, zone()} | {:error, changeset()}
  defdelegate update_zone(zone, attrs), to: Editor

  @doc """
  Updates only the vertices of a zone (optimized for drag operations).
  """
  @spec update_zone_vertices(zone(), attrs()) :: {:ok, zone()} | {:error, changeset()}
  defdelegate update_zone_vertices(zone, attrs), to: Editor

  @doc """
  Deletes a zone (hard delete).
  """
  @spec delete_zone(zone()) :: {:ok, zone()} | {:error, changeset()}
  defdelegate delete_zone(zone), to: Editor

  @doc """
  Finds the zone on a parent scene that targets a child scene.
  """
  defdelegate get_zone_linking_to_scene(parent_scene_id, child_scene_id), to: Editor

  @doc """
  Lists zones with a non-navigate action_type, ordered by position.
  """
  @spec list_actionable_zones(integer()) :: [zone()]
  defdelegate list_actionable_zones(scene_id), to: Editor

  # =============================================================================
  # Zone Image Extraction
  # =============================================================================

  @doc """
  Extracts a zone's bounding-box region from the parent scene's background image,
  upscales to a minimum usable size, and returns the new Asset with dimensions.

  The `parent_scene` must have `:background_asset` preloaded.
  """
  defdelegate extract_zone_image(parent_scene, zone, project), to: Assets

  @doc """
  Computes the bounding box of zone vertices as {min_x, min_y, max_x, max_y} in percentages.
  """
  defdelegate zone_bounding_box(vertices), to: Assets

  @doc """
  Normalizes zone vertices into child coordinate space (0-100% relative to bounding box).
  """
  defdelegate normalize_zone_vertices(vertices), to: Assets

  # =============================================================================
  # Pins
  # =============================================================================

  @doc """
  Lists pins for a scene, with optional `:layer_id` filter.
  """
  @spec list_pins(integer(), keyword()) :: [pin()]
  defdelegate list_pins(scene_id, opts \\ []), to: Editor

  @doc """
  Gets a pin by ID. Returns `nil` if not found.
  """
  @spec get_pin(integer()) :: pin() | nil
  defdelegate get_pin(pin_id), to: Editor

  @doc """
  Gets a pin by ID, scoped to a specific scene. Returns `nil` if not found.
  """
  @spec get_pin(integer(), integer()) :: pin() | nil
  defdelegate get_pin(scene_id, pin_id), to: Editor

  @doc """
  Gets a pin by ID. Raises if not found.
  """
  @spec get_pin!(integer()) :: pin()
  defdelegate get_pin!(pin_id), to: Editor

  @doc """
  Gets a pin by ID, scoped to a specific scene. Raises if not found.
  """
  @spec get_pin!(integer(), integer()) :: pin()
  defdelegate get_pin!(scene_id, pin_id), to: Editor

  @doc """
  Creates a pin in a scene with auto-assigned position.
  """
  @spec create_pin(integer(), attrs()) :: {:ok, pin()} | {:error, changeset()}
  defdelegate create_pin(scene_id, attrs), to: Editor

  @doc """
  Updates a pin.
  """
  @spec update_pin(pin(), attrs()) :: {:ok, pin()} | {:error, changeset()}
  defdelegate update_pin(pin, attrs), to: Editor

  @doc """
  Moves a pin to new coordinates (position_x/position_y only — drag optimization).
  """
  @spec move_pin(pin(), float(), float()) :: {:ok, pin()} | {:error, changeset()}
  defdelegate move_pin(pin, position_x, position_y), to: Editor

  @doc """
  Deletes a pin (hard delete). Connections to/from this pin are cascaded via FK.
  """
  @spec delete_pin(pin()) :: {:ok, pin()} | {:error, changeset()}
  defdelegate delete_pin(pin), to: Editor

  # =============================================================================
  # Connections
  # =============================================================================

  @doc """
  Lists all connections for a scene, with from_pin and to_pin preloaded.
  """
  @spec list_connections(integer()) :: [connection()]
  defdelegate list_connections(scene_id), to: Editor

  @doc """
  Gets a connection by ID, scoped to a specific scene. Returns `nil` if not found.
  """
  @spec get_connection(integer(), integer()) :: connection() | nil
  defdelegate get_connection(scene_id, connection_id), to: Editor

  @doc """
  Gets a connection by ID, scoped to a specific scene. Raises if not found.
  """
  @spec get_connection!(integer(), integer()) :: connection()
  defdelegate get_connection!(scene_id, connection_id), to: Editor

  @doc """
  Creates a connection between two pins in a scene.
  Validates both pins belong to the same scene.
  """
  @spec create_connection(integer(), attrs()) ::
          {:ok, connection()} | {:error, changeset() | atom()}
  defdelegate create_connection(scene_id, attrs), to: Editor

  @doc """
  Updates a connection.
  """
  @spec update_connection(connection(), attrs()) :: {:ok, connection()} | {:error, changeset()}
  defdelegate update_connection(connection, attrs), to: Editor

  @spec update_connection_waypoints(connection(), attrs()) ::
          {:ok, connection()} | {:error, changeset()}
  defdelegate update_connection_waypoints(connection, attrs), to: Editor

  @doc """
  Deletes a connection (hard delete).
  """
  @spec delete_connection(connection()) :: {:ok, connection()} | {:error, changeset()}
  defdelegate delete_connection(connection), to: Editor

  # =============================================================================
  # Annotations
  # =============================================================================

  @spec list_annotations(integer()) :: [annotation()]
  defdelegate list_annotations(scene_id), to: Editor

  @spec get_annotation(integer(), integer()) :: annotation() | nil
  defdelegate get_annotation(scene_id, annotation_id), to: Editor

  @spec get_annotation!(integer(), integer()) :: annotation()
  defdelegate get_annotation!(scene_id, annotation_id), to: Editor

  @spec create_annotation(integer(), attrs()) :: {:ok, annotation()} | {:error, changeset()}
  defdelegate create_annotation(scene_id, attrs), to: Editor

  @spec update_annotation(annotation(), attrs()) :: {:ok, annotation()} | {:error, changeset()}
  defdelegate update_annotation(annotation, attrs), to: Editor

  @spec move_annotation(annotation(), float(), float()) ::
          {:ok, annotation()} | {:error, changeset()}
  defdelegate move_annotation(annotation, position_x, position_y), to: Editor

  @spec delete_annotation(annotation()) :: {:ok, annotation()} | {:error, changeset()}
  defdelegate delete_annotation(annotation), to: Editor

  # =============================================================================
  # Ambient Flows
  # =============================================================================

  @doc "Lists ambient flows for a scene, ordered by position. Preloads `:flow`."
  @spec list_ambient_flows(integer()) :: [ambient_flow()]
  defdelegate list_ambient_flows(scene_id), to: Editor

  @doc "Gets a single ambient flow scoped to a scene. Returns `nil` if not found."
  @spec get_ambient_flow(integer(), integer()) :: ambient_flow() | nil
  defdelegate get_ambient_flow(scene_id, id), to: Editor

  @doc "Creates an ambient flow link. Validates flow belongs to same project."
  @spec create_ambient_flow(integer(), attrs()) :: {:ok, ambient_flow()} | {:error, term()}
  defdelegate create_ambient_flow(scene_id, attrs), to: Editor

  @doc "Updates an ambient flow (enabled, trigger_type, position)."
  @spec update_ambient_flow(ambient_flow(), attrs()) ::
          {:ok, ambient_flow()} | {:error, changeset()}
  defdelegate update_ambient_flow(ambient_flow, attrs), to: Editor

  @doc "Deletes an ambient flow link."
  @spec delete_ambient_flow(ambient_flow()) :: {:ok, ambient_flow()} | {:error, changeset()}
  defdelegate delete_ambient_flow(ambient_flow), to: Editor

  @doc "Reorders ambient flows by updating positions from ordered ID list."
  @spec reorder_ambient_flows(integer(), [integer()]) ::
          {:ok, [ambient_flow()]} | {:error, term()}
  defdelegate reorder_ambient_flows(scene_id, ordered_ids), to: Editor

  # =============================================================================
  # Scene-owned Flow and Sheet projections
  # =============================================================================

  @doc "Returns a bounded page of active assets for Scene pickers."
  defdelegate search_asset_options(project_id, kind, opts \\ []), to: Assets, as: :asset_options

  @doc "Builds an initial Scene asset picker page retaining every selected asset."
  defdelegate initial_asset_options(project_id, kind, selected_ids), to: Assets

  @doc "Lists the active Flow identities visible to Scenes."
  defdelegate list_flows(project_id), to: Exploration

  @doc "Searches active Flow identities for Scene pickers."
  defdelegate search_flows(project_id, query, opts \\ []), to: Exploration

  @doc "Gets an active Flow identity scoped to the Scene project."
  defdelegate get_flow(project_id, flow_id), to: Exploration

  @doc "Gets a lightweight active Flow identity scoped to the Scene project."
  def get_flow_brief(project_id, flow_id), do: Exploration.get_flow(project_id, flow_id)

  @doc "Loads the executable graph projection owned by Scene exploration."
  defdelegate get_runtime_flow(project_id, flow_id), to: Exploration

  @doc "Loads the active node map for a Scene-owned Flow runtime graph."
  defdelegate runtime_nodes(project_id, flow_id), to: Exploration

  @doc "Loads the connections for a Scene-owned Flow runtime graph."
  defdelegate runtime_connections(project_id, flow_id), to: Exploration

  @doc "Lists active Sheets as a tree for Scene editor selectors."
  defdelegate list_sheets_tree(project_id), to: Exploration

  @doc "Lists active Sheet speaker records for Scene exploration."
  defdelegate list_all_sheets(project_id), to: Exploration

  @doc "Searches active Sheet identities for Scene pickers."
  defdelegate search_sheets(project_id, query, opts \\ []), to: Exploration

  @doc "Gets an active Sheet identity scoped to the Scene project."
  defdelegate get_sheet(project_id, sheet_id), to: Exploration

  @doc "Returns every variable addressable by Scene conditions and instructions."
  defdelegate list_referenceable_variables(project_id), to: Expressions, as: :list_referenceable

  @doc "Builds the in-memory variable state used by Scene exploration."
  defdelegate build_runtime_variables(project_id), to: Exploration

  # =============================================================================
  # Scene exploration Flow runtime
  # =============================================================================

  @doc "Initializes Scene-owned Flow execution state."
  defdelegate runtime_init(variables, entry_id), to: Exploration

  @doc "Advances execution until the next interactive node."
  defdelegate runtime_step_until_interactive(state, nodes, connections, opts \\ []),
    to: Exploration

  @doc "Selects a dialogue response in Scene exploration."
  defdelegate runtime_choose_response(state, response_id, connections), to: Exploration

  @doc "Steps Scene exploration back to its previous execution snapshot."
  defdelegate runtime_step_back(state), to: Exploration

  @doc "Pushes a parent graph before entering a nested Flow."
  defdelegate runtime_push_flow_context(state, node_id, nodes, connections, flow_name), to: Exploration

  @doc "Restores the parent graph after returning from a nested Flow."
  defdelegate runtime_pop_flow_context(state), to: Exploration

  @doc "Finds the parent connection associated with a returned Flow exit."
  defdelegate runtime_find_return_connection(connections, return_node_id, returned_exit_node_id), to: Exploration

  @doc "Evaluates a condition against the Scene exploration variable state."
  defdelegate evaluate_runtime_condition(condition, variables), to: Exploration

  @doc "Executes variable assignments in the Scene exploration variable state."
  defdelegate execute_runtime_instructions(assignments, variables), to: Exploration

  @doc "Builds the browser-neutral slide projected by Scene exploration."
  defdelegate build_runtime_slide(node, state, speakers_map, project_id), to: Exploration

  @doc "Formats a runtime value for Scene presentation."
  defdelegate format_runtime_value(value), to: Exploration

  @doc "Returns the entry node ID from a Scene-owned runtime graph."
  defdelegate runtime_entry_node(nodes), to: Exploration

  # =============================================================================
  # Preload Helpers (wrap Repo.preload to keep web layer clean)
  # =============================================================================

  @doc "Preloads pin associations (icon_asset, sheet with avatars)."
  defdelegate preload_pin_associations(pin), to: Editor

  @doc "Preloads scene background_asset association."
  defdelegate preload_scene_background(scene), to: Editor

  @doc "Preloads sheet avatars association."
  defdelegate preload_sheet_avatar(sheet), to: Editor

  # =============================================================================
  # Dashboard Stats
  # =============================================================================

  @doc "Returns per-scene zone, pin, and connection counts. %{scene_id => %{zone_count, pin_count, connection_count}}."
  defdelegate scene_stats_for_project(project_id), to: Health

  @doc "Returns the count of scenes that have a background image."
  defdelegate scenes_with_background_count(project_id), to: Health

  @doc "Returns the canonical project-wide scene health findings, one checker run per scene."
  defdelegate list_dashboard_health_findings(project_id), to: Health

  @doc "Normalizes the project-wide reference sets a scene health check needs."
  defdelegate scene_health_references(attrs), to: Health, as: :references

  @doc "Returns the canonical health findings for one scene and its elements."
  defdelegate scene_health_findings(scene, collections, references), to: Health, as: :findings

  # =============================================================================
  # Exploration Sessions
  # =============================================================================

  @doc "Gets an existing exploration session for a user and project."
  defdelegate get_exploration_session(user_id, project_id),
    to: Exploration,
    as: :get_session

  @doc "Upserts an exploration session (create or update, includes positions)."
  defdelegate save_exploration_session(user_id, project_id, attrs),
    to: Exploration,
    as: :save_session

  @doc "Deletes an exploration session (new game)."
  defdelegate delete_exploration_session(user_id, project_id),
    to: Exploration,
    as: :delete_session

  @doc "Deletes exploration sessions older than N days."
  defdelegate cleanup_old_exploration_sessions(days \\ 30),
    to: Exploration,
    as: :cleanup_old_sessions

  @doc "Recomputes Scene exploration formula variables."
  defdelegate recompute_runtime_formulas(variables),
    to: Exploration

  @doc "Emits the typed Scene fact that an exploration session started."
  defdelegate record_exploration_started(scope, scene, has_saved_session),
    to: Exploration,
    as: :exploration_started

  @doc "Emits the typed Scene fact that the version panel was opened."
  defdelegate record_version_panel_opened(scope, scene),
    to: Versioning

  @doc "Emits the typed Scene fact that a version comparison was opened."
  defdelegate record_version_compared(scope, scene), to: Versioning

  @doc "Creates a named Scene version and emits its Scene-owned fact."
  defdelegate create_named_version(scope, scene, opts), to: Versioning

  @doc "Restores a Scene version and emits its Scene-owned fact on success."
  defdelegate restore_tracked_version(scope, scene, version, opts),
    to: Versioning

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
  defdelegate can_create_named_version?(project_id, workspace_id), to: Versioning

  @doc """
  Sets the current version for a scene.
  """
  def set_current_version(%Scene{} = scene, version_or_nil) do
    Versioning.set_current_version(scene, version_or_nil)
  end
end

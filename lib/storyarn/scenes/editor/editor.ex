defmodule Storyarn.Scenes.Editor do
  @moduledoc """
  Public application boundary for the Scene editor capability.

  It keeps presentation and sibling capabilities independent of the internal
  query/command organization while preserving the established Scene entities.
  """

  alias Storyarn.Scenes.Editor.Commands
  alias Storyarn.Scenes.Editor.Queries

  defdelegate waypoint_pause_ms(waypoint), to: Storyarn.Scenes.RoutePoints

  defdelegate list_scenes(project_id), to: Queries.Scenes
  defdelegate list_scenes_tree(project_id), to: Queries.Scenes
  defdelegate list_scenes_tree_with_elements(project_id), to: Queries.Scenes
  defdelegate search_scenes(project_id, query, opts \\ []), to: Queries.Scenes
  defdelegate search_scenes_deep(project_id, query, opts \\ []), to: Queries.Scenes
  defdelegate get_scene(project_id, scene_id), to: Queries.Scenes
  defdelegate get_scene!(project_id, scene_id), to: Queries.Scenes
  defdelegate get_scene_by_id(scene_id), to: Queries.Scenes
  defdelegate get_scene_brief(project_id, scene_id), to: Queries.Scenes
  defdelegate get_scene_including_deleted(project_id, scene_id), to: Queries.Scenes
  defdelegate list_deleted_scenes(project_id), to: Queries.Scenes
  defdelegate list_ancestors(scene), to: Queries.Scenes
  defdelegate preload_pin_associations(pin), to: Queries.Preloads
  defdelegate preload_scene_background(scene), to: Queries.Preloads
  defdelegate preload_sheet_avatar(sheet), to: Queries.Preloads

  defdelegate create_scene(project, attrs), to: Commands.Scenes
  defdelegate create_scene(actor_scope, project, attrs), to: Commands.Scenes
  defdelegate create_scene_in_transaction(project, attrs), to: Commands.Scenes
  defdelegate create_scene_in_transaction(actor_scope, project, attrs), to: Commands.Scenes
  defdelegate update_scene(scene, attrs), to: Commands.Scenes
  defdelegate delete_scene(scene), to: Commands.Scenes
  defdelegate delete_scene(actor_scope, scene), to: Commands.Scenes
  defdelegate delete_scene_subtree(scene), to: Commands.Scenes
  defdelegate delete_scene_subtree(actor_scope, scene), to: Commands.Scenes
  defdelegate delete_scene_subtree_in_transaction(scene), to: Commands.Scenes
  defdelegate delete_scene_subtree_in_transaction(actor_scope, scene), to: Commands.Scenes

  defdelegate delete_scene_subtree_by_id_in_transaction(actor_scope, project_id, scene_id),
    to: Commands.Scenes

  defdelegate hard_delete_scene(scene), to: Commands.Scenes
  defdelegate restore_scene(scene), to: Commands.Scenes
  defdelegate change_scene(scene, attrs \\ %{}), to: Commands.Scenes

  defdelegate move_scene_to_position(scene, new_parent_id, new_position), to: Commands.Tree
  defdelegate reorder_scenes(project_id, parent_id, scene_ids), to: Commands.Tree

  defdelegate list_layers(scene_id), to: Queries.Layers
  defdelegate get_layer(scene_id, layer_id), to: Queries.Layers
  defdelegate get_layer!(scene_id, layer_id), to: Queries.Layers
  defdelegate create_layer(scene_id, attrs), to: Commands.Layers
  defdelegate update_layer(layer, attrs), to: Commands.Layers
  defdelegate toggle_layer_visibility(layer), to: Commands.Layers
  defdelegate delete_layer(layer), to: Commands.Layers
  defdelegate reorder_layers(scene_id, layer_ids), to: Commands.Layers
  defdelegate change_layer(layer, attrs \\ %{}), to: Commands.Layers

  defdelegate list_zones(scene_id, opts \\ []), to: Queries.Zones
  defdelegate get_zone(zone_id), to: Queries.Zones
  defdelegate get_zone(scene_id, zone_id), to: Queries.Zones
  defdelegate get_zone!(zone_id), to: Queries.Zones
  defdelegate get_zone!(scene_id, zone_id), to: Queries.Zones
  defdelegate get_zone_linking_to_scene(parent_scene_id, child_scene_id), to: Queries.Zones
  defdelegate list_actionable_zones(scene_id), to: Queries.Zones
  defdelegate create_zone(scene_id, attrs), to: Commands.Zones
  defdelegate update_zone(zone, attrs), to: Commands.Zones
  defdelegate update_zone_vertices(zone, attrs), to: Commands.Zones
  defdelegate delete_zone(zone), to: Commands.Zones
  defdelegate change_zone(zone, attrs \\ %{}), to: Commands.Zones

  defdelegate list_pins(scene_id, opts \\ []), to: Queries.Pins
  defdelegate get_pin(pin_id), to: Queries.Pins
  defdelegate get_pin(scene_id, pin_id), to: Queries.Pins
  defdelegate get_pin!(pin_id), to: Queries.Pins
  defdelegate get_pin!(scene_id, pin_id), to: Queries.Pins
  defdelegate create_pin(scene_id, attrs), to: Commands.Pins
  defdelegate update_pin(pin, attrs), to: Commands.Pins
  defdelegate move_pin(pin, position_x, position_y), to: Commands.Pins
  defdelegate delete_pin(pin), to: Commands.Pins
  defdelegate change_pin(pin, attrs \\ %{}), to: Commands.Pins

  defdelegate list_connections(scene_id), to: Queries.Connections
  defdelegate get_connection(scene_id, connection_id), to: Queries.Connections
  defdelegate get_connection!(scene_id, connection_id), to: Queries.Connections
  defdelegate create_connection(scene_id, attrs), to: Commands.Connections
  defdelegate update_connection(connection, attrs), to: Commands.Connections
  defdelegate update_connection_waypoints(connection, attrs), to: Commands.Connections
  defdelegate delete_connection(connection), to: Commands.Connections
  defdelegate change_connection(connection, attrs \\ %{}), to: Commands.Connections

  defdelegate list_annotations(scene_id), to: Queries.Annotations
  defdelegate get_annotation(scene_id, annotation_id), to: Queries.Annotations
  defdelegate get_annotation!(scene_id, annotation_id), to: Queries.Annotations
  defdelegate create_annotation(scene_id, attrs), to: Commands.Annotations
  defdelegate update_annotation(annotation, attrs), to: Commands.Annotations
  defdelegate move_annotation(annotation, position_x, position_y), to: Commands.Annotations
  defdelegate delete_annotation(annotation), to: Commands.Annotations

  defdelegate list_ambient_flows(scene_id), to: Queries.AmbientFlows
  defdelegate get_ambient_flow(scene_id, id), to: Queries.AmbientFlows
  defdelegate create_ambient_flow(scene_id, attrs), to: Commands.AmbientFlows
  defdelegate update_ambient_flow(ambient_flow, attrs), to: Commands.AmbientFlows
  defdelegate delete_ambient_flow(ambient_flow), to: Commands.AmbientFlows
  defdelegate reorder_ambient_flows(scene_id, ordered_ids), to: Commands.AmbientFlows
end

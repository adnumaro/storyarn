defmodule StoryarnWeb.Components.Sidebar.SceneTree do
  @moduledoc """
  Scene tree components for the project sidebar.

  Thin wrapper around `GenericTree` with scene-specific configuration.
  Includes extra children for zones and pins rendered inside each scene node.
  """

  use Phoenix.Component
  use StoryarnWeb, :verified_routes
  use Gettext, backend: StoryarnWeb.Gettext

  import StoryarnWeb.Components.TreeComponents
  import StoryarnWeb.Components.Sidebar.GenericTree

  attr :scenes_tree, :list, required: true
  attr :workspace, :map, required: true
  attr :project, :map, required: true
  attr :selected_scene_id, :string, default: nil
  attr :can_edit, :boolean, default: false

  def scenes_section(assigns) do
    ~H"""
    <.entity_tree_section
      tree={@scenes_tree}
      workspace={@workspace}
      project={@project}
      selected_id={@selected_scene_id}
      can_edit={@can_edit}
      entity_type="scenes"
      search_placeholder={dgettext("scenes", "Filter scenes...")}
      empty_text={dgettext("scenes", "No scenes yet")}
      create_event="create_scene"
      create_label={dgettext("scenes", "New Scene")}
      delete_title={dgettext("scenes", "Delete scene?")}
      delete_message={dgettext("scenes", "Are you sure you want to delete this scene?")}
      delete_confirm_text={dgettext("scenes", "Delete")}
      confirm_delete_event="confirm_delete_scene"
      icon="map"
      href_fn={&scene_href/3}
      link_type={:patch}
      create_child_event="create_child_scene"
      create_child_title={dgettext("scenes", "Add child scene")}
      set_pending_delete_event="set_pending_delete_scene"
      delete_label={dgettext("scenes", "Move to Trash")}
    >
      <:extra_children :let={scene}>
        <.element_leaves
          items={Map.get(scene, :sidebar_zones, [])}
          total_count={Map.get(scene, :zone_count, 0)}
          icon="pentagon"
          scene_id={scene.id}
          workspace={@workspace}
          project={@project}
          element_type="zone"
          label_fn={& &1.name}
          more_text={
            dgettext("scenes", "%{count} more zones\u2026",
              count: Map.get(scene, :zone_count, 0) - length(Map.get(scene, :sidebar_zones, []))
            )
          }
        />
        <.element_leaves
          items={Map.get(scene, :sidebar_pins, [])}
          total_count={Map.get(scene, :pin_count, 0)}
          icon="map-pin"
          scene_id={scene.id}
          workspace={@workspace}
          project={@project}
          element_type="pin"
          label_fn={&(&1.label || dgettext("scenes", "Pin"))}
          more_text={
            dgettext("scenes", "%{count} more pins\u2026",
              count: Map.get(scene, :pin_count, 0) - length(Map.get(scene, :sidebar_pins, []))
            )
          }
        />
      </:extra_children>
    </.entity_tree_section>
    """
  end

  def delete_modal(assigns) do
    ~H"""
    <.entity_delete_modal
      entity_type="scenes"
      title={dgettext("scenes", "Delete scene?")}
      message={dgettext("scenes", "Are you sure you want to delete this scene?")}
      confirm_text={dgettext("scenes", "Delete")}
      confirm_event="confirm_delete_scene"
    />
    """
  end

  defp scene_href(workspace, project, scene) do
    ~p"/workspaces/#{workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
  end

  # ── Element leaves (zones/pins) ──────────────────────────────────────

  attr :items, :list, required: true
  attr :total_count, :integer, required: true
  attr :icon, :string, required: true
  attr :scene_id, :any, required: true
  attr :workspace, :map, required: true
  attr :project, :map, required: true
  attr :element_type, :string, required: true
  attr :label_fn, :any, required: true
  attr :more_text, :string, required: true

  defp element_leaves(assigns) do
    base =
      ~p"/workspaces/#{assigns.workspace.slug}/projects/#{assigns.project.slug}/scenes/#{assigns.scene_id}"

    assigns =
      assign(
        assigns,
        :items_with_href,
        Enum.map(assigns.items, fn item ->
          {item, "#{base}?highlight=#{assigns.element_type}:#{item.id}"}
        end)
      )

    ~H"""
    <.tree_leaf
      :for={{item, href} <- @items_with_href}
      label={@label_fn.(item)}
      icon={@icon}
      href={href}
      active={false}
      item_id={"#{@element_type}-#{item.id}"}
      item_name={@label_fn.(item)}
      can_drag={false}
      link_type={:patch}
    />
    <div :if={@total_count > length(@items)} class="text-xs text-base-content/40 pl-8 py-0.5">
      {@more_text}
    </div>
    """
  end
end

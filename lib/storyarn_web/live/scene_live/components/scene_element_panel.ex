defmodule StoryarnWeb.SceneLive.Components.SceneElementPanel do
  @moduledoc """
  Sliding right-side panel for scene element properties.

  Renders per-type content (zone/pin/connection/annotation) moved from the
  floating toolbar's "more" popover. Mirrors the flow editor's BuilderSidebar pattern.
  """

  use StoryarnWeb, :html
  use Gettext, backend: Storyarn.Gettext

  alias Phoenix.LiveView.JS
  alias StoryarnWeb.Components.SearchableSelect

  import StoryarnWeb.Components.ConditionBuilder
  import StoryarnWeb.Components.ExpressionEditor
  import StoryarnWeb.SceneLive.Components.CollectionItemsEditor
  import StoryarnWeb.SceneLive.Components.ToolbarWidgets

  attr :selected_type, :string, required: true
  attr :selected_element, :map, required: true
  attr :can_edit, :boolean, default: true
  attr :project_id, :integer, required: true
  attr :project_scenes, :list, default: []
  attr :project_sheets, :list, default: []
  attr :project_flows, :list, default: []
  attr :project_variables, :list, default: []
  attr :panel_sections, :map, default: %{}

  def scene_element_panel(assigns) do
    ~H"""
    <div class="flex items-center justify-between p-4 border-b border-base-300 shrink-0">
      <h3 class="font-semibold text-sm">{panel_title(@selected_type)}</h3>
      <button
        type="button"
        class="btn btn-ghost btn-xs btn-square"
        phx-click={JS.dispatch("panel:close", to: "#scene-element-panel")}
      >
        <.icon name="x" class="size-3.5" />
      </button>
    </div>
    <div class="p-4 overflow-y-auto flex-1">
      <.zone_panel
        :if={@selected_type == "zone"}
        zone={@selected_element}
        can_edit={@can_edit}
        project_id={@project_id}
        project_scenes={@project_scenes}
        project_sheets={@project_sheets}
        project_flows={@project_flows}
        project_variables={@project_variables}
        panel_sections={@panel_sections}
      />
      <.pin_panel
        :if={@selected_type == "pin"}
        pin={@selected_element}
        can_edit={@can_edit}
        project_id={@project_id}
        project_scenes={@project_scenes}
        project_variables={@project_variables}
        panel_sections={@panel_sections}
      />
      <.connection_panel
        :if={@selected_type == "connection"}
        connection={@selected_element}
        can_edit={@can_edit}
      />
      <div :if={@selected_type == "annotation"} class="text-sm text-base-content/40 italic">
        {dgettext("scenes", "No additional properties")}
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Zone panel
  # ---------------------------------------------------------------------------

  @action_types ~w(none walkable instruction display collection)

  attr :zone, :map, required: true
  attr :can_edit, :boolean, default: true
  attr :project_id, :integer, required: true
  attr :project_scenes, :list, default: []
  attr :project_sheets, :list, default: []
  attr :project_flows, :list, default: []
  attr :project_variables, :list, default: []
  attr :panel_sections, :map, default: %{}

  defp zone_panel(assigns) do
    assigns =
      assigns
      |> assign(:action_types, @action_types)
      |> assign(:action_data, assigns.zone.action_data || %{})

    ~H"""
    <div class="space-y-4">
      <%!-- Walkable (only show toggle when action type is NOT already "walkable") --%>
      <div :if={@zone.action_type != "walkable"} class="flex items-center justify-between">
        <label class="text-xs font-medium text-base-content/60 flex items-center gap-1">
          <.icon name="footprints" class="size-3" />
          {dgettext("scenes", "Walkable area")}
        </label>
        <input
          type="checkbox"
          class="toggle toggle-xs toggle-primary"
          checked={@zone.is_walkable}
          phx-click={
            JS.push("update_zone",
              value: %{id: @zone.id, field: "is_walkable", toggle: to_string(!@zone.is_walkable)}
            )
          }
          disabled={!@can_edit}
        />
      </div>

      <%!-- Shortcut --%>
      <div :if={@zone.shortcut} class="flex items-center gap-2">
        <label class="text-xs font-medium text-base-content/60 shrink-0">
          {dgettext("scenes", "Shortcut")}
        </label>
        <div class="text-xs font-mono text-base-content/80 bg-base-200 rounded px-2 py-0.5 truncate">
          {@zone.shortcut}
        </div>
      </div>

      <%!-- Hidden in exploration --%>
      <div class="flex items-center justify-between">
        <label class="text-xs font-medium text-base-content/60 flex items-center gap-1">
          <.icon name="eye-off" class="size-3" />
          {dgettext("scenes", "Hidden in exploration")}
        </label>
        <input
          type="checkbox"
          class="toggle toggle-xs toggle-primary"
          checked={@zone.hidden}
          phx-click={
            JS.push("update_zone",
              value: %{id: @zone.id, field: "hidden", toggle: to_string(!@zone.hidden)}
            )
          }
          disabled={!@can_edit}
        />
      </div>

      <%!-- Tooltip --%>
      <div>
        <label class="block text-xs font-medium text-base-content/60 mb-1">
          {dgettext("scenes", "Tooltip")}
        </label>
        <input
          type="text"
          value={@zone.tooltip || ""}
          phx-blur="update_zone"
          phx-value-id={@zone.id}
          phx-value-field="tooltip"
          placeholder={dgettext("scenes", "Hover text...")}
          class="input input-sm input-bordered w-full"
          disabled={!@can_edit}
        />
      </div>

      <%!-- Link to --%>
      <div class="pt-3 border-t border-base-300">
        <label class="block text-xs font-medium text-base-content/60 mb-1">
          {dgettext("scenes", "Link to")}
        </label>
        <.toolbar_target_picker
          id={"panel-zone-target-#{@zone.id}"}
          event="update_zone"
          element_id={@zone.id}
          current_type={@zone.target_type}
          current_target_id={@zone.target_id}
          target_types={~w(flow scene)}
          project_scenes={@project_scenes}
          project_sheets={@project_sheets}
          project_flows={@project_flows}
          disabled={!@can_edit}
        />
      </div>

      <%!-- Instruction --%>
      <div :if={@zone.action_type == "instruction"} class="pt-3 border-t border-base-300">
        <label class="block text-xs font-medium text-base-content/60 mb-1">
          {dgettext("scenes", "Assignments")}
        </label>
        <.expression_editor
          id={"panel-zone-instruction-#{@zone.id}"}
          mode="instruction"
          assignments={@action_data["assignments"] || []}
          variables={@project_variables}
          can_edit={@can_edit}
          context={%{"zone-id" => @zone.id}}
          event_name="update_zone_assignments"
          active_tab={Map.get(@panel_sections, "tab_panel-zone-instruction-#{@zone.id}", "builder")}
        />
      </div>

      <%!-- Display --%>
      <div :if={@zone.action_type == "display"} class="pt-3 border-t border-base-300">
        <label class="block text-xs font-medium text-base-content/60 mb-1">
          {dgettext("scenes", "Variable")}
        </label>
        <.display_variable_picker
          id={"panel-zone-display-var-#{@zone.id}"}
          element_id={@zone.id}
          event="update_zone_action_data"
          context_key="zone-id"
          variables={@project_variables}
          selected_ref={@action_data["variable_ref"] || ""}
          can_edit={@can_edit}
        />
      </div>

      <%!-- Collection --%>
      <div :if={@zone.action_type == "collection"} class="pt-3 border-t border-base-300">
        <.collection_items_editor
          zone={@zone}
          action_data={@action_data}
          can_edit={@can_edit}
          project_id={@project_id}
          project_variables={@project_variables}
          panel_sections={@panel_sections}
        />
      </div>

      <%!-- Condition --%>
      <div class="pt-3 border-t border-base-300">
        <div class="flex items-center justify-between mb-1">
          <label class="text-xs font-medium text-base-content/60">
            {dgettext("scenes", "Condition")}
          </label>
          <div class="join">
            <button
              type="button"
              class={[
                "btn btn-xs join-item",
                if((@zone.condition_effect || "hide") == "hide",
                  do: "btn-active",
                  else: "btn-ghost"
                )
              ]}
              phx-click="update_zone_condition_effect"
              phx-value-id={@zone.id}
              phx-value-effect="hide"
              disabled={!@can_edit}
            >
              {dgettext("scenes", "Hide")}
            </button>
            <button
              type="button"
              class={[
                "btn btn-xs join-item",
                if((@zone.condition_effect || "hide") == "disable",
                  do: "btn-active",
                  else: "btn-ghost"
                )
              ]}
              phx-click="update_zone_condition_effect"
              phx-value-id={@zone.id}
              phx-value-effect="disable"
              disabled={!@can_edit}
            >
              {dgettext("scenes", "Disable")}
            </button>
          </div>
        </div>
        <.condition_builder
          id={"panel-zone-condition-#{@zone.id}-#{@can_edit}"}
          condition={@zone.condition}
          variables={@project_variables}
          can_edit={@can_edit}
          event_name="update_zone_condition"
          context={%{"zone-id" => @zone.id}}
        />
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Pin panel
  # ---------------------------------------------------------------------------

  attr :pin, :map, required: true
  attr :can_edit, :boolean, default: true
  attr :project_id, :integer, required: true
  attr :project_scenes, :list, default: []
  attr :project_variables, :list, default: []
  attr :panel_sections, :map, default: %{}

  defp pin_panel(assigns) do
    ~H"""
    <div class="space-y-4">
      <%!-- Tooltip --%>
      <div>
        <label class="block text-xs font-medium text-base-content/60 mb-1">
          {dgettext("scenes", "Tooltip")}
        </label>
        <input
          type="text"
          value={@pin.tooltip || ""}
          phx-blur="update_pin"
          phx-value-id={@pin.id}
          phx-value-field="tooltip"
          placeholder={dgettext("scenes", "Hover text...")}
          class="input input-sm input-bordered w-full"
          disabled={!@can_edit}
        />
      </div>

      <%!-- Linked Sheet --%>
      <div class="pt-3 border-t border-base-300">
        <.live_component
          module={StoryarnWeb.Components.EntitySelect}
          id={"pin-sheet-#{@pin.id}"}
          project_id={@project_id}
          entity_type={:sheet}
          selected_id={@pin.sheet_id}
          label={dgettext("scenes", "Sheet")}
          placeholder={dgettext("scenes", "Select sheet...")}
          disabled={!@can_edit}
        />
      </div>

      <%!-- Playable character --%>
      <div class="pt-3 border-t border-base-300">
        <div class="flex items-center justify-between">
          <label class="text-xs font-medium text-base-content/60 flex items-center gap-1">
            <.icon name="user" class="size-3" />
            {dgettext("scenes", "Playable character")}
          </label>
          <input
            type="checkbox"
            class="toggle toggle-xs toggle-primary"
            checked={@pin.is_playable}
            phx-click={
              JS.push("update_pin",
                value: %{id: @pin.id, field: "is_playable", toggle: to_string(!@pin.is_playable)}
              )
            }
            disabled={!@can_edit}
          />
        </div>
        <%!-- Leader (only if playable) --%>
        <div :if={@pin.is_playable} class="flex items-center justify-between mt-2">
          <label class="text-xs font-medium text-base-content/60 flex items-center gap-1">
            <.icon name="crown" class="size-3" />
            {dgettext("scenes", "Party leader")}
          </label>
          <input
            type="checkbox"
            class="toggle toggle-xs toggle-warning"
            checked={@pin.is_leader}
            phx-click={
              JS.push("update_pin",
                value: %{id: @pin.id, field: "is_leader", toggle: to_string(!@pin.is_leader)}
              )
            }
            disabled={!@can_edit}
          />
        </div>
      </div>

      <%!-- Patrol (only for non-playable pins) --%>
      <div :if={!@pin.is_playable} class="pt-3 border-t border-base-300">
        <label class="block text-xs font-medium text-base-content/60 mb-2 flex items-center gap-1">
          <.icon name="route" class="size-3" />
          {dgettext("scenes", "Patrol")}
        </label>
        <%!-- Patrol mode --%>
        <div class="mb-2">
          <.live_component
            module={SearchableSelect}
            id={"pin-patrol-mode-#{@pin.id}"}
            options={patrol_mode_options()}
            value={@pin.patrol_mode || "none"}
            on_select="update_patrol_mode"
            allow_none={false}
            label={dgettext("scenes", "Mode")}
            disabled={!@can_edit}
          />
        </div>
        <%!-- Speed & Pause (only when patrol mode != none) --%>
        <div :if={(@pin.patrol_mode || "none") != "none"}>
          <div class="mb-2">
            <label class="block text-[10px] text-base-content/40 mb-0.5">
              {dgettext("scenes", "Speed: %{speed}x", speed: @pin.patrol_speed || 1.0)}
            </label>
            <input
              type="range"
              class="range range-xs range-primary w-full"
              min="0.2"
              max="3.0"
              step="0.1"
              value={@pin.patrol_speed || 1.0}
              phx-change="update_pin"
              phx-value-id={@pin.id}
              phx-value-field="patrol_speed"
              name="value"
              disabled={!@can_edit}
            />
          </div>
          <div>
            <label class="block text-[10px] text-base-content/40 mb-0.5">
              {dgettext("scenes", "Pause at waypoints (ms)")}
            </label>
            <input
              type="number"
              class="input input-xs input-bordered w-full"
              min="0"
              max="30000"
              step="100"
              value={@pin.patrol_pause_ms || 0}
              phx-change="update_pin"
              phx-value-id={@pin.id}
              phx-value-field="patrol_pause_ms"
              phx-debounce="300"
              name="value"
              disabled={!@can_edit}
            />
          </div>
        </div>
      </div>

      <%!-- Shortcut --%>
      <div :if={@pin.shortcut} class="pt-3 border-t border-base-300">
        <label class="block text-xs font-medium text-base-content/60 mb-1">
          {dgettext("scenes", "Shortcut")}
        </label>
        <div class="text-xs font-mono text-base-content/80 bg-base-200 rounded px-2 py-1">
          {@pin.shortcut}
        </div>
      </div>

      <%!-- Flow --%>
      <div class="pt-3 border-t border-base-300">
        <.live_component
          module={StoryarnWeb.Components.EntitySelect}
          id={"pin-flow-#{@pin.id}"}
          project_id={@project_id}
          entity_type={:flow}
          selected_id={@pin.flow_id}
          label={dgettext("scenes", "Flow")}
          placeholder={dgettext("scenes", "Select flow...")}
          disabled={!@can_edit}
        />
      </div>

      <%!-- Hidden in exploration --%>
      <div class="pt-3 border-t border-base-300">
        <div class="flex items-center justify-between">
          <label class="text-xs font-medium text-base-content/60 flex items-center gap-1">
            <.icon name="eye-off" class="size-3" />
            {dgettext("scenes", "Hidden in exploration")}
          </label>
          <input
            type="checkbox"
            class="toggle toggle-xs toggle-primary"
            checked={@pin.hidden}
            phx-click={
              JS.push("update_pin",
                value: %{id: @pin.id, field: "hidden", toggle: to_string(!@pin.hidden)}
              )
            }
            disabled={!@can_edit}
          />
        </div>
      </div>

      <%!-- Condition --%>
      <div class="pt-3 border-t border-base-300">
        <div class="flex items-center justify-between mb-1">
          <label class="text-xs font-medium text-base-content/60">
            {dgettext("scenes", "Condition")}
          </label>
          <div class="join">
            <button
              type="button"
              class={[
                "btn btn-xs join-item",
                if((@pin.condition_effect || "hide") == "hide",
                  do: "btn-active",
                  else: "btn-ghost"
                )
              ]}
              phx-click="update_pin_condition_effect"
              phx-value-id={@pin.id}
              phx-value-effect="hide"
              disabled={!@can_edit}
            >
              {dgettext("scenes", "Hide")}
            </button>
            <button
              type="button"
              class={[
                "btn btn-xs join-item",
                if((@pin.condition_effect || "hide") == "disable",
                  do: "btn-active",
                  else: "btn-ghost"
                )
              ]}
              phx-click="update_pin_condition_effect"
              phx-value-id={@pin.id}
              phx-value-effect="disable"
              disabled={!@can_edit}
            >
              {dgettext("scenes", "Disable")}
            </button>
          </div>
        </div>
        <.condition_builder
          id={"panel-pin-condition-#{@pin.id}-#{@can_edit}"}
          condition={@pin.condition}
          variables={@project_variables}
          can_edit={@can_edit}
          event_name="update_pin_condition"
          context={%{"pin-id" => @pin.id}}
        />
      </div>

      <%!-- Custom icon --%>
      <div :if={@can_edit} class="pt-3 border-t border-base-300">
        <button
          type="button"
          phx-click="toggle_pin_icon_upload"
          class="btn btn-ghost btn-sm w-full"
        >
          <.icon name="image" class="size-3.5" />
          {dgettext("scenes", "Change Icon")}
        </button>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Connection panel
  # ---------------------------------------------------------------------------

  attr :connection, :map, required: true
  attr :can_edit, :boolean, default: true

  defp connection_panel(assigns) do
    ~H"""
    <div class="space-y-2">
      <button
        :if={@can_edit && length(@connection.waypoints || []) > 0}
        type="button"
        phx-click={JS.push("clear_connection_waypoints", value: %{id: @connection.id})}
        class="flex items-center gap-2 btn btn-ghost btn-sm w-full justify-start"
      >
        <.icon name="undo-2" class="size-3.5" />
        {dgettext("scenes", "Straighten path")}
      </button>
      <p
        :if={length(@connection.waypoints || []) == 0}
        class="text-sm text-base-content/40 italic"
      >
        {dgettext("scenes", "No waypoints")}
      </p>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Shared: display variable picker
  # ---------------------------------------------------------------------------

  attr :id, :string, required: true
  attr :element_id, :integer, required: true
  attr :event, :string, required: true
  attr :context_key, :string, required: true
  attr :variables, :list, required: true
  attr :selected_ref, :string, default: ""
  attr :can_edit, :boolean, default: true

  defp display_variable_picker(assigns) do
    selected_label =
      if assigns.selected_ref != "" do
        assigns.selected_ref
      end

    assigns = assign(assigns, :selected_label, selected_label)

    ~H"""
    <div id={@id} phx-hook="SearchableSelect">
      <button
        data-role="trigger"
        type="button"
        class="btn btn-sm btn-ghost gap-1 w-full justify-between font-normal border border-base-300"
        disabled={!@can_edit}
      >
        <span :if={@selected_label} class="text-xs truncate">{@selected_label}</span>
        <span :if={!@selected_label} class="text-xs opacity-50">
          {dgettext("scenes", "Select variable...")}
        </span>
        <.icon name="chevron-down" class="size-3 opacity-50 shrink-0" />
      </button>
      <template data-role="popover-template">
        <div class="p-2 pb-1">
          <input
            data-role="search"
            type="text"
            placeholder={dgettext("scenes", "Search variables...")}
            class="input input-xs input-bordered w-full"
            autocomplete="off"
          />
        </div>
        <div data-role="list" class="max-h-48 overflow-y-auto p-1">
          <button
            :if={@selected_ref != ""}
            type="button"
            data-event={@event}
            data-params={
              Jason.encode!(%{@context_key => @element_id, "field" => "variable_ref", "value" => ""})
            }
            data-search-text=""
            class="flex items-center gap-2 w-full px-2 py-1.5 rounded text-xs text-base-content/50 cursor-pointer hover:bg-base-content/10"
          >
            <.icon name="x" class="size-3" />
            {dgettext("scenes", "Clear")}
          </button>
          <button
            :for={var <- @variables}
            type="button"
            data-event={@event}
            data-params={
              Jason.encode!(%{
                @context_key => @element_id,
                "field" => "variable_ref",
                "value" => "#{var.sheet_shortcut}.#{var.variable_name}"
              })
            }
            data-search-text={"#{String.downcase(var.sheet_shortcut)}.#{String.downcase(var.variable_name)}"}
            class={[
              "flex items-center w-full px-2 py-1.5 rounded text-xs cursor-pointer hover:bg-base-content/10 truncate",
              "#{var.sheet_shortcut}.#{var.variable_name}" == @selected_ref &&
                "font-semibold text-primary"
            ]}
          >
            <span class="text-base-content/50">{var.sheet_shortcut}.</span>{var.variable_name}
          </button>
        </div>
        <div
          data-role="empty"
          class="px-3 py-2 text-xs text-base-content/40 italic"
          style="display:none"
        >
          {dgettext("scenes", "No matches")}
        </div>
      </template>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp panel_title("zone"), do: dgettext("scenes", "Zone Properties")
  defp panel_title("pin"), do: dgettext("scenes", "Pin Properties")
  defp panel_title("connection"), do: dgettext("scenes", "Connection Properties")
  defp panel_title("annotation"), do: dgettext("scenes", "Annotation Properties")
  defp panel_title(_), do: dgettext("scenes", "Properties")

  defp patrol_mode_options do
    [
      %{id: "none", name: dgettext("scenes", "None")},
      %{id: "loop", name: dgettext("scenes", "Loop")},
      %{id: "ping_pong", name: dgettext("scenes", "Ping-pong")},
      %{id: "one_way", name: dgettext("scenes", "One-way")}
    ]
  end
end

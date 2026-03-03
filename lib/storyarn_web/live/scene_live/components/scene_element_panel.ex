defmodule StoryarnWeb.SceneLive.Components.SceneElementPanel do
  @moduledoc """
  Sliding right-side panel for scene element properties.

  Renders per-type content (zone/pin/connection/annotation) moved from the
  floating toolbar's "more" popover. Mirrors the flow editor's BuilderSidebar pattern.
  """

  use StoryarnWeb, :html
  use Gettext, backend: StoryarnWeb.Gettext

  alias Phoenix.LiveView.JS

  import StoryarnWeb.Components.ConditionBuilder
  import StoryarnWeb.Components.ExpressionEditor
  import StoryarnWeb.SceneLive.Components.ToolbarWidgets

  attr :selected_type, :string, required: true
  attr :selected_element, :map, required: true
  attr :can_edit, :boolean, default: true
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
        project_scenes={@project_scenes}
        project_sheets={@project_sheets}
        project_flows={@project_flows}
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

  @action_types ~w(none instruction display)

  attr :zone, :map, required: true
  attr :can_edit, :boolean, default: true
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
          target_types={~w(sheet flow map)}
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

      <%!-- Condition --%>
      <div class="pt-3 border-t border-base-300">
        <div class="flex items-center justify-between mb-1">
          <label class="text-xs font-medium text-base-content/60">
            {dgettext("scenes", "Condition")}
          </label>
          <select
            name="value"
            class="select select-xs w-20 text-xs"
            phx-change="update_zone_condition_effect"
            phx-value-id={@zone.id}
            disabled={!@can_edit}
          >
            <option value="hide" selected={(@zone.condition_effect || "hide") == "hide"}>
              {dgettext("scenes", "Hide")}
            </option>
            <option value="disable" selected={(@zone.condition_effect || "hide") == "disable"}>
              {dgettext("scenes", "Disable")}
            </option>
          </select>
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
  attr :project_scenes, :list, default: []
  attr :project_sheets, :list, default: []
  attr :project_flows, :list, default: []
  attr :project_variables, :list, default: []
  attr :panel_sections, :map, default: %{}

  defp pin_panel(assigns) do
    assigns =
      assigns
      |> assign(:action_types, @action_types)
      |> assign(:action_data, assigns.pin.action_data || %{})

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

      <%!-- Link to --%>
      <div class="pt-3 border-t border-base-300">
        <label class="block text-xs font-medium text-base-content/60 mb-1">
          {dgettext("scenes", "Link to")}
        </label>
        <.toolbar_target_picker
          id={"panel-pin-target-#{@pin.id}"}
          event="update_pin"
          element_id={@pin.id}
          current_type={@pin.target_type}
          current_target_id={@pin.target_id}
          target_types={~w(sheet flow map url)}
          project_scenes={@project_scenes}
          project_sheets={@project_sheets}
          project_flows={@project_flows}
          disabled={!@can_edit}
        />
      </div>

      <%!-- Action type --%>
      <div class="pt-3 border-t border-base-300">
        <label class="block text-xs font-medium text-base-content/60 mb-1">
          {dgettext("scenes", "Action")}
        </label>
        <div class="flex gap-1">
          <button
            :for={type <- @action_types}
            type="button"
            phx-click={
              JS.push("update_pin_action_type",
                value: %{"pin-id": @pin.id, "action-type": type}
              )
            }
            class={[
              "flex items-center gap-1 px-2 py-1 rounded text-xs cursor-pointer hover:bg-base-content/10",
              type == (@pin.action_type || "none") && "font-semibold text-primary bg-base-content/5"
            ]}
            disabled={!@can_edit}
          >
            <.icon name={action_type_icon(type)} class="size-3" />
            {action_type_label(type)}
          </button>
        </div>
      </div>

      <%!-- Instruction --%>
      <div :if={@pin.action_type == "instruction"} class="pt-3 border-t border-base-300">
        <label class="block text-xs font-medium text-base-content/60 mb-1">
          {dgettext("scenes", "Assignments")}
        </label>
        <.expression_editor
          id={"panel-pin-instruction-#{@pin.id}"}
          mode="instruction"
          assignments={@action_data["assignments"] || []}
          variables={@project_variables}
          can_edit={@can_edit}
          context={%{"pin-id" => @pin.id}}
          event_name="update_pin_assignments"
          active_tab={Map.get(@panel_sections, "tab_panel-pin-instruction-#{@pin.id}", "builder")}
        />
      </div>

      <%!-- Display --%>
      <div :if={@pin.action_type == "display"} class="pt-3 border-t border-base-300">
        <label class="block text-xs font-medium text-base-content/60 mb-1">
          {dgettext("scenes", "Variable")}
        </label>
        <.display_variable_picker
          id={"panel-pin-display-var-#{@pin.id}"}
          element_id={@pin.id}
          event="update_pin_action_data"
          context_key="pin-id"
          variables={@project_variables}
          selected_ref={@action_data["variable_ref"] || ""}
          can_edit={@can_edit}
        />
      </div>

      <%!-- Condition --%>
      <div class="pt-3 border-t border-base-300">
        <div class="flex items-center justify-between mb-1">
          <label class="text-xs font-medium text-base-content/60">
            {dgettext("scenes", "Condition")}
          </label>
          <select
            name="value"
            class="select select-xs w-20 text-xs"
            phx-change="update_pin_condition_effect"
            phx-value-id={@pin.id}
            disabled={!@can_edit}
          >
            <option value="hide" selected={(@pin.condition_effect || "hide") == "hide"}>
              {dgettext("scenes", "Hide")}
            </option>
            <option value="disable" selected={(@pin.condition_effect || "hide") == "disable"}>
              {dgettext("scenes", "Disable")}
            </option>
          </select>
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

  defp action_type_icon("none"), do: "circle-off"
  defp action_type_icon("instruction"), do: "zap"
  defp action_type_icon("display"), do: "bar-chart-3"
  defp action_type_icon(_), do: "circle-off"

  defp action_type_label("none"), do: dgettext("scenes", "None")
  defp action_type_label("instruction"), do: dgettext("scenes", "Action")
  defp action_type_label("display"), do: dgettext("scenes", "Display")
  defp action_type_label(_), do: dgettext("scenes", "None")
end

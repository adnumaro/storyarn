defmodule StoryarnWeb.MapLive.Components.FloatingToolbar do
  @moduledoc """
  FigJam-style floating toolbar positioned above the selected map element.

  Dispatches to per-type toolbars (zone, pin, connection, annotation).
  JS manages positioning; LiveView manages content and values.
  """

  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext

  alias Phoenix.LiveView.JS

  import StoryarnWeb.Components.CoreComponents
  import StoryarnWeb.MapLive.Components.ToolbarWidgets

  @pin_types ~w(location character event custom)

  # ---------------------------------------------------------------------------
  # Main dispatcher
  # ---------------------------------------------------------------------------

  attr :selected_type, :string, required: true
  attr :selected_element, :map, required: true
  attr :layers, :list, default: []
  attr :can_edit, :boolean, default: true
  attr :can_toggle_lock, :boolean, default: true
  attr :project_maps, :list, default: []
  attr :project_sheets, :list, default: []
  attr :project_flows, :list, default: []

  def floating_toolbar(assigns) do
    ~H"""
    <div class="floating-toolbar">
      <.zone_toolbar
        :if={@selected_type == "zone"}
        zone={@selected_element}
        layers={@layers}
        can_edit={@can_edit}
        can_toggle_lock={@can_toggle_lock}
        project_maps={@project_maps}
        project_sheets={@project_sheets}
        project_flows={@project_flows}
      />
      <.pin_toolbar
        :if={@selected_type == "pin"}
        pin={@selected_element}
        layers={@layers}
        can_edit={@can_edit}
        can_toggle_lock={@can_toggle_lock}
        project_maps={@project_maps}
        project_sheets={@project_sheets}
        project_flows={@project_flows}
      />
      <.connection_toolbar
        :if={@selected_type == "connection"}
        connection={@selected_element}
        can_edit={@can_edit}
      />
      <.annotation_toolbar
        :if={@selected_type == "annotation"}
        annotation={@selected_element}
        layers={@layers}
        can_edit={@can_edit}
        can_toggle_lock={@can_toggle_lock}
      />
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Zone Toolbar
  # [Name] | [Fill▾ (+opacity)] [Border▾] | [Layer▾] [Lock] | [… more]
  # ---------------------------------------------------------------------------

  attr :zone, :map, required: true
  attr :layers, :list, default: []
  attr :can_edit, :boolean, default: true
  attr :can_toggle_lock, :boolean, default: true
  attr :project_maps, :list, default: []
  attr :project_sheets, :list, default: []
  attr :project_flows, :list, default: []

  defp zone_toolbar(assigns) do
    ~H"""
    <div class="flex items-center gap-0.5">
      <%!-- Name --%>
      <input
        type="text"
        value={@zone.name || ""}
        phx-blur="update_zone"
        phx-value-id={@zone.id}
        phx-value-field="name"
        placeholder={dgettext("maps", "Name")}
        class="toolbar-input w-24"
        disabled={!@can_edit}
      />

      <span class="toolbar-separator" />

      <%!-- Fill color + opacity --%>
      <.toolbar_color_picker
        id={"zone-fill-#{@zone.id}"}
        event="update_zone"
        element_id={@zone.id}
        field="fill_color"
        value={@zone.fill_color || "#3b82f6"}
        label={dgettext("maps", "Fill Color")}
        disabled={!@can_edit}
      >
        <:extra_content>
          <.toolbar_opacity_slider
            event="update_zone"
            element_id={@zone.id}
            value={@zone.opacity || 0.3}
            disabled={!@can_edit}
          />
        </:extra_content>
      </.toolbar_color_picker>

      <%!-- Border --%>
      <.toolbar_stroke_picker
        id={"zone-border-#{@zone.id}"}
        event="update_zone"
        element_id={@zone.id}
        current_style={@zone.border_style || "solid"}
        current_color={@zone.border_color || "#1e40af"}
        current_width={@zone.border_width || 2}
        style_field="border_style"
        color_field="border_color"
        width_field="border_width"
        label={dgettext("maps", "Border")}
        disabled={!@can_edit}
      />

      <span class="toolbar-separator" />

      <%!-- Layer --%>
      <.toolbar_layer_picker
        id={"zone-layer-#{@zone.id}"}
        event="update_zone"
        element_id={@zone.id}
        current_layer_id={@zone.layer_id}
        layers={@layers}
        disabled={!@can_edit}
      />

      <%!-- Lock toggle --%>
      <.toolbar_lock_toggle element_id={@zone.id} event="update_zone" locked={@zone.locked} can_toggle_lock={@can_toggle_lock} />

      <span class="toolbar-separator" />

      <%!-- More (…) popover: tooltip + target --%>
      <div class="relative">
        <button
          type="button"
          class="toolbar-btn"
          title={dgettext("maps", "More")}
          phx-click={JS.toggle(to: "#popover-zone-more-#{@zone.id}", display: "block")}
        >
          <.icon name="more-horizontal" class="size-3.5" />
        </button>

        <div
          id={"popover-zone-more-#{@zone.id}"}
          class="toolbar-popover w-56"
          style="display:none"
          phx-click-away={JS.hide(to: "#popover-zone-more-#{@zone.id}")}
        >
          <div class="p-2 space-y-3">
            <%!-- Tooltip --%>
            <div>
              <label class="block text-xs font-medium text-base-content/60 mb-1">
                {dgettext("maps", "Tooltip")}
              </label>
              <input
                type="text"
                value={@zone.tooltip || ""}
                phx-blur="update_zone"
                phx-value-id={@zone.id}
                phx-value-field="tooltip"
                placeholder={dgettext("maps", "Hover text...")}
                class="input input-xs input-bordered w-full"
                disabled={!@can_edit}
              />
            </div>

            <%!-- Target link --%>
            <div class="pt-2 border-t border-base-300">
              <label class="text-xs font-medium text-base-content/60">
                {dgettext("maps", "Link to")}
              </label>
              <div class="mt-1">
                <.toolbar_target_picker
                  id={"zone-target-#{@zone.id}"}
                  event="update_zone"
                  element_id={@zone.id}
                  current_type={@zone.target_type}
                  current_target_id={@zone.target_id}
                  target_types={~w(sheet flow map)}
                  project_maps={@project_maps}
                  project_sheets={@project_sheets}
                  project_flows={@project_flows}
                  disabled={!@can_edit}
                />
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Pin Toolbar
  # [Label] | [Type▾] [Color▾] [Size S|M|L] | [Layer▾] [Lock] | [… more]
  # ---------------------------------------------------------------------------

  attr :pin, :map, required: true
  attr :layers, :list, default: []
  attr :can_edit, :boolean, default: true
  attr :can_toggle_lock, :boolean, default: true
  attr :project_maps, :list, default: []
  attr :project_sheets, :list, default: []
  attr :project_flows, :list, default: []

  defp pin_toolbar(assigns) do
    assigns = assign(assigns, :pin_types, @pin_types)

    ~H"""
    <div class="flex items-center gap-0.5">
      <%!-- Label --%>
      <input
        type="text"
        value={@pin.label || ""}
        phx-blur="update_pin"
        phx-value-id={@pin.id}
        phx-value-field="label"
        placeholder={dgettext("maps", "Label")}
        class="toolbar-input w-24"
        disabled={!@can_edit}
      />

      <span class="toolbar-separator" />

      <%!-- Type --%>
      <div class="relative">
        <button
          type="button"
          class="toolbar-btn gap-1 px-1.5"
          title={dgettext("maps", "Type")}
          disabled={!@can_edit}
          phx-click={JS.toggle(to: "#popover-pin-type-#{@pin.id}", display: "block")}
        >
          <.icon name={pin_type_icon(@pin.pin_type)} class="size-3.5" />
        </button>

        <div
          id={"popover-pin-type-#{@pin.id}"}
          class="toolbar-popover"
          style="display:none"
          phx-click-away={JS.hide(to: "#popover-pin-type-#{@pin.id}")}
        >
          <div class="p-1 min-w-[120px]">
            <button
              :for={value <- @pin_types}
              type="button"
              phx-click={
                JS.push("update_pin", value: %{id: @pin.id, field: "pin_type", value: value})
                |> JS.hide(to: "#popover-pin-type-#{@pin.id}")
              }
              class={"flex items-center gap-2 w-full px-2 py-1 rounded text-sm hover:bg-base-200 #{if value == @pin.pin_type, do: "font-semibold text-primary"}"}
              disabled={!@can_edit}
            >
              <.icon name={pin_type_icon(value)} class="size-3.5" />
              {pin_type_label(value)}
            </button>
          </div>
        </div>
      </div>

      <%!-- Color --%>
      <.toolbar_color_picker
        id={"pin-color-#{@pin.id}"}
        event="update_pin"
        element_id={@pin.id}
        field="color"
        value={@pin.color || "#3b82f6"}
        label={dgettext("maps", "Color")}
        disabled={!@can_edit}
      >
        <:extra_content>
          <.toolbar_opacity_slider
            event="update_pin"
            element_id={@pin.id}
            value={@pin.opacity || 1.0}
            disabled={!@can_edit}
          />
        </:extra_content>
      </.toolbar_color_picker>

      <%!-- Size --%>
      <.toolbar_size_picker
        event="update_pin"
        element_id={@pin.id}
        field="size"
        current={@pin.size || "md"}
        disabled={!@can_edit}
      />

      <span class="toolbar-separator" />

      <%!-- Layer --%>
      <.toolbar_layer_picker
        id={"pin-layer-#{@pin.id}"}
        event="update_pin"
        element_id={@pin.id}
        current_layer_id={@pin.layer_id}
        layers={@layers}
        disabled={!@can_edit}
      />

      <%!-- Lock toggle --%>
      <.toolbar_lock_toggle element_id={@pin.id} event="update_pin" locked={@pin.locked} can_toggle_lock={@can_toggle_lock} />

      <span class="toolbar-separator" />

      <%!-- More (…) --%>
      <div class="relative">
        <button
          type="button"
          class="toolbar-btn"
          title={dgettext("maps", "More")}
          phx-click={JS.toggle(to: "#popover-pin-more-#{@pin.id}", display: "block")}
        >
          <.icon name="more-horizontal" class="size-3.5" />
        </button>

        <div
          id={"popover-pin-more-#{@pin.id}"}
          class="toolbar-popover w-56"
          style="display:none"
          phx-click-away={JS.hide(to: "#popover-pin-more-#{@pin.id}")}
        >
          <div class="p-2 space-y-3">
            <%!-- Tooltip --%>
            <div>
              <label class="block text-xs font-medium text-base-content/60 mb-1">
                {dgettext("maps", "Tooltip")}
              </label>
              <input
                type="text"
                value={@pin.tooltip || ""}
                phx-blur="update_pin"
                phx-value-id={@pin.id}
                phx-value-field="tooltip"
                placeholder={dgettext("maps", "Hover text...")}
                class="input input-xs input-bordered w-full"
                disabled={!@can_edit}
              />
            </div>

            <%!-- Target link --%>
            <div class="pt-2 border-t border-base-300">
              <label class="text-xs font-medium text-base-content/60">
                {dgettext("maps", "Link to")}
              </label>
              <div class="mt-1">
                <.toolbar_target_picker
                  id={"pin-target-#{@pin.id}"}
                  event="update_pin"
                  element_id={@pin.id}
                  current_type={@pin.target_type}
                  current_target_id={@pin.target_id}
                  target_types={~w(sheet flow map url)}
                  project_maps={@project_maps}
                  project_sheets={@project_sheets}
                  project_flows={@project_flows}
                  disabled={!@can_edit}
                />
              </div>
            </div>

            <%!-- Custom icon --%>
            <div :if={@can_edit} class="pt-2 border-t border-base-300">
              <button
                type="button"
                phx-click="toggle_pin_icon_upload"
                class="btn btn-ghost btn-xs w-full"
              >
                <.icon name="image" class="size-3" />
                {dgettext("maps", "Change Icon")}
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Connection Toolbar
  # [Label] | [Style ···] [Color▾] | [Show Label] [Bidirectional] | [… more]
  # ---------------------------------------------------------------------------

  attr :connection, :map, required: true
  attr :can_edit, :boolean, default: true

  defp connection_toolbar(assigns) do
    ~H"""
    <div class="flex items-center gap-0.5">
      <%!-- Label --%>
      <input
        type="text"
        value={@connection.label || ""}
        phx-blur="update_connection"
        phx-value-id={@connection.id}
        phx-value-field="label"
        placeholder={dgettext("maps", "Label")}
        class="toolbar-input w-24"
        disabled={!@can_edit}
      />

      <span class="toolbar-separator" />

      <%!-- Line style + color + width --%>
      <.toolbar_stroke_picker
        id={"conn-line-#{@connection.id}"}
        event="update_connection"
        element_id={@connection.id}
        current_style={@connection.line_style || "solid"}
        current_color={@connection.color || "#6b7280"}
        current_width={@connection.line_width || 2}
        style_field="line_style"
        color_field="color"
        width_field="line_width"
        label={dgettext("maps", "Line style")}
        disabled={!@can_edit}
      />

      <span class="toolbar-separator" />

      <%!-- Show Label toggle --%>
      <button
        type="button"
        class={"toolbar-btn px-1.5 gap-1 #{if @connection.show_label, do: "toolbar-btn-active"}"}
        title={dgettext("maps", "Show Label")}
        phx-click={JS.push("update_connection", value: %{id: @connection.id, field: "show_label", toggle: to_string(!@connection.show_label)})}
        disabled={!@can_edit}
      >
        <.icon name="tag" class="size-3" />
      </button>

      <%!-- Bidirectional toggle --%>
      <button
        type="button"
        class={"toolbar-btn px-1.5 gap-1 #{if @connection.bidirectional, do: "toolbar-btn-active"}"}
        title={dgettext("maps", "Bidirectional")}
        phx-click={JS.push("update_connection", value: %{id: @connection.id, field: "bidirectional", toggle: to_string(!@connection.bidirectional)})}
        disabled={!@can_edit}
      >
        <.icon name="arrow-left-right" class="size-3" />
      </button>

      <span class="toolbar-separator" />

      <%!-- More (…) --%>
      <div class="relative">
        <button
          type="button"
          class="toolbar-btn"
          title={dgettext("maps", "More")}
          phx-click={JS.toggle(to: "#popover-conn-more-#{@connection.id}", display: "block")}
        >
          <.icon name="more-horizontal" class="size-3.5" />
        </button>

        <div
          id={"popover-conn-more-#{@connection.id}"}
          class="toolbar-popover"
          style="display:none"
          phx-click-away={JS.hide(to: "#popover-conn-more-#{@connection.id}")}
        >
          <div class="p-1 min-w-[140px]">
            <button
              :if={@can_edit && length(@connection.waypoints || []) > 0}
              type="button"
              phx-click={
                JS.push("clear_connection_waypoints", value: %{id: @connection.id})
                |> JS.hide(to: "#popover-conn-more-#{@connection.id}")
              }
              class="flex items-center gap-2 w-full px-2 py-1 rounded text-sm hover:bg-base-200"
            >
              <.icon name="undo-2" class="size-3" />
              {dgettext("maps", "Straighten path")}
            </button>
            <p :if={length(@connection.waypoints || []) == 0} class="px-2 py-1 text-xs text-base-content/40">
              {dgettext("maps", "No waypoints")}
            </p>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Annotation Toolbar
  # [Color▾] [Size S|M|L] | [Layer▾] [Lock]
  # ---------------------------------------------------------------------------

  attr :annotation, :map, required: true
  attr :layers, :list, default: []
  attr :can_edit, :boolean, default: true
  attr :can_toggle_lock, :boolean, default: true

  defp annotation_toolbar(assigns) do
    ~H"""
    <div class="flex items-center gap-0.5">
      <%!-- Color --%>
      <.toolbar_color_picker
        id={"ann-color-#{@annotation.id}"}
        event="update_annotation"
        element_id={@annotation.id}
        field="color"
        value={@annotation.color || "#fbbf24"}
        label={dgettext("maps", "Color")}
        disabled={!@can_edit}
      />

      <%!-- Size --%>
      <.toolbar_size_picker
        event="update_annotation"
        element_id={@annotation.id}
        field="font_size"
        current={@annotation.font_size || "md"}
        disabled={!@can_edit}
      />

      <span class="toolbar-separator" />

      <%!-- Layer --%>
      <.toolbar_layer_picker
        id={"ann-layer-#{@annotation.id}"}
        event="update_annotation"
        element_id={@annotation.id}
        current_layer_id={@annotation.layer_id}
        layers={@layers}
        disabled={!@can_edit}
      />

      <%!-- Lock toggle --%>
      <.toolbar_lock_toggle element_id={@annotation.id} event="update_annotation" locked={@annotation.locked} can_toggle_lock={@can_toggle_lock} />
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Lock toggle (shared by zone, pin, annotation toolbars)
  # ---------------------------------------------------------------------------

  attr :element_id, :any, required: true
  attr :event, :string, required: true
  attr :locked, :boolean, required: true
  attr :can_toggle_lock, :boolean, default: true

  defp toolbar_lock_toggle(assigns) do
    ~H"""
    <button
      :if={@can_toggle_lock}
      type="button"
      class="toolbar-btn"
      title={if @locked, do: dgettext("maps", "Unlock"), else: dgettext("maps", "Lock")}
      phx-click={JS.push(@event, value: %{id: @element_id, field: "locked", toggle: to_string(!@locked)})}
    >
      <.icon name={if @locked, do: "lock", else: "unlock"} class="size-3.5" />
    </button>
    """
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp pin_type_icon("location"), do: "map-pin"
  defp pin_type_icon("character"), do: "user"
  defp pin_type_icon("event"), do: "zap"
  defp pin_type_icon("custom"), do: "star"
  defp pin_type_icon(_), do: "map-pin"

  defp pin_type_label("location"), do: dgettext("maps", "Location")
  defp pin_type_label("character"), do: dgettext("maps", "Character")
  defp pin_type_label("event"), do: dgettext("maps", "Event")
  defp pin_type_label("custom"), do: dgettext("maps", "Custom")
  defp pin_type_label(other), do: other
end

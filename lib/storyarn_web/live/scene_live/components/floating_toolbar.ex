defmodule StoryarnWeb.SceneLive.Components.FloatingToolbar do
  @moduledoc """
  FigJam-style floating toolbar positioned above the selected map element.

  Dispatches to per-type toolbars (zone, pin, connection, annotation).
  JS manages positioning; LiveView manages content and values.
  Advanced properties (tooltip, link-to, conditions, actions) live in SceneElementPanel.
  """

  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext

  alias Phoenix.LiveView.JS

  import StoryarnWeb.Components.CoreComponents
  import StoryarnWeb.Components.ToolbarColorPicker
  import StoryarnWeb.SceneLive.Components.ToolbarWidgets

  @pin_types ~w(location character event custom)

  # ---------------------------------------------------------------------------
  # Main dispatcher
  # ---------------------------------------------------------------------------

  attr :selected_type, :string, required: true
  attr :selected_element, :map, required: true
  attr :layers, :list, default: []
  attr :can_edit, :boolean, default: true
  attr :can_toggle_lock, :boolean, default: true

  @doc "Renders the floating toolbar dispatching to the per-type toolbar variant."
  def floating_toolbar(assigns) do
    ~H"""
    <div class="flex items-center gap-0.5">
      <.zone_toolbar
        :if={@selected_type == "zone"}
        zone={@selected_element}
        layers={@layers}
        can_edit={@can_edit}
        can_toggle_lock={@can_toggle_lock}
      />
      <.pin_toolbar
        :if={@selected_type == "pin"}
        pin={@selected_element}
        layers={@layers}
        can_edit={@can_edit}
        can_toggle_lock={@can_toggle_lock}
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
  # [Action▾] [Name] | [Fill▾ (+opacity)] [Border▾] | [Layer▾] [Lock] | [⚙]
  # ---------------------------------------------------------------------------

  @action_types ~w(none instruction display)

  attr :zone, :map, required: true
  attr :layers, :list, default: []
  attr :can_edit, :boolean, default: true
  attr :can_toggle_lock, :boolean, default: true

  defp zone_toolbar(assigns) do
    assigns = assign(assigns, :action_types, @action_types)

    ~H"""
    <div class="flex items-center gap-0.5">
      <%!-- Action type selector --%>
      <div class="relative">
        <button
          type="button"
          class="toolbar-btn gap-1 px-1.5"
          title={dgettext("scenes", "Action type")}
          disabled={!@can_edit}
          phx-click={JS.toggle(to: "#popover-zone-action-#{@zone.id}", display: "block")}
        >
          <.icon name={action_type_icon(@zone.action_type)} class="size-3.5" />
          <span class="text-xs">{action_type_label(@zone.action_type)}</span>
          <.icon name="chevron-down" class="size-2.5 opacity-50" />
        </button>

        <div
          id={"popover-zone-action-#{@zone.id}"}
          class="toolbar-popover"
          style="display:none"
          phx-click-away={JS.hide(to: "#popover-zone-action-#{@zone.id}")}
        >
          <div class="p-1 min-w-[120px]">
            <button
              :for={type <- @action_types}
              type="button"
              phx-click={
                JS.push("update_zone_action_type",
                  value: %{"zone-id": @zone.id, "action-type": type}
                )
                |> JS.hide(to: "#popover-zone-action-#{@zone.id}")
              }
              class={"flex items-center gap-2 w-full px-2 py-1 rounded text-sm cursor-pointer hover:bg-base-content/10 #{if type == (@zone.action_type || "none"), do: "font-semibold text-primary"}"}
              disabled={!@can_edit}
            >
              <.icon name={action_type_icon(type)} class="size-3.5" />
              {action_type_label(type)}
            </button>
          </div>
        </div>
      </div>

      <span class="toolbar-separator" />

      <%!-- Name --%>
      <input
        type="text"
        value={@zone.name || ""}
        phx-blur="update_zone"
        phx-value-id={@zone.id}
        phx-value-field="name"
        placeholder={dgettext("scenes", "Name")}
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
        label={dgettext("scenes", "Fill Color")}
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
        label={dgettext("scenes", "Border")}
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
      <.toolbar_lock_toggle
        element_id={@zone.id}
        event="update_zone"
        locked={@zone.locked}
        can_toggle_lock={@can_toggle_lock}
      />

      <span class="toolbar-separator" />

      <%!-- Settings — opens element properties panel --%>
      <button
        type="button"
        class="toolbar-btn"
        title={dgettext("scenes", "Properties")}
        phx-click={JS.push("open_element_panel")}
      >
        <.icon name="settings" class="size-3.5" />
      </button>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Pin Toolbar
  # [Label] | [Type▾] [Color▾] [Size S|M|L] | [Layer▾] [Lock] | [⚙]
  # ---------------------------------------------------------------------------

  attr :pin, :map, required: true
  attr :layers, :list, default: []
  attr :can_edit, :boolean, default: true
  attr :can_toggle_lock, :boolean, default: true

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
        placeholder={dgettext("scenes", "Label")}
        class="toolbar-input w-24"
        disabled={!@can_edit}
      />

      <span class="toolbar-separator" />

      <%!-- Type --%>
      <div class="relative">
        <button
          type="button"
          class="toolbar-btn gap-1 px-1.5"
          title={dgettext("scenes", "Type")}
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
              class={"flex items-center gap-2 w-full px-2 py-1 rounded text-sm cursor-pointer hover:bg-base-content/10 #{if value == @pin.pin_type, do: "font-semibold text-primary"}"}
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
        label={dgettext("scenes", "Color")}
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
        id={"pin-size-#{@pin.id}"}
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
      <.toolbar_lock_toggle
        element_id={@pin.id}
        event="update_pin"
        locked={@pin.locked}
        can_toggle_lock={@can_toggle_lock}
      />

      <span class="toolbar-separator" />

      <%!-- Settings — opens element properties panel --%>
      <button
        type="button"
        class="toolbar-btn"
        title={dgettext("scenes", "Properties")}
        phx-click={JS.push("open_element_panel")}
      >
        <.icon name="settings" class="size-3.5" />
      </button>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Connection Toolbar
  # [Label] | [Style ···] [Color▾] | [Show Label] [Bidirectional] | [⚙]
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
        placeholder={dgettext("scenes", "Label")}
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
        label={dgettext("scenes", "Line style")}
        disabled={!@can_edit}
      />

      <span class="toolbar-separator" />

      <%!-- Show Label toggle --%>
      <button
        type="button"
        class={"toolbar-btn px-1.5 gap-1 #{if @connection.show_label, do: "toolbar-btn-active"}"}
        title={dgettext("scenes", "Show Label")}
        phx-click={
          JS.push("update_connection",
            value: %{
              id: @connection.id,
              field: "show_label",
              toggle: to_string(!@connection.show_label)
            }
          )
        }
        disabled={!@can_edit}
      >
        <.icon name="tag" class="size-3" />
      </button>

      <%!-- Bidirectional toggle --%>
      <button
        type="button"
        class={"toolbar-btn px-1.5 gap-1 #{if @connection.bidirectional, do: "toolbar-btn-active"}"}
        title={dgettext("scenes", "Bidirectional")}
        phx-click={
          JS.push("update_connection",
            value: %{
              id: @connection.id,
              field: "bidirectional",
              toggle: to_string(!@connection.bidirectional)
            }
          )
        }
        disabled={!@can_edit}
      >
        <.icon name="arrow-left-right" class="size-3" />
      </button>

      <span class="toolbar-separator" />

      <%!-- Settings — opens element properties panel --%>
      <button
        type="button"
        class="toolbar-btn"
        title={dgettext("scenes", "Properties")}
        phx-click={JS.push("open_element_panel")}
      >
        <.icon name="settings" class="size-3.5" />
      </button>
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
        label={dgettext("scenes", "Color")}
        disabled={!@can_edit}
      />

      <%!-- Size --%>
      <.toolbar_size_picker
        id={"ann-size-#{@annotation.id}"}
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
      <.toolbar_lock_toggle
        element_id={@annotation.id}
        event="update_annotation"
        locked={@annotation.locked}
        can_toggle_lock={@can_toggle_lock}
      />
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
      title={if @locked, do: dgettext("scenes", "Unlock"), else: dgettext("scenes", "Lock")}
      phx-click={
        JS.push(@event, value: %{id: @element_id, field: "locked", toggle: to_string(!@locked)})
      }
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

  defp pin_type_label("location"), do: dgettext("scenes", "Location")
  defp pin_type_label("character"), do: dgettext("scenes", "Character")
  defp pin_type_label("event"), do: dgettext("scenes", "Event")
  defp pin_type_label("custom"), do: dgettext("scenes", "Custom")
  defp pin_type_label(other), do: other

  defp action_type_icon("none"), do: "circle-off"
  defp action_type_icon("instruction"), do: "zap"
  defp action_type_icon("display"), do: "bar-chart-3"
  defp action_type_icon(_), do: "circle-off"

  defp action_type_label("none"), do: dgettext("scenes", "None")
  defp action_type_label("instruction"), do: dgettext("scenes", "Action")
  defp action_type_label("display"), do: dgettext("scenes", "Display")
  defp action_type_label(_), do: dgettext("scenes", "None")
end

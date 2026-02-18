defmodule StoryarnWeb.MapLive.Components.PropertiesPanel do
  @moduledoc """
  Properties panel components for the map canvas editor.
  Renders editable fields for pins, zones, and connections.

  Each `phx-change` input is wrapped in its own `<form>` so LiveView
  serializes only that single input (avoiding value collision when
  multiple inputs share `name="value"` in one form).
  `phx-blur` inputs do NOT need a form wrapper.
  """

  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext

  alias Phoenix.LiveView.JS

  import StoryarnWeb.Components.CoreComponents

  @pin_types ~w(location character event custom)
  @pin_sizes ~w(sm md lg)
  @border_styles ~w(solid dashed dotted)

  # ---------------------------------------------------------------------------
  # Pin properties
  # ---------------------------------------------------------------------------

  attr :pin, :map, required: true
  attr :layers, :list, default: []
  attr :can_edit, :boolean, default: false
  attr :can_toggle_lock, :boolean, default: false
  attr :project_maps, :list, default: []
  attr :project_sheets, :list, default: []
  attr :project_flows, :list, default: []
  attr :show_pin_icon_upload, :boolean, default: false
  attr :project, :map, default: nil
  attr :current_user, :map, default: nil

  def pin_properties(assigns) do
    assigns =
      assigns
      |> assign(:pin_types, @pin_types)
      |> assign(:pin_sizes, @pin_sizes)

    ~H"""
    <div class="space-y-4">
      <%!-- Lock toggle --%>
      <div :if={@can_toggle_lock} class="flex items-center justify-between pb-2 border-b border-base-300">
        <label class="label text-xs font-medium flex items-center gap-1.5">
          <.icon name={if @pin.locked, do: "lock", else: "unlock"} class="size-3.5" />
          {if @pin.locked, do: dgettext("maps", "Locked"), else: dgettext("maps", "Unlocked")}
        </label>
        <input
          type="checkbox"
          checked={@pin.locked}
          phx-click="update_pin"
          phx-value-id={@pin.id}
          phx-value-field="locked"
          phx-value-toggle={to_string(!@pin.locked)}
          class="toggle toggle-sm"
        />
      </div>

      <%!-- Label (phx-blur — no form needed) --%>
      <div>
        <label class="label text-xs font-medium">{dgettext("maps", "Label")}</label>
        <input
          type="text"
          value={@pin.label || ""}
          phx-blur="update_pin"
          phx-value-id={@pin.id}
          phx-value-field="label"
          class="input input-sm input-bordered w-full"
          disabled={!@can_edit}
        />
      </div>

      <%!-- Type --%>
      <div>
        <label class="label text-xs font-medium">{dgettext("maps", "Type")}</label>
        <form phx-change="update_pin" phx-submit="noop">
          <input type="hidden" name="element_id" value={@pin.id} />
          <input type="hidden" name="field" value="pin_type" />
          <select
            name="value"
            class="select select-sm select-bordered w-full"
            disabled={!@can_edit}
          >
            <option :for={t <- @pin_types} value={t} selected={t == @pin.pin_type}>
              {pin_type_label(t)}
            </option>
          </select>
        </form>
      </div>

      <%!-- Color --%>
      <div>
        <label class="label text-xs font-medium">{dgettext("maps", "Color")}</label>
        <form phx-change="update_pin" phx-submit="noop">
          <input type="hidden" name="element_id" value={@pin.id} />
          <input type="hidden" name="field" value="color" />
          <input
            type="color"
            value={@pin.color || "#3b82f6"}
            name="value"
            class="w-full h-8 rounded cursor-pointer"
            disabled={!@can_edit}
          />
        </form>
      </div>

      <%!-- Size --%>
      <div>
        <label class="label text-xs font-medium">{dgettext("maps", "Size")}</label>
        <form phx-change="update_pin" phx-submit="noop">
          <input type="hidden" name="element_id" value={@pin.id} />
          <input type="hidden" name="field" value="size" />
          <select
            name="value"
            class="select select-sm select-bordered w-full"
            disabled={!@can_edit}
          >
            <option :for={s <- @pin_sizes} value={s} selected={s == @pin.size}>
              {pin_size_label(s)}
            </option>
          </select>
        </form>
      </div>

      <%!-- Tooltip (phx-blur — no form needed) --%>
      <div>
        <label class="label text-xs font-medium">{dgettext("maps", "Tooltip")}</label>
        <input
          type="text"
          value={@pin.tooltip || ""}
          phx-blur="update_pin"
          phx-value-id={@pin.id}
          phx-value-field="tooltip"
          class="input input-sm input-bordered w-full"
          disabled={!@can_edit}
        />
      </div>

      <%!-- Layer --%>
      <div>
        <label class="label text-xs font-medium">{dgettext("maps", "Layer")}</label>
        <form phx-change="update_pin" phx-submit="noop">
          <input type="hidden" name="element_id" value={@pin.id} />
          <input type="hidden" name="field" value="layer_id" />
          <select
            name="value"
            class="select select-sm select-bordered w-full"
            disabled={!@can_edit}
          >
            <option value="" selected={is_nil(@pin.layer_id)}>
              {dgettext("maps", "None")}
            </option>
            <option :for={layer <- @layers} value={layer.id} selected={layer.id == @pin.layer_id}>
              {layer.name}
            </option>
          </select>
        </form>
      </div>

      <%!-- Custom Icon --%>
      <div :if={@can_edit} class="pt-2 border-t border-base-300 space-y-2">
        <label class="label text-xs font-medium">
          <.icon name="image" class="size-3 inline-block mr-1" />{dgettext("maps", "Custom Icon")}
        </label>

        <div :if={pin_icon_set?(@pin)} class="space-y-2">
          <div class="rounded border border-base-300 overflow-hidden bg-base-200 flex items-center justify-center p-2">
            <img
              src={pin_icon_url(@pin)}
              alt={dgettext("maps", "Pin icon")}
              class="max-h-16 max-w-16 object-contain"
            />
          </div>
          <div class="flex gap-2">
            <button
              type="button"
              phx-click="toggle_pin_icon_upload"
              class="btn btn-ghost btn-xs flex-1"
            >
              <.icon name="refresh-cw" class="size-3" />
              {dgettext("maps", "Change")}
            </button>
            <button
              type="button"
              phx-click="remove_pin_icon"
              class="btn btn-error btn-outline btn-xs flex-1"
            >
              <.icon name="trash-2" class="size-3" />
              {dgettext("maps", "Remove")}
            </button>
          </div>
        </div>

        <div :if={!pin_icon_set?(@pin)}>
          <button
            type="button"
            phx-click="toggle_pin_icon_upload"
            class="btn btn-ghost btn-xs w-full border border-dashed border-base-300"
          >
            <.icon name="image-plus" class="size-3.5" />
            {dgettext("maps", "Upload Icon")}
          </button>
        </div>

        <div :if={@show_pin_icon_upload && @project && @current_user}>
          <.live_component
            module={StoryarnWeb.Components.AssetUpload}
            id="pin-icon-upload"
            project={@project}
            current_user={@current_user}
            on_upload={fn asset -> send(self(), {:pin_icon_uploaded, asset}) end}
            accept={~w(image/jpeg image/png image/gif image/webp image/svg+xml)}
            max_entries={1}
            max_file_size={524_288}
          />
        </div>
      </div>

      <%!-- Target link --%>
      <.target_selector
        element_type="pin"
        element_id={@pin.id}
        target_type={@pin.target_type}
        target_id={@pin.target_id}
        can_edit={@can_edit}
        project_maps={@project_maps}
        project_sheets={@project_sheets}
        project_flows={@project_flows}
        target_types={~w(sheet flow map url)}
      />

      <%!-- Delete --%>
      <div :if={@can_edit} class="pt-2 border-t border-base-300">
        <button
          type="button"
          phx-click={JS.push("delete_pin", value: %{id: @pin.id})}
          class="btn btn-error btn-sm btn-outline w-full"
        >
          <.icon name="trash-2" class="size-4" />
          {dgettext("maps", "Delete Pin")}
        </button>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Zone properties
  # ---------------------------------------------------------------------------

  attr :zone, :map, required: true
  attr :layers, :list, default: []
  attr :can_edit, :boolean, default: false
  attr :can_toggle_lock, :boolean, default: false
  attr :project_maps, :list, default: []
  attr :project_sheets, :list, default: []
  attr :project_flows, :list, default: []

  def zone_properties(assigns) do
    assigns = assign(assigns, :border_styles, @border_styles)

    ~H"""
    <div class="space-y-4">
      <%!-- Lock toggle --%>
      <div :if={@can_toggle_lock} class="flex items-center justify-between pb-2 border-b border-base-300">
        <label class="label text-xs font-medium flex items-center gap-1.5">
          <.icon name={if @zone.locked, do: "lock", else: "unlock"} class="size-3.5" />
          {if @zone.locked, do: dgettext("maps", "Locked"), else: dgettext("maps", "Unlocked")}
        </label>
        <input
          type="checkbox"
          checked={@zone.locked}
          phx-click="update_zone"
          phx-value-id={@zone.id}
          phx-value-field="locked"
          phx-value-toggle={to_string(!@zone.locked)}
          class="toggle toggle-sm"
        />
      </div>

      <%!-- Name (phx-blur — no form needed) --%>
      <div>
        <label class="label text-xs font-medium">{dgettext("maps", "Name")}</label>
        <input
          type="text"
          value={@zone.name || ""}
          phx-blur="update_zone"
          phx-value-id={@zone.id}
          phx-value-field="name"
          class="input input-sm input-bordered w-full"
          disabled={!@can_edit}
        />
      </div>

      <%!-- Fill Color --%>
      <div>
        <label class="label text-xs font-medium">{dgettext("maps", "Fill Color")}</label>
        <form phx-change="update_zone" phx-submit="noop">
          <input type="hidden" name="element_id" value={@zone.id} />
          <input type="hidden" name="field" value="fill_color" />
          <input
            type="color"
            value={@zone.fill_color || "#3b82f6"}
            name="value"
            class="w-full h-8 rounded cursor-pointer"
            disabled={!@can_edit}
          />
        </form>
      </div>

      <%!-- Border Color --%>
      <div>
        <label class="label text-xs font-medium">{dgettext("maps", "Border Color")}</label>
        <form phx-change="update_zone" phx-submit="noop">
          <input type="hidden" name="element_id" value={@zone.id} />
          <input type="hidden" name="field" value="border_color" />
          <input
            type="color"
            value={@zone.border_color || "#1e40af"}
            name="value"
            class="w-full h-8 rounded cursor-pointer"
            disabled={!@can_edit}
          />
        </form>
      </div>

      <%!-- Opacity --%>
      <div>
        <label class="label text-xs font-medium">
          {dgettext("maps", "Opacity")}
          <span class="text-base-content/50 ml-1">{format_opacity(@zone.opacity)}</span>
        </label>
        <form phx-change="update_zone" phx-submit="noop">
          <input type="hidden" name="element_id" value={@zone.id} />
          <input type="hidden" name="field" value="opacity" />
          <input
            type="range"
            min="0"
            max="1"
            step="0.05"
            value={@zone.opacity || 0.3}
            name="value"
            class="range range-sm"
            disabled={!@can_edit}
          />
        </form>
      </div>

      <%!-- Border Style --%>
      <div>
        <label class="label text-xs font-medium">{dgettext("maps", "Border Style")}</label>
        <form phx-change="update_zone" phx-submit="noop">
          <input type="hidden" name="element_id" value={@zone.id} />
          <input type="hidden" name="field" value="border_style" />
          <select
            name="value"
            class="select select-sm select-bordered w-full"
            disabled={!@can_edit}
          >
            <option :for={s <- @border_styles} value={s} selected={s == @zone.border_style}>
              {border_style_label(s)}
            </option>
          </select>
        </form>
      </div>

      <%!-- Border Width --%>
      <div>
        <label class="label text-xs font-medium">{dgettext("maps", "Border Width")}</label>
        <form phx-change="update_zone" phx-submit="noop">
          <input type="hidden" name="element_id" value={@zone.id} />
          <input type="hidden" name="field" value="border_width" />
          <input
            type="number"
            min="0"
            max="10"
            value={@zone.border_width || 2}
            name="value"
            class="input input-sm input-bordered w-full"
            disabled={!@can_edit}
          />
        </form>
      </div>

      <%!-- Tooltip (phx-blur — no form needed) --%>
      <div>
        <label class="label text-xs font-medium">{dgettext("maps", "Tooltip")}</label>
        <input
          type="text"
          value={@zone.tooltip || ""}
          phx-blur="update_zone"
          phx-value-id={@zone.id}
          phx-value-field="tooltip"
          class="input input-sm input-bordered w-full"
          disabled={!@can_edit}
        />
      </div>

      <%!-- Layer --%>
      <div>
        <label class="label text-xs font-medium">{dgettext("maps", "Layer")}</label>
        <form phx-change="update_zone" phx-submit="noop">
          <input type="hidden" name="element_id" value={@zone.id} />
          <input type="hidden" name="field" value="layer_id" />
          <select
            name="value"
            class="select select-sm select-bordered w-full"
            disabled={!@can_edit}
          >
            <option value="" selected={is_nil(@zone.layer_id)}>
              {dgettext("maps", "None")}
            </option>
            <option :for={layer <- @layers} value={layer.id} selected={layer.id == @zone.layer_id}>
              {layer.name}
            </option>
          </select>
        </form>
      </div>

      <%!-- Target link --%>
      <.target_selector
        element_type="zone"
        element_id={@zone.id}
        target_type={@zone.target_type}
        target_id={@zone.target_id}
        can_edit={@can_edit}
        project_maps={@project_maps}
        project_sheets={@project_sheets}
        project_flows={@project_flows}
        target_types={~w(sheet flow map)}
      />

      <%!-- Delete --%>
      <div :if={@can_edit} class="pt-2 border-t border-base-300">
        <button
          type="button"
          phx-click={JS.push("delete_zone", value: %{id: @zone.id})}
          class="btn btn-error btn-sm btn-outline w-full"
        >
          <.icon name="trash-2" class="size-4" />
          {dgettext("maps", "Delete Zone")}
        </button>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Connection properties
  # ---------------------------------------------------------------------------

  @line_styles ~w(solid dashed dotted)

  attr :connection, :map, required: true
  attr :can_edit, :boolean, default: false

  def connection_properties(assigns) do
    assigns = assign(assigns, :line_styles, @line_styles)

    ~H"""
    <div class="space-y-4">
      <%!-- Label (phx-blur — no form needed) --%>
      <div>
        <label class="label text-xs font-medium">{dgettext("maps", "Label")}</label>
        <input
          type="text"
          value={@connection.label || ""}
          phx-blur="update_connection"
          phx-value-id={@connection.id}
          phx-value-field="label"
          class="input input-sm input-bordered w-full"
          disabled={!@can_edit}
        />
      </div>

      <%!-- Line Style --%>
      <div>
        <label class="label text-xs font-medium">{dgettext("maps", "Line Style")}</label>
        <form phx-change="update_connection" phx-submit="noop">
          <input type="hidden" name="element_id" value={@connection.id} />
          <input type="hidden" name="field" value="line_style" />
          <select
            name="value"
            class="select select-sm select-bordered w-full"
            disabled={!@can_edit}
          >
            <option :for={s <- @line_styles} value={s} selected={s == @connection.line_style}>
              {line_style_label(s)}
            </option>
          </select>
        </form>
      </div>

      <%!-- Color --%>
      <div>
        <label class="label text-xs font-medium">{dgettext("maps", "Color")}</label>
        <form phx-change="update_connection" phx-submit="noop">
          <input type="hidden" name="element_id" value={@connection.id} />
          <input type="hidden" name="field" value="color" />
          <input
            type="color"
            value={@connection.color || "#6b7280"}
            name="value"
            class="w-full h-8 rounded cursor-pointer"
            disabled={!@can_edit}
          />
        </form>
      </div>

      <%!-- Bidirectional (phx-click — no form needed) --%>
      <div class="flex items-center justify-between">
        <label class="label text-xs font-medium">{dgettext("maps", "Bidirectional")}</label>
        <input
          type="checkbox"
          checked={@connection.bidirectional}
          phx-click="update_connection"
          phx-value-id={@connection.id}
          phx-value-field="bidirectional"
          phx-value-toggle={to_string(!@connection.bidirectional)}
          class="toggle toggle-sm"
          disabled={!@can_edit}
        />
      </div>

      <%!-- Waypoints --%>
      <div>
        <label class="label text-xs font-medium">{dgettext("maps", "Path")}</label>
        <div class="flex items-center justify-between">
          <span class="text-xs text-base-content/60">
            {dngettext("maps", "%{count} waypoint", "%{count} waypoints", length(@connection.waypoints || []),
              count: length(@connection.waypoints || []))}
          </span>
          <button
            :if={@can_edit && (@connection.waypoints || []) != []}
            type="button"
            phx-click="clear_connection_waypoints"
            phx-value-id={@connection.id}
            class="btn btn-ghost btn-xs"
          >
            <.icon name="undo-2" class="size-3" />
            {dgettext("maps", "Straighten")}
          </button>
        </div>
        <p :if={@can_edit} class="text-xs text-base-content/40 mt-1">
          {dgettext("maps", "Double-click the line to add waypoints.")}
        </p>
      </div>

      <%!-- Delete --%>
      <div :if={@can_edit} class="pt-2 border-t border-base-300">
        <button
          type="button"
          phx-click={JS.push("delete_connection", value: %{id: @connection.id})}
          class="btn btn-error btn-sm btn-outline w-full"
        >
          <.icon name="trash-2" class="size-4" />
          {dgettext("maps", "Delete Connection")}
        </button>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Annotation properties
  # ---------------------------------------------------------------------------

  @annotation_font_sizes ~w(sm md lg)

  attr :annotation, :map, required: true
  attr :layers, :list, default: []
  attr :can_edit, :boolean, default: false
  attr :can_toggle_lock, :boolean, default: false

  def annotation_properties(assigns) do
    assigns = assign(assigns, :font_sizes, @annotation_font_sizes)

    ~H"""
    <div class="space-y-4">
      <%!-- Lock toggle --%>
      <div :if={@can_toggle_lock} class="flex items-center justify-between pb-2 border-b border-base-300">
        <label class="label text-xs font-medium flex items-center gap-1.5">
          <.icon name={if @annotation.locked, do: "lock", else: "unlock"} class="size-3.5" />
          {if @annotation.locked, do: dgettext("maps", "Locked"), else: dgettext("maps", "Unlocked")}
        </label>
        <input
          type="checkbox"
          checked={@annotation.locked}
          phx-click="update_annotation"
          phx-value-id={@annotation.id}
          phx-value-field="locked"
          phx-value-toggle={to_string(!@annotation.locked)}
          class="toggle toggle-sm"
        />
      </div>

      <%!-- Text (phx-blur — no form needed) --%>
      <div>
        <label class="label text-xs font-medium">{dgettext("maps", "Text")}</label>
        <textarea
          phx-blur="update_annotation"
          phx-value-id={@annotation.id}
          phx-value-field="text"
          name="value"
          class="textarea textarea-sm textarea-bordered w-full"
          rows="3"
          disabled={!@can_edit}
        >{@annotation.text || ""}</textarea>
      </div>

      <%!-- Font Size --%>
      <div>
        <label class="label text-xs font-medium">{dgettext("maps", "Font Size")}</label>
        <form phx-change="update_annotation" phx-submit="noop">
          <input type="hidden" name="element_id" value={@annotation.id} />
          <input type="hidden" name="field" value="font_size" />
          <select
            name="value"
            class="select select-sm select-bordered w-full"
            disabled={!@can_edit}
          >
            <option :for={s <- @font_sizes} value={s} selected={s == @annotation.font_size}>
              {font_size_label(s)}
            </option>
          </select>
        </form>
      </div>

      <%!-- Color --%>
      <div>
        <label class="label text-xs font-medium">{dgettext("maps", "Color")}</label>
        <form phx-change="update_annotation" phx-submit="noop">
          <input type="hidden" name="element_id" value={@annotation.id} />
          <input type="hidden" name="field" value="color" />
          <input
            type="color"
            value={@annotation.color || "#fbbf24"}
            name="value"
            class="w-full h-8 rounded cursor-pointer"
            disabled={!@can_edit}
          />
        </form>
      </div>

      <%!-- Layer --%>
      <div>
        <label class="label text-xs font-medium">{dgettext("maps", "Layer")}</label>
        <form phx-change="update_annotation" phx-submit="noop">
          <input type="hidden" name="element_id" value={@annotation.id} />
          <input type="hidden" name="field" value="layer_id" />
          <select
            name="value"
            class="select select-sm select-bordered w-full"
            disabled={!@can_edit}
          >
            <option value="" selected={is_nil(@annotation.layer_id)}>
              {dgettext("maps", "None")}
            </option>
            <option :for={layer <- @layers} value={layer.id} selected={layer.id == @annotation.layer_id}>
              {layer.name}
            </option>
          </select>
        </form>
      </div>

      <%!-- Delete --%>
      <div :if={@can_edit} class="pt-2 border-t border-base-300">
        <button
          type="button"
          phx-click={JS.push("delete_annotation", value: %{id: @annotation.id})}
          class="btn btn-error btn-sm btn-outline w-full"
        >
          <.icon name="trash-2" class="size-4" />
          {dgettext("maps", "Delete Annotation")}
        </button>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Target selector (shared between pin and zone properties)
  # ---------------------------------------------------------------------------

  attr :element_type, :string, required: true
  attr :element_id, :any, required: true
  attr :target_type, :string, default: nil
  attr :target_id, :any, default: nil
  attr :can_edit, :boolean, default: false
  attr :project_maps, :list, default: []
  attr :project_sheets, :list, default: []
  attr :project_flows, :list, default: []
  attr :target_types, :list, default: ~w(sheet flow map)

  defp target_selector(assigns) do
    update_event = "update_#{assigns.element_type}"
    assigns = assign(assigns, :update_event, update_event)

    ~H"""
    <div class="pt-2 border-t border-base-300 space-y-2">
      <label class="label text-xs font-medium">
        <.icon name="link" class="size-3 inline-block mr-1" />{dgettext("maps", "Link to")}
      </label>

      <%!-- Target type select --%>
      <form phx-change={@update_event} phx-submit="noop">
        <input type="hidden" name="element_id" value={@element_id} />
        <input type="hidden" name="field" value="target_type" />
        <select
          name="value"
          class="select select-sm select-bordered w-full"
          disabled={!@can_edit}
        >
          <option value="" selected={is_nil(@target_type)}>{dgettext("maps", "None")}</option>
          <option :for={t <- @target_types} value={t} selected={t == @target_type}>
            {target_type_label(t)}
          </option>
        </select>
      </form>

      <%!-- Target ID select (shown when type is selected) --%>
      <form :if={@target_type in ~w(sheet flow map)} phx-change={@update_event} phx-submit="noop">
        <input type="hidden" name="element_id" value={@element_id} />
        <input type="hidden" name="field" value="target_id" />
        <select
          name="value"
          class="select select-sm select-bordered w-full"
          disabled={!@can_edit}
        >
          <option value="" selected={is_nil(@target_id)}>{dgettext("maps", "Select...")}</option>
          <option
            :for={item <- target_items(@target_type, @project_maps, @project_sheets, @project_flows)}
            value={item.id}
            selected={item.id == @target_id}
          >
            {item.name}
          </option>
        </select>
      </form>

      <%!-- URL input (for pins with target_type=url — phx-blur, no form needed) --%>
      <input
        :if={@target_type == "url"}
        type="url"
        value={@target_id || ""}
        phx-blur={@update_event}
        phx-value-id={@element_id}
        phx-value-field="target_id"
        placeholder="https://..."
        class="input input-sm input-bordered w-full"
        disabled={!@can_edit}
      />
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Map properties (background upload)
  # ---------------------------------------------------------------------------

  attr :map, :map, required: true
  attr :show_background_upload, :boolean, default: false
  attr :project, :map, required: true
  attr :current_user, :map, required: true

  def map_properties(assigns) do
    ~H"""
    <div class="space-y-4">
      <%!-- Background image --%>
      <div>
        <label class="label text-xs font-medium">{dgettext("maps", "Background Image")}</label>

        <div :if={background_set?(@map)} class="space-y-2">
          <div class="rounded border border-base-300 overflow-hidden">
            <img
              src={background_asset_url(@map)}
              alt={dgettext("maps", "Map background")}
              class="w-full h-32 object-cover"
            />
          </div>
          <div class="flex gap-2">
            <button
              type="button"
              phx-click="toggle_background_upload"
              class="btn btn-ghost btn-xs flex-1"
            >
              <.icon name="refresh-cw" class="size-3" />
              {dgettext("maps", "Change")}
            </button>
            <button
              type="button"
              phx-click="remove_background"
              class="btn btn-error btn-outline btn-xs flex-1"
            >
              <.icon name="trash-2" class="size-3" />
              {dgettext("maps", "Remove")}
            </button>
          </div>
        </div>

        <div :if={!background_set?(@map)}>
          <button
            type="button"
            phx-click="toggle_background_upload"
            class="btn btn-ghost btn-sm w-full border border-dashed border-base-300"
          >
            <.icon name="image-plus" class="size-4" />
            {dgettext("maps", "Upload Background")}
          </button>
        </div>
      </div>

      <%!-- Upload component --%>
      <div :if={@show_background_upload}>
        <.live_component
          module={StoryarnWeb.Components.AssetUpload}
          id="background-upload"
          project={@project}
          current_user={@current_user}
          on_upload={fn asset -> send(self(), {:background_uploaded, asset}) end}
          accept={~w(image/jpeg image/png image/gif image/webp)}
          max_entries={1}
        />
      </div>

      <%!-- Map scale --%>
      <div class="pt-2 border-t border-base-300 space-y-2">
        <label class="label text-xs font-medium">
          <.icon name="ruler" class="size-3 inline-block mr-1" />{dgettext("maps", "Map Scale")}
        </label>
        <div class="grid grid-cols-2 gap-2">
          <div>
            <label class="text-xs text-base-content/50">{dgettext("maps", "Total width")}</label>
            <input
              type="number"
              min="0"
              step="any"
              value={@map.scale_value || ""}
              phx-blur="update_map_scale"
              phx-value-field="scale_value"
              placeholder="500"
              class="input input-xs input-bordered w-full"
            />
          </div>
          <div>
            <label class="text-xs text-base-content/50">{dgettext("maps", "Unit")}</label>
            <input
              type="text"
              value={@map.scale_unit || ""}
              phx-blur="update_map_scale"
              phx-value-field="scale_unit"
              placeholder="km"
              class="input input-xs input-bordered w-full"
            />
          </div>
        </div>
        <p :if={@map.scale_value && @map.scale_unit} class="text-xs text-base-content/40">
          {dgettext("maps", "1 map width = %{value} %{unit}",
            value: format_scale_value(@map.scale_value),
            unit: @map.scale_unit
          )}
        </p>
      </div>

      <%!-- Map dimensions (read-only info) --%>
      <div class="pt-2 border-t border-base-300">
        <label class="label text-xs font-medium text-base-content/60">{dgettext("maps", "Dimensions")}</label>
        <p class="text-xs text-base-content/50">
          {(@map.width || 1000)} &times; {(@map.height || 1000)} px
        </p>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp background_set?(%{background_asset_id: id}) when not is_nil(id), do: true
  defp background_set?(_), do: false

  defp background_asset_url(%{background_asset: %{url: url}}) when is_binary(url), do: url
  defp background_asset_url(_), do: nil

  defp pin_icon_set?(%{icon_asset_id: id}) when not is_nil(id), do: true
  defp pin_icon_set?(_), do: false

  defp pin_icon_url(%{icon_asset: %{url: url}}) when is_binary(url), do: url
  defp pin_icon_url(_), do: nil

  defp pin_type_label("location"), do: dgettext("maps", "Location")
  defp pin_type_label("character"), do: dgettext("maps", "Character")
  defp pin_type_label("event"), do: dgettext("maps", "Event")
  defp pin_type_label("custom"), do: dgettext("maps", "Custom")
  defp pin_type_label(other), do: other

  defp pin_size_label("sm"), do: dgettext("maps", "Small")
  defp pin_size_label("md"), do: dgettext("maps", "Medium")
  defp pin_size_label("lg"), do: dgettext("maps", "Large")
  defp pin_size_label(other), do: other

  defp border_style_label(style), do: style_label(style)
  defp line_style_label(style), do: style_label(style)

  defp style_label("solid"), do: dgettext("maps", "Solid")
  defp style_label("dashed"), do: dgettext("maps", "Dashed")
  defp style_label("dotted"), do: dgettext("maps", "Dotted")
  defp style_label(other), do: other

  defp font_size_label("sm"), do: dgettext("maps", "Small")
  defp font_size_label("md"), do: dgettext("maps", "Medium")
  defp font_size_label("lg"), do: dgettext("maps", "Large")
  defp font_size_label(other), do: other

  defp format_opacity(nil), do: "30%"
  defp format_opacity(val), do: "#{round(val * 100)}%"

  defp target_type_label("sheet"), do: dgettext("maps", "Sheet")
  defp target_type_label("flow"), do: dgettext("maps", "Flow")
  defp target_type_label("map"), do: dgettext("maps", "Map")
  defp target_type_label("url"), do: dgettext("maps", "URL")
  defp target_type_label(other), do: other

  defp target_items("map", maps, _sheets, _flows), do: maps
  defp target_items("sheet", _maps, sheets, _flows), do: flatten_sheets(sheets)
  defp target_items("flow", _maps, _sheets, flows), do: flows
  defp target_items(_, _, _, _), do: []

  defp flatten_sheets(sheets) do
    Enum.flat_map(sheets, fn sheet ->
      [sheet | flatten_sheets(Map.get(sheet, :children, []))]
    end)
  end

  defp format_scale_value(val) when is_float(val) do
    if val == Float.floor(val), do: trunc(val) |> to_string(), else: to_string(val)
  end

  defp format_scale_value(val), do: to_string(val)
end

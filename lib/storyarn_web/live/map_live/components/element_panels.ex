defmodule StoryarnWeb.MapLive.Components.ElementPanels do
  @moduledoc """
  Properties panel components for connections and annotations on the map canvas.
  """

  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext

  alias Phoenix.LiveView.JS

  import StoryarnWeb.Components.CoreComponents

  @line_styles ~w(solid dashed dotted)
  @annotation_font_sizes ~w(sm md lg)

  # ---------------------------------------------------------------------------
  # Connection properties
  # ---------------------------------------------------------------------------

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
  # Private helpers (only used by connection_properties and annotation_properties)
  # ---------------------------------------------------------------------------

  defp line_style_label(style), do: style_label(style)

  defp font_size_label("sm"), do: dgettext("maps", "Small")
  defp font_size_label("md"), do: dgettext("maps", "Medium")
  defp font_size_label("lg"), do: dgettext("maps", "Large")
  defp font_size_label(other), do: other

  defp style_label("solid"), do: dgettext("maps", "Solid")
  defp style_label("dashed"), do: dgettext("maps", "Dashed")
  defp style_label("dotted"), do: dgettext("maps", "Dotted")
  defp style_label(other), do: other
end

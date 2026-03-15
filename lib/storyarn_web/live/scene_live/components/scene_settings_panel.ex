defmodule StoryarnWeb.SceneLive.Components.SceneSettingsPanel do
  @moduledoc """
  Right sidebar panel for scene settings (background image, scale, dimensions).
  Uses the same SceneElementPanel hook for slide-in/out animations.
  """

  use StoryarnWeb, :html
  use Gettext, backend: StoryarnWeb.Gettext

  alias Phoenix.LiveView.JS

  attr :scene, :map, required: true
  attr :can_edit, :boolean, required: true
  attr :bg_upload_input_id, :string, default: nil
  attr :ambient_flows, :list, default: []
  attr :project_flows, :list, default: []

  def scene_settings_panel(assigns) do
    ~H"""
    <div class="flex items-center justify-between p-4 border-b border-base-300 shrink-0">
      <h3 class="font-semibold text-sm">{dgettext("scenes", "Scene Settings")}</h3>
      <button
        type="button"
        class="btn btn-ghost btn-xs btn-square"
        phx-click={JS.dispatch("panel:close", to: "#scene-settings-panel")}
      >
        <.icon name="x" class="size-3.5" />
      </button>
    </div>
    <div class="p-4 overflow-y-auto flex-1 space-y-4">
      <%!-- Background image --%>
      <div>
        <label class="label text-xs font-medium">
          {dgettext("scenes", "Background Image")}
        </label>
        <div :if={background_set?(@scene)} class="space-y-2">
          <div class="rounded border border-base-300 overflow-hidden">
            <img
              src={background_asset_url(@scene)}
              alt={dgettext("scenes", "Scene background")}
              class="w-full h-32 object-cover"
            />
          </div>
          <div class="flex gap-2">
            <button
              :if={@bg_upload_input_id}
              type="button"
              phx-click={JS.dispatch("click", to: "#bg-upload-form input[type=file]")}
              class="btn btn-ghost btn-xs flex-1"
            >
              <.icon name="refresh-cw" class="size-3" />
              {dgettext("scenes", "Change")}
            </button>
            <button
              type="button"
              phx-click="remove_background"
              class="btn btn-error btn-outline btn-xs flex-1"
            >
              <.icon name="trash-2" class="size-3" />
              {dgettext("scenes", "Remove")}
            </button>
          </div>
        </div>
        <button
          :if={!background_set?(@scene) && @bg_upload_input_id}
          type="button"
          phx-click={JS.dispatch("click", to: "#bg-upload-form input[type=file]")}
          class="btn btn-ghost btn-sm w-full border border-dashed border-base-300"
        >
          <.icon name="image-plus" class="size-4" />
          {dgettext("scenes", "Upload Background")}
        </button>
      </div>
      <%!-- Exploration display mode --%>
      <div class="pt-2 border-t border-base-300 space-y-2">
        <label class="label text-xs font-medium">
          <.icon name="monitor" class="size-3 inline-block mr-1" />
          {dgettext("scenes", "Exploration Display")}
        </label>
        <div class="flex gap-1">
          <button
            type="button"
            class={[
              "btn btn-xs flex-1",
              if(@scene.exploration_display_mode != "scaled",
                do: "btn-primary",
                else: "btn-ghost"
              )
            ]}
            phx-click="update_exploration_display_mode"
            phx-value-mode="fit"
          >
            <.icon name="maximize" class="size-3" />
            {dgettext("scenes", "Fit")}
          </button>
          <button
            type="button"
            class={[
              "btn btn-xs flex-1",
              if(@scene.exploration_display_mode == "scaled",
                do: "btn-primary",
                else: "btn-ghost"
              )
            ]}
            phx-click="update_exploration_display_mode"
            phx-value-mode="scaled"
          >
            <.icon name="scan" class="size-3" />
            {dgettext("scenes", "Scaled")}
          </button>
        </div>
        <p class="text-xs text-base-content/40">
          <%= if @scene.exploration_display_mode == "scaled" do %>
            {dgettext("scenes", "Renders at native pixel size with CRPG-style camera scrolling.")}
          <% else %>
            {dgettext("scenes", "Scales to fit the viewport.")}
          <% end %>
        </p>
        <div :if={@scene.exploration_display_mode == "scaled"} class="flex items-center gap-2 pt-1">
          <label class="text-xs text-base-content/60 whitespace-nowrap">
            {dgettext("scenes", "Zoom")}
          </label>
          <input
            type="number"
            min="0.5"
            max="10"
            step="0.5"
            value={@scene.default_zoom || 1.0}
            phx-blur="update_scene_scale"
            phx-value-field="default_zoom"
            name="value"
            class="input input-xs flex-1"
            disabled={!@can_edit}
          />
          <span class="text-xs text-base-content/40">×</span>
        </div>
      </div>
      <%!-- Map scale --%>
      <div class="pt-2 border-t border-base-300 space-y-2">
        <label class="label text-xs font-medium">
          <.icon name="ruler" class="size-3 inline-block mr-1" />
          {dgettext("scenes", "Scene Scale")}
        </label>
        <div class="grid grid-cols-2 gap-2">
          <div>
            <label class="text-xs text-base-content/50">
              {dgettext("scenes", "Total width")}
            </label>
            <input
              type="number"
              min="0"
              step="any"
              value={@scene.scale_value || ""}
              phx-blur="update_scene_scale"
              phx-value-field="scale_value"
              placeholder="500"
              class="input input-xs input-bordered w-full"
            />
          </div>
          <div>
            <label class="text-xs text-base-content/50">{dgettext("scenes", "Unit")}</label>
            <input
              type="text"
              value={(@scene.scale_value && @scene.scale_unit) || ""}
              phx-blur="update_scene_scale"
              phx-value-field="scale_unit"
              placeholder="km"
              class="input input-xs input-bordered w-full"
            />
          </div>
        </div>
        <p :if={@scene.scale_value && @scene.scale_unit} class="text-xs text-base-content/40">
          {dgettext("scenes", "1 scene width = %{value} %{unit}",
            value: format_scale_value(@scene.scale_value),
            unit: @scene.scale_unit
          )}
        </p>
      </div>
      <%!-- Map dimensions (read-only) --%>
      <div class="pt-2 border-t border-base-300">
        <label class="label text-xs font-medium text-base-content/60">
          {dgettext("scenes", "Dimensions")}
        </label>
        <p class="text-xs text-base-content/50">
          {@scene.width || 1000} &times; {@scene.height || 1000} px
        </p>
      </div>
      <%!-- Ambient Flows --%>
      <div class="pt-2 border-t border-base-300 space-y-2">
        <label class="label text-xs font-medium">
          <.icon name="wind" class="size-3 inline-block mr-1" />
          {dgettext("scenes", "Ambient Flows")}
        </label>
        <div :if={@ambient_flows == []} class="text-xs text-base-content/40">
          {dgettext("scenes", "No ambient flows linked to this scene.")}
        </div>
        <div :for={af <- @ambient_flows} class="flex items-center gap-1.5 group">
          <span class="text-xs truncate flex-1" title={af.flow.name}>
            <.icon name="git-branch" class="size-3 inline-block mr-0.5 opacity-50" />
            {af.flow.name}
          </span>
          <div :if={@can_edit} class="flex items-center gap-0.5 shrink-0">
            <button
              type="button"
              class="btn btn-ghost btn-xs btn-square opacity-0 group-hover:opacity-100"
              phx-click="reorder_ambient_flow"
              phx-value-id={af.id}
              phx-value-direction="up"
              title={dgettext("scenes", "Move up")}
            >
              <.icon name="chevron-up" class="size-3" />
            </button>
            <button
              type="button"
              class="btn btn-ghost btn-xs btn-square opacity-0 group-hover:opacity-100"
              phx-click="reorder_ambient_flow"
              phx-value-id={af.id}
              phx-value-direction="down"
              title={dgettext("scenes", "Move down")}
            >
              <.icon name="chevron-down" class="size-3" />
            </button>
            <label class="swap swap-rotate">
              <input
                type="checkbox"
                checked={af.enabled}
                phx-click="toggle_ambient_flow"
                phx-value-id={af.id}
              />
              <.icon name="eye" class="swap-on size-3.5 text-success" />
              <.icon name="eye-off" class="swap-off size-3.5 text-base-content/30" />
            </label>
            <button
              type="button"
              class="btn btn-ghost btn-xs btn-square text-error opacity-0 group-hover:opacity-100"
              phx-click="remove_ambient_flow"
              phx-value-id={af.id}
            >
              <.icon name="x" class="size-3" />
            </button>
          </div>
        </div>
        <% available_flows = available_flows(@project_flows, @ambient_flows) %>
        <div :if={@can_edit && available_flows != []}>
          <select
            class="select select-xs select-bordered w-full"
            phx-change="add_ambient_flow"
            name="flow_id"
          >
            <option value="">{dgettext("scenes", "+ Add ambient flow…")}</option>
            <option :for={flow <- available_flows} value={flow.id}>
              {flow.name}
            </option>
          </select>
        </div>
      </div>
    </div>
    """
  end

  defp background_set?(%{background_asset_id: id}) when not is_nil(id), do: true
  defp background_set?(_), do: false

  defp background_asset_url(%{background_asset: %{url: url}}) when is_binary(url), do: url
  defp background_asset_url(_), do: nil

  defp format_scale_value(val) when is_float(val) do
    if val == Float.floor(val), do: trunc(val) |> to_string(), else: to_string(val)
  end

  defp format_scale_value(val), do: to_string(val)

  defp available_flows(project_flows, ambient_flows) do
    linked_ids = MapSet.new(ambient_flows, & &1.flow_id)
    Enum.reject(project_flows, &MapSet.member?(linked_ids, &1.id))
  end
end

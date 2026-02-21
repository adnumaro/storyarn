defmodule StoryarnWeb.MapLive.Components.MapPanel do
  @moduledoc """
  Map-level properties panel component.
  Renders editable fields for the map itself (background image, scale).
  """

  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext

  import StoryarnWeb.Components.CoreComponents

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
        <label class="label text-xs font-medium text-base-content/60">
          {dgettext("maps", "Dimensions")}
        </label>
        <p class="text-xs text-base-content/50">
          {@map.width || 1000} &times; {@map.height || 1000} px
        </p>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Private helpers (only used by map_properties)
  # ---------------------------------------------------------------------------

  defp background_set?(%{background_asset_id: id}) when not is_nil(id), do: true
  defp background_set?(_), do: false

  defp background_asset_url(%{background_asset: %{url: url}}) when is_binary(url), do: url
  defp background_asset_url(_), do: nil

  defp format_scale_value(val) when is_float(val) do
    if val == Float.floor(val), do: trunc(val) |> to_string(), else: to_string(val)
  end

  defp format_scale_value(val), do: to_string(val)
end

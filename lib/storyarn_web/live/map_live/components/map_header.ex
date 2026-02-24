defmodule StoryarnWeb.MapLive.Components.MapHeader do
  @moduledoc """
  Header bar component for the map editor.

  Displays breadcrumbs + map name (floating below toolbars) and action buttons
  (export, settings, edit/view toggle) at the same level as layout toolbars.
  """

  use Phoenix.Component
  use StoryarnWeb, :verified_routes
  use Gettext, backend: StoryarnWeb.Gettext

  import StoryarnWeb.Components.CoreComponents

  @doc "Actions toolbar (export, settings, play, edit/view toggle) — fixed top-right."
  attr :can_edit, :boolean, required: true
  attr :edit_mode, :boolean, required: true
  attr :workspace, :map, required: true
  attr :project, :map, required: true
  attr :map, :map, required: true
  attr :bg_upload_input_id, :string, default: nil, doc: "ID of the hidden background file input"

  def map_actions(assigns) do
    ~H"""
    <div class="flex items-center gap-1 px-1.5 py-1 bg-base-200/95 backdrop-blur border border-base-300 rounded-xl shadow-lg">
      <%!-- Play / Explore button --%>
      <.link
        navigate={
          ~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/maps/#{@map.id}/explore"
        }
        class="btn btn-ghost btn-sm gap-1.5"
        title={dgettext("maps", "Play exploration mode")}
      >
        <.icon name="play" class="size-3.5" />
        <span class="hidden xl:inline">{dgettext("maps", "Play")}</span>
      </.link>

      <%!-- Export dropdown --%>
      <div
        phx-hook="ToolbarPopover"
        id="popover-export-map"
        data-width="11rem"
        data-placement="bottom-end"
      >
        <button
          data-role="trigger"
          type="button"
          class="btn btn-ghost btn-sm gap-1.5"
          title={dgettext("maps", "Export map")}
        >
          <.icon name="upload" class="size-4" />
          <span class="hidden xl:inline">{dgettext("maps", "Export")}</span>
        </button>
        <template data-role="popover-template">
          <ul class="menu menu-xs p-1">
            <li>
              <button
                type="button"
                data-event="export_map"
                data-params={Jason.encode!(%{"format" => "png"})}
                class="text-sm"
              >
                <.icon name="image" class="size-4" />
                {dgettext("maps", "Export as PNG")}
              </button>
            </li>
            <li>
              <button
                type="button"
                data-event="export_map"
                data-params={Jason.encode!(%{"format" => "svg"})}
                class="text-sm"
              >
                <.icon name="file-code" class="size-4" />
                {dgettext("maps", "Export as SVG")}
              </button>
            </li>
          </ul>
        </template>
      </div>

      <%!-- Map settings popover --%>
      <div
        :if={@can_edit && @edit_mode}
        phx-hook="ToolbarPopover"
        id="popover-map-settings"
        data-width="18rem"
        data-placement="bottom-end"
      >
        <button
          data-role="trigger"
          type="button"
          class="btn btn-ghost btn-sm btn-square"
          title={dgettext("maps", "Map Settings")}
        >
          <.icon name="settings" class="size-4" />
        </button>
        <template data-role="popover-template">
          <div class="p-3 space-y-4">
            <%!-- Background image --%>
            <div>
              <label class="label text-xs font-medium">
                {dgettext("maps", "Background Image")}
              </label>
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
                    :if={@bg_upload_input_id}
                    type="button"
                    data-click-input="#bg-upload-form input[type=file]"
                    data-close-on-click="false"
                    class="btn btn-ghost btn-xs flex-1"
                  >
                    <.icon name="refresh-cw" class="size-3" />
                    {dgettext("maps", "Change")}
                  </button>
                  <button
                    type="button"
                    data-event="remove_background"
                    class="btn btn-error btn-outline btn-xs flex-1"
                  >
                    <.icon name="trash-2" class="size-3" />
                    {dgettext("maps", "Remove")}
                  </button>
                </div>
              </div>
              <button
                :if={!background_set?(@map) && @bg_upload_input_id}
                type="button"
                data-click-input="#bg-upload-form input[type=file]"
                data-close-on-click="false"
                class="btn btn-ghost btn-sm w-full border border-dashed border-base-300"
              >
                <.icon name="image-plus" class="size-4" />
                {dgettext("maps", "Upload Background")}
              </button>
            </div>
            <%!-- Map scale --%>
            <div class="pt-2 border-t border-base-300 space-y-2">
              <label class="label text-xs font-medium">
                <.icon name="ruler" class="size-3 inline-block mr-1" />
                {dgettext("maps", "Map Scale")}
              </label>
              <div class="grid grid-cols-2 gap-2">
                <div>
                  <label class="text-xs text-base-content/50">
                    {dgettext("maps", "Total width")}
                  </label>
                  <input
                    type="number"
                    min="0"
                    step="any"
                    value={@map.scale_value || ""}
                    data-blur-event="update_map_scale"
                    data-params={Jason.encode!(%{"field" => "scale_value"})}
                    placeholder="500"
                    class="input input-xs input-bordered w-full"
                  />
                </div>
                <div>
                  <label class="text-xs text-base-content/50">{dgettext("maps", "Unit")}</label>
                  <input
                    type="text"
                    value={@map.scale_unit || ""}
                    data-blur-event="update_map_scale"
                    data-params={Jason.encode!(%{"field" => "scale_unit"})}
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
            <%!-- Map dimensions (read-only) --%>
            <div class="pt-2 border-t border-base-300">
              <label class="label text-xs font-medium text-base-content/60">
                {dgettext("maps", "Dimensions")}
              </label>
              <p class="text-xs text-base-content/50">
                {@map.width || 1000} &times; {@map.height || 1000} px
              </p>
            </div>
          </div>
        </template>
      </div>

      <%!-- Edit/View mode switcher --%>
      <div :if={@can_edit} class="flex rounded-lg border border-base-300/50 overflow-hidden">
        <button
          type="button"
          phx-click="toggle_edit_mode"
          phx-value-mode="view"
          class={"btn btn-sm rounded-none border-0 gap-1 #{if !@edit_mode, do: "btn-primary", else: "btn-ghost"}"}
        >
          <.icon name="eye" class="size-4" />
          <span class="hidden xl:inline">{dgettext("maps", "View")}</span>
        </button>
        <button
          type="button"
          phx-click="toggle_edit_mode"
          phx-value-mode="edit"
          class={"btn btn-sm rounded-none border-0 gap-1 #{if @edit_mode, do: "btn-primary", else: "btn-ghost"}"}
        >
          <.icon name="pencil" class="size-4" />
          <span class="hidden xl:inline">{dgettext("maps", "Edit")}</span>
        </button>
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

  @doc "Map info bar (breadcrumbs + title + shortcut + refs) — for top_bar_extra slot."
  attr :map, :map, required: true
  attr :ancestors, :list, default: []
  attr :workspace, :map, required: true
  attr :project, :map, required: true
  attr :can_edit, :boolean, required: true
  attr :referencing_flows, :list, default: []

  def map_info_bar(assigns) do
    ~H"""
    <div class="hidden lg:flex items-center gap-2 bg-base-200/95 backdrop-blur border border-base-300 rounded-xl shadow-lg px-3">
      <div class="flex items-baseline gap-1">
        <span
          :for={{ancestor, idx} <- Enum.with_index(@ancestors)}
          class="flex items-baseline gap-1 text-xs text-base-content/50"
        >
          <span :if={idx > 0} class="opacity-50">/</span>
          <.link
            navigate={
              ~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/maps/#{ancestor.id}"
            }
            class="hover:text-base-content truncate max-w-[100px]"
          >
            {ancestor.name}
          </.link>
        </span>
        <span :if={@ancestors != []} class="text-xs text-base-content/50 opacity-50">/</span>
        <h1
          :if={@can_edit}
          id="map-title"
          class="text-sm font-medium outline-none rounded px-1 -mx-1 empty:before:content-[attr(data-placeholder)] empty:before:text-base-content/30"
          contenteditable="true"
          phx-hook="EditableTitle"
          phx-update="ignore"
          data-placeholder={dgettext("maps", "Untitled")}
          data-name={@map.name}
        >
          {@map.name}
        </h1>
        <h1 :if={!@can_edit} class="text-sm font-medium">
          {@map.name}
        </h1>
      </div>
      <span :if={@map.shortcut} class="hidden xl:inline badge badge-ghost font-mono text-xs badge-xs">
        #{@map.shortcut}
      </span>
      <div
        :if={@referencing_flows != []}
        phx-hook="ToolbarPopover"
        id="popover-referencing-flows"
        data-width="14rem"
        data-placement="bottom-start"
      >
        <button data-role="trigger" type="button" class="btn btn-xs btn-ghost gap-1 font-normal">
          <.icon name="git-branch" class="size-3.5 opacity-60" />
          <span class="text-xs">
            {dngettext(
              "maps",
              "Used in %{count} flow",
              "Used in %{count} flows",
              length(@referencing_flows),
              count: length(@referencing_flows)
            )}
          </span>
        </button>
        <template data-role="popover-template">
          <ul class="menu menu-xs p-1">
            <li :for={ref <- @referencing_flows}>
              <button
                type="button"
                data-event="navigate_to_referencing_flow"
                data-params={Jason.encode!(%{"flow-id" => ref.flow_id})}
                class="flex items-center gap-2"
              >
                <.icon name="git-branch" class="size-3.5 opacity-60" />
                <span class="truncate">{ref.flow_name}</span>
              </button>
            </li>
          </ul>
        </template>
      </div>
    </div>
    """
  end
end

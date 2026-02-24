defmodule StoryarnWeb.SceneLive.Components.LayerBar do
  @moduledoc """
  Layer bar component for the map editor.

  Displays the list of layers with visibility toggles, rename, fog, and delete options.
  Two variants: `layer_bar/1` (floating card) and `layer_panel/1` (embedded in tree panel).
  """

  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext

  import StoryarnWeb.Components.CoreComponents

  alias Phoenix.LiveView.JS

  @doc """
  Layer panel for embedding inside the tree panel (no outer chrome).
  """
  attr :layers, :list, required: true
  attr :active_layer_id, :any, default: nil
  attr :renaming_layer_id, :any, default: nil
  attr :can_edit, :boolean, required: true
  attr :edit_mode, :boolean, required: true

  def layer_panel(assigns) do
    ~H"""
    <div class="flex flex-col gap-0.5" id="layer-panel-items">
      <.layer_row
        :for={layer <- @layers}
        layer={layer}
        active_layer_id={@active_layer_id}
        renaming_layer_id={@renaming_layer_id}
        can_edit={@can_edit}
        edit_mode={@edit_mode}
        layers_count={length(@layers)}
      />
    </div>
    <button
      :if={@can_edit and @edit_mode}
      type="button"
      phx-click="create_layer"
      class="btn btn-ghost btn-sm w-full gap-1.5 mt-1 text-base-content/50 hover:text-base-content"
    >
      <.icon name="plus" class="size-4" />
      {dgettext("scenes", "New Layer")}
    </button>
    """
  end

  attr :layers, :list, required: true
  attr :active_layer_id, :any, default: nil
  attr :renaming_layer_id, :any, default: nil
  attr :can_edit, :boolean, required: true
  attr :edit_mode, :boolean, required: true

  def layer_bar(assigns) do
    ~H"""
    <div class="bg-base-100 rounded-lg border border-base-300 shadow-md px-3 py-1.5">
      <div class="flex items-center justify-between mb-1">
        <span class="text-xs font-medium text-base-content/60">
          <.icon name="layers" class="size-3.5 inline-block mr-1" />{dgettext("scenes", "Layers")}
        </span>
        <div :if={@can_edit and @edit_mode} class="flex items-center gap-1 shrink-0">
          <button
            type="button"
            phx-click="create_layer"
            class="btn btn-ghost btn-xs btn-square"
            title={dgettext("scenes", "Add layer")}
          >
            <.icon name="plus" class="size-3.5" />
          </button>
        </div>
      </div>
      <div class="flex flex-col gap-0.5" id="layer-bar-items">
        <.layer_row
          :for={layer <- @layers}
          layer={layer}
          active_layer_id={@active_layer_id}
          renaming_layer_id={@renaming_layer_id}
          can_edit={@can_edit}
          edit_mode={@edit_mode}
          layers_count={length(@layers)}
        />
      </div>
    </div>
    """
  end

  attr :layer, :map, required: true
  attr :active_layer_id, :any, required: true
  attr :renaming_layer_id, :any, required: true
  attr :can_edit, :boolean, required: true
  attr :edit_mode, :boolean, required: true
  attr :layers_count, :integer, required: true

  defp layer_row(assigns) do
    ~H"""
    <div class="flex items-center group">
      <button
        :if={@can_edit and @edit_mode}
        type="button"
        phx-click="toggle_layer_visibility"
        phx-value-id={@layer.id}
        class="btn btn-ghost btn-xs btn-square shrink-0"
        title={dgettext("scenes", "Toggle visibility")}
      >
        <.icon
          name={if(@layer.visible, do: "eye", else: "eye-off")}
          class={"size-3 #{unless @layer.visible, do: "opacity-40"}"}
        />
      </button>
      <%!-- Inline rename input (replaces the button text) --%>
      <input
        :if={@renaming_layer_id == @layer.id}
        type="text"
        id={"layer-rename-#{@layer.id}"}
        value={@layer.name}
        phx-blur="rename_layer"
        phx-keydown="rename_layer"
        phx-key="Enter"
        phx-value-id={@layer.id}
        phx-mounted={JS.focus(to: "#layer-rename-#{@layer.id}")}
        class="input input-xs input-bordered flex-1 min-w-0"
      />
      <%!-- Normal layer name button --%>
      <button
        :if={@renaming_layer_id != @layer.id}
        type="button"
        phx-click="set_active_layer"
        phx-value-id={@layer.id}
        class={[
          "btn btn-xs flex-1 justify-start min-w-0",
          if(@layer.id == @active_layer_id,
            do: "btn-primary btn-outline",
            else: "btn-ghost"
          )
        ]}
        title={dgettext("scenes", "Set as active layer")}
      >
        <span class={"text-xs truncate #{unless @layer.visible, do: "opacity-40 line-through"}"}>
          {@layer.name}
        </span>
        <.icon
          :if={@layer.fog_enabled}
          name="cloud-fog"
          class="size-3 opacity-50 shrink-0"
          title={dgettext("scenes", "Fog of War enabled")}
        />
      </button>
      <%!-- Kebab menu for rename/delete --%>
      <div
        :if={@can_edit and @edit_mode and @renaming_layer_id != @layer.id}
        class="dropdown dropdown-end"
      >
        <div
          tabindex="0"
          role="button"
          class="btn btn-ghost btn-xs btn-square opacity-0 group-hover:opacity-100 transition-opacity shrink-0"
          title={dgettext("scenes", "Layer options")}
        >
          <.icon name="ellipsis-vertical" class="size-3" />
        </div>
        <ul
          tabindex="0"
          class="dropdown-content menu bg-base-100 rounded-lg border border-base-300 shadow-md w-36 p-1 z-[1100]"
        >
          <li>
            <button
              type="button"
              phx-click={JS.push("start_rename_layer", value: %{id: @layer.id})}
              class="text-sm"
            >
              <.icon name="pencil" class="size-3.5" />
              {dgettext("scenes", "Rename")}
            </button>
          </li>
          <li>
            <button
              type="button"
              phx-click={
                JS.push("update_layer_fog",
                  value: %{
                    id: @layer.id,
                    field: "fog_enabled",
                    value: to_string(!@layer.fog_enabled)
                  }
                )
              }
              class="text-sm"
            >
              <.icon
                name={if(@layer.fog_enabled, do: "eye", else: "cloud-fog")}
                class="size-3.5"
              />
              {if(@layer.fog_enabled,
                do: dgettext("scenes", "Disable Fog"),
                else: dgettext("scenes", "Enable Fog")
              )}
            </button>
          </li>
          <li>
            <button
              type="button"
              phx-click={
                JS.push("set_pending_delete_layer", value: %{id: @layer.id})
                |> show_modal("delete-layer-confirm")
              }
              class="text-sm text-error"
              disabled={@layers_count <= 1}
            >
              <.icon name="trash-2" class="size-3.5" />
              {dgettext("scenes", "Delete")}
            </button>
          </li>
        </ul>
      </div>
    </div>
    """
  end
end

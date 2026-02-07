defmodule StoryarnWeb.FlowLive.Nodes.Exit.ConfigSidebar do
  @moduledoc """
  Sidebar panel for exit nodes.
  """

  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext

  import StoryarnWeb.Components.CoreComponents

  attr :node, :map, required: true
  attr :form, :map, required: true
  attr :can_edit, :boolean, default: false
  attr :all_pages, :list, default: []
  attr :flow_hubs, :list, default: []
  attr :audio_assets, :list, default: []
  attr :panel_sections, :map, default: %{}
  attr :project_variables, :list, default: []
  attr :referencing_jumps, :list, default: []

  def config_sidebar(assigns) do
    ~H"""
    <.form for={@form} phx-change="update_node_data" phx-debounce="500">
      <.input
        field={@form[:label]}
        type="text"
        label={gettext("Label")}
        placeholder={gettext("e.g., Victory, Defeat")}
        disabled={!@can_edit}
      />
      <.input
        field={@form[:is_success]}
        type="checkbox"
        label={gettext("Success ending")}
        disabled={!@can_edit}
      />
      <p class="text-xs text-base-content/60 mt-1">
        {gettext("Uncheck for failure/game-over endings.")}
      </p>
      <div class="form-control">
        <label class="label">
          <span class="label-text text-xs">{gettext("Technical ID")}</span>
        </label>
        <div class="join w-full">
          <input
            type="text"
            name={@form[:technical_id].name}
            value={@form[:technical_id].value || ""}
            disabled={!@can_edit}
            placeholder={gettext("e.g., victory_ending_1")}
            class="input input-sm input-bordered join-item flex-1 font-mono text-xs"
          />
          <button
            :if={@can_edit}
            type="button"
            phx-click="generate_technical_id"
            onclick="event.stopPropagation()"
            class="btn btn-sm btn-ghost join-item"
            title={gettext("Generate ID")}
          >
            <.icon name="refresh-cw" class="size-3" />
          </button>
        </div>
        <p class="text-xs text-base-content/60 mt-1">
          {gettext("Unique identifier for export and game integration.")}
        </p>
      </div>
    </.form>
    """
  end

  def wrap_in_form?, do: false
end

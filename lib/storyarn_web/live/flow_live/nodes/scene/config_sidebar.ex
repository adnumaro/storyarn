defmodule StoryarnWeb.FlowLive.Nodes.Scene.ConfigSidebar do
  @moduledoc """
  Sidebar panel for scene nodes.

  Renders: location selector, INT/EXT, sub-location, time of day,
  description, and technical ID fields.
  """

  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext

  import StoryarnWeb.Components.CoreComponents

  attr :node, :map, required: true
  attr :form, :map, required: true
  attr :can_edit, :boolean, default: false
  attr :all_sheets, :list, default: []
  attr :flow_hubs, :list, default: []
  attr :project, :map, required: true
  attr :current_user, :map, required: true
  attr :panel_sections, :map, default: %{}
  attr :project_variables, :list, default: []
  attr :referencing_jumps, :list, default: []
  attr :available_flows, :list, default: []
  attr :subflow_exits, :list, default: []
  attr :outcome_tags_suggestions, :list, default: []
  attr :referencing_flows, :list, default: []

  def config_sidebar(assigns) do
    location_options =
      [{"", gettext("Select location...")}] ++
        Enum.map(assigns.all_sheets, fn sheet -> {sheet.name, sheet.id} end)

    int_ext_options = [
      {gettext("INT."), "int"},
      {gettext("EXT."), "ext"},
      {gettext("INT./EXT."), "int_ext"}
    ]

    time_of_day_options = [
      {gettext("Not set"), ""},
      {gettext("Day"), "day"},
      {gettext("Night"), "night"},
      {gettext("Morning"), "morning"},
      {gettext("Evening"), "evening"},
      {gettext("Continuous"), "continuous"}
    ]

    assigns =
      assigns
      |> assign(:location_options, location_options)
      |> assign(:int_ext_options, int_ext_options)
      |> assign(:time_of_day_options, time_of_day_options)

    ~H"""
    <div class="space-y-4">
      <.form for={@form} phx-change="update_node_data" phx-debounce="500">
        <%!-- Location --%>
        <.input
          field={@form[:location_sheet_id]}
          type="select"
          label={gettext("Location")}
          options={@location_options}
          disabled={!@can_edit}
        />

        <%!-- INT / EXT + Time of Day (side by side) --%>
        <div class="grid grid-cols-2 gap-2 mt-4">
          <.input
            field={@form[:int_ext]}
            type="select"
            label={gettext("Int / Ext")}
            options={@int_ext_options}
            disabled={!@can_edit}
          />
          <.input
            field={@form[:time_of_day]}
            type="select"
            label={gettext("Time of Day")}
            options={@time_of_day_options}
            disabled={!@can_edit}
          />
        </div>

        <%!-- Sub-location --%>
        <.input
          field={@form[:sub_location]}
          type="text"
          label={gettext("Sub-location")}
          placeholder={gettext("e.g., Lobby, Rooftop, Room 1")}
          disabled={!@can_edit}
          class="mt-4"
        />

        <%!-- Description --%>
        <.input
          field={@form[:description]}
          type="textarea"
          label={gettext("Description")}
          placeholder={gettext("Action lines, transition notes...")}
          disabled={!@can_edit}
          rows={3}
          class="mt-4"
        />
      </.form>

      <%!-- Advanced (Technical ID) --%>
      <details
        class="collapse collapse-arrow bg-base-200 mt-2"
        open={Map.get(@panel_sections, "technical", false)}
      >
        <summary
          class="collapse-title text-sm font-medium flex items-center gap-2 cursor-pointer"
          phx-click="toggle_panel_section"
          phx-value-section="technical"
          onclick="event.preventDefault()"
        >
          <.icon name="hash" class="size-4" />
          {gettext("Advanced")}
        </summary>
        <div class="collapse-content space-y-3">
          <div class="form-control">
            <label class="label">
              <span class="label-text text-xs">{gettext("Technical ID")}</span>
            </label>
            <div class="join w-full">
              <.form
                for={@form}
                phx-change="update_node_data"
                phx-debounce="500"
                class="flex-1 join-item"
              >
                <input
                  type="text"
                  name={@form[:technical_id].name}
                  value={@form[:technical_id].value || ""}
                  disabled={!@can_edit}
                  placeholder={gettext("e.g., ch1_int_hotel_1")}
                  class="input input-sm input-bordered w-full font-mono text-xs"
                />
              </.form>
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
        </div>
      </details>
    </div>
    """
  end

  def wrap_in_form?, do: false
end

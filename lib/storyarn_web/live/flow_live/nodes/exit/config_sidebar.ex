defmodule StoryarnWeb.FlowLive.Nodes.Exit.ConfigSidebar do
  @moduledoc """
  Sidebar panel for exit nodes.
  """

  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext

  import StoryarnWeb.Components.CoreComponents
  import StoryarnWeb.Components.ColorPicker

  attr :node, :map, required: true
  attr :form, :map, required: true
  attr :can_edit, :boolean, default: false
  attr :all_sheets, :list, default: []
  attr :flow_hubs, :list, default: []
  attr :audio_assets, :list, default: []
  attr :panel_sections, :map, default: %{}
  attr :project_variables, :list, default: []
  attr :referencing_jumps, :list, default: []
  attr :available_flows, :list, default: []
  attr :subflow_exits, :list, default: []
  attr :outcome_tags_suggestions, :list, default: []
  attr :referencing_flows, :list, default: []

  def config_sidebar(assigns) do
    outcome_tags = assigns.node.data["outcome_tags"] || []
    outcome_color = assigns.node.data["outcome_color"] || "#22c55e"
    exit_mode = assigns.node.data["exit_mode"] || "terminal"
    referenced_flow_id = assigns.node.data["referenced_flow_id"]

    flow_options =
      [{"", gettext("Select a flow...")}] ++
        Enum.map(assigns.available_flows, fn flow ->
          display =
            if flow.shortcut && flow.shortcut != "" do
              "#{flow.name} (##{flow.shortcut})"
            else
              flow.name
            end

          {display, to_string(flow.id)}
        end)

    current_ref_str = if referenced_flow_id, do: to_string(referenced_flow_id), else: ""

    assigns =
      assigns
      |> assign(:outcome_tags, outcome_tags)
      |> assign(:outcome_color, outcome_color)
      |> assign(:exit_mode, exit_mode)
      |> assign(:flow_options, flow_options)
      |> assign(:current_ref_str, current_ref_str)

    ~H"""
    <div class="space-y-4">
      <%!-- Label --%>
      <.form for={@form} phx-change="update_node_data" phx-debounce="500">
        <.input
          field={@form[:label]}
          type="text"
          label={gettext("Label")}
          placeholder={gettext("e.g., Victory, Defeat")}
          disabled={!@can_edit}
        />
      </.form>

      <%!-- Outcome Tags --%>
      <div>
        <label class="label">
          <span class="label-text text-xs font-medium">{gettext("Outcome Tags")}</span>
        </label>
        <div class="flex flex-wrap gap-1 mb-2">
          <span
            :for={tag <- @outcome_tags}
            class="badge badge-sm gap-1"
          >
            {tag}
            <button
              :if={@can_edit}
              type="button"
              phx-click="remove_outcome_tag"
              phx-value-tag={tag}
              class="cursor-pointer hover:text-error"
            >
              x
            </button>
          </span>
        </div>
        <form :if={@can_edit} phx-submit="add_outcome_tag" class="flex gap-1">
          <input
            type="text"
            name="tag"
            placeholder={gettext("Add tag...")}
            class="input input-sm input-bordered flex-1 text-xs"
            list="outcome-tag-suggestions"
            autocomplete="off"
          />
          <button type="submit" class="btn btn-sm btn-ghost">
            <.icon name="plus" class="size-3" />
          </button>
        </form>
        <datalist id="outcome-tag-suggestions">
          <option :for={tag <- @outcome_tags_suggestions} value={tag} />
        </datalist>
        <p class="text-xs text-base-content/60 mt-1">
          {gettext("Free-form tags for game engine consumption.")}
        </p>
      </div>

      <%!-- Outcome Color --%>
      <div>
        <label class="label">
          <span class="label-text text-xs font-medium">{gettext("Color")}</span>
        </label>
        <.color_picker
          id={"exit-color-#{@node.id}"}
          color={@outcome_color}
          event="update_outcome_color"
          field="color"
          disabled={!@can_edit}
        />
      </div>

      <%!-- Exit Mode --%>
      <div>
        <label class="label">
          <span class="label-text text-xs font-medium">{gettext("Exit Mode")}</span>
        </label>
        <div class="space-y-1">
          <label class="flex items-center gap-2 cursor-pointer p-1 rounded hover:bg-base-200">
            <input
              type="radio"
              name="exit_mode"
              value="terminal"
              checked={@exit_mode == "terminal"}
              phx-click="update_exit_mode"
              phx-value-mode="terminal"
              disabled={!@can_edit}
              class="radio radio-xs"
            />
            <span class="text-xs">{gettext("Terminal (end)")}</span>
          </label>
          <label class="flex items-center gap-2 cursor-pointer p-1 rounded hover:bg-base-200">
            <input
              type="radio"
              name="exit_mode"
              value="flow_reference"
              checked={@exit_mode == "flow_reference"}
              phx-click="update_exit_mode"
              phx-value-mode="flow_reference"
              disabled={!@can_edit}
              class="radio radio-xs"
            />
            <span class="text-xs inline-flex items-center gap-1">
              {gettext("Continue to flow")} <.icon name="arrow-right" class="size-3" />
            </span>
          </label>
          <label class="flex items-center gap-2 cursor-pointer p-1 rounded hover:bg-base-200">
            <input
              type="radio"
              name="exit_mode"
              value="caller_return"
              checked={@exit_mode == "caller_return"}
              phx-click="update_exit_mode"
              phx-value-mode="caller_return"
              disabled={!@can_edit}
              class="radio radio-xs"
            />
            <span class="text-xs inline-flex items-center gap-1">
              {gettext("Return to caller")} <.icon name="corner-down-left" class="size-3" />
            </span>
          </label>
        </div>
      </div>

      <%!-- Flow Reference (only when flow_reference mode) --%>
      <div :if={@exit_mode == "flow_reference"}>
        <label class="label text-sm font-medium">{gettext("Target Flow")}</label>
        <form phx-change="update_exit_reference">
          <select
            class="select select-bordered select-sm w-full"
            name="flow-id"
            disabled={!@can_edit}
          >
            <option
              :for={{display, value} <- @flow_options}
              value={value}
              selected={value == @current_ref_str}
            >
              {display}
            </option>
          </select>
        </form>

        <div :if={@node.data["stale_reference"]} class="alert alert-error text-sm mt-2">
          <.icon name="alert-triangle" class="size-4" />
          <span>{gettext("Referenced flow has been deleted.")}</span>
        </div>

        <button
          :if={@current_ref_str != "" && !@node.data["stale_reference"]}
          type="button"
          class="btn btn-ghost btn-xs w-full mt-2"
          phx-click="navigate_to_exit_flow"
          phx-value-flow-id={@current_ref_str}
        >
          <.icon name="external-link" class="size-3 mr-1" />
          {gettext("Open Flow")}
        </button>
      </div>

      <%!-- Technical ID --%>
      <div class="form-control">
        <label class="label">
          <span class="label-text text-xs">{gettext("Technical ID")}</span>
        </label>
        <div class="join w-full">
          <.form for={@form} phx-change="update_node_data" phx-debounce="500" class="flex-1 join-item">
            <input
              type="text"
              name={@form[:technical_id].name}
              value={@form[:technical_id].value || ""}
              disabled={!@can_edit}
              placeholder={gettext("e.g., victory_ending_1")}
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

      <%!-- Referenced By --%>
      <div :if={@referencing_flows != []}>
        <h3 class="text-xs font-semibold text-base-content/60 uppercase tracking-wide mb-2">
          {gettext("Referenced By")}
          <span class="text-base-content/40 ml-1">({length(@referencing_flows)})</span>
        </h3>
        <div class="space-y-1">
          <button
            :for={ref <- @referencing_flows}
            type="button"
            class="btn btn-ghost btn-xs w-full justify-start gap-2 font-normal"
            phx-click="navigate_to_referencing_flow"
            phx-value-flow-id={ref.flow_id}
          >
            <.icon
              name={if ref.node_type == "subflow", do: "box", else: "square"}
              class="size-3 opacity-60"
            />
            <span class="truncate">{ref.flow_name}</span>
          </button>
        </div>
      </div>
    </div>
    """
  end

  def wrap_in_form?, do: false
end

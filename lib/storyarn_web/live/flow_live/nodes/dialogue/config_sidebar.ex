defmodule StoryarnWeb.FlowLive.Nodes.Dialogue.ConfigSidebar do
  @moduledoc """
  Sidebar panel for dialogue nodes.

  Renders: speaker, stage directions, text editor, responses, menu text,
  audio, logic fields, and technical fields.
  """

  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext

  import StoryarnWeb.Components.ExpressionEditor
  import StoryarnWeb.Components.CoreComponents
  import StoryarnWeb.FlowLive.Components.NodeTypeHelpers,
    only: [word_count: 1, response_has_advanced?: 1]

  alias Storyarn.Flows.Condition

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

  def config_sidebar(assigns) do
    speaker_options =
      [{"", dgettext("flows", "Select speaker...")}] ++
        Enum.map(assigns.all_sheets, fn sheet -> {sheet.name, sheet.id} end)

    assigns = assign(assigns, :speaker_options, speaker_options)

    ~H"""
    <.form for={@form} phx-change="update_node_data" phx-debounce="500">
      <.input
        field={@form[:speaker_sheet_id]}
        type="select"
        label={dgettext("flows", "Speaker")}
        options={@speaker_options}
        disabled={!@can_edit}
      />
      <.input
        field={@form[:stage_directions]}
        type="textarea"
        label={dgettext("flows", "Stage Directions")}
        placeholder={dgettext("flows", "(whispering)")}
        disabled={!@can_edit}
        rows={2}
        class="italic font-mono text-sm"
      />
      <div class="form-control mt-4">
        <label class="label">
          <span class="label-text">{dgettext("flows", "Text")}</span>
        </label>
        <div
          id={"dialogue-text-editor-#{@node.id}"}
          phx-hook="TiptapEditor"
          phx-update="ignore"
          data-node-id={@node.id}
          data-content={@form[:text].value || ""}
          data-editable={to_string(@can_edit)}
          class="border border-base-300 rounded-lg bg-base-100 p-2"
        >
        </div>
      </div>
      <.dialogue_responses_form
        form={@form}
        node={@node}
        can_edit={@can_edit}
        project_variables={@project_variables}
        panel_sections={@panel_sections}
      />
      <details
        class="collapse collapse-arrow bg-base-200 mt-4"
        open={Map.get(@panel_sections, "menu_text", false)}
      >
        <summary
          class="collapse-title text-sm font-medium cursor-pointer"
          phx-click="toggle_panel_section"
          phx-value-section="menu_text"
          onclick="event.preventDefault()"
        >
          {dgettext("flows", "Menu Text")}
        </summary>
        <div class="collapse-content">
          <.input
            field={@form[:menu_text]}
            type="text"
            placeholder={dgettext("flows", "Short text shown in response menus")}
            disabled={!@can_edit}
          />
          <p class="text-xs text-base-content/60 mt-1">
            {dgettext("flows", "Optional shorter text to display in dialogue choice menus.")}
          </p>
        </div>
      </details>
    </.form>
    <details
      class="collapse collapse-arrow bg-base-200 mt-2"
      open={Map.get(@panel_sections, "audio", @form[:audio_asset_id] && @form[:audio_asset_id].value != nil)}
    >
      <summary
        class="collapse-title text-sm font-medium flex items-center gap-2 cursor-pointer"
        phx-click="toggle_panel_section"
        phx-value-section="audio"
        onclick="event.preventDefault()"
      >
        <.icon name="volume-2" class="size-4" />
        {dgettext("flows", "Audio")}
      </summary>
      <div class="collapse-content">
        <.live_component
          module={StoryarnWeb.Components.AudioPicker}
          id={"audio-picker-#{@node.id}"}
          project={@project}
          current_user={@current_user}
          selected_asset_id={@form[:audio_asset_id] && @form[:audio_asset_id].value}
          can_edit={@can_edit}
        />
      </div>
    </details>
    <.form for={@form} phx-change="update_node_data" phx-debounce="500">
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
          {dgettext("flows", "Technical")}
        </summary>
        <div class="collapse-content space-y-3">
          <div class="form-control">
            <label class="label">
              <span class="label-text text-xs">{dgettext("flows", "Technical ID")}</span>
            </label>
            <div class="join w-full">
              <input
                type="text"
                name={@form[:technical_id].name}
                value={@form[:technical_id].value || ""}
                disabled={!@can_edit}
                placeholder={dgettext("flows", "auto_generated_id")}
                class="input input-sm input-bordered join-item flex-1 font-mono text-xs"
              />
              <button
                :if={@can_edit}
                type="button"
                phx-click="generate_technical_id"
                onclick="event.stopPropagation()"
                class="btn btn-sm btn-ghost join-item"
                title={dgettext("flows", "Generate ID")}
              >
                <.icon name="refresh-cw" class="size-3" />
              </button>
            </div>
            <p class="text-xs text-base-content/60 mt-1">
              {dgettext("flows", "Unique identifier for export and game integration.")}
            </p>
          </div>
          <div class="form-control">
            <label class="label">
              <span class="label-text text-xs">{dgettext("flows", "Localization ID")}</span>
            </label>
            <div class="join w-full">
              <input
                type="text"
                name={@form[:localization_id].name}
                value={@form[:localization_id].value || ""}
                disabled={!@can_edit}
                placeholder={dgettext("flows", "dlg_001")}
                class="input input-sm input-bordered join-item flex-1 font-mono text-xs"
              />
              <button
                type="button"
                data-copy-text={@form[:localization_id].value || ""}
                onclick="event.stopPropagation()"
                class="btn btn-sm btn-ghost join-item"
                title={dgettext("flows", "Copy to clipboard")}
              >
                <.icon name="copy" class="size-3" />
              </button>
            </div>
            <p class="text-xs text-base-content/60 mt-1">
              {dgettext("flows", "ID for localization tools (Crowdin, Lokalise).")}
            </p>
          </div>
          <div class="divider my-1"></div>
          <div class="flex items-center justify-between text-xs text-base-content/70">
            <span>{dgettext("flows", "Word count")}</span>
            <span class="font-mono badge badge-ghost badge-sm">
              {word_count(@form[:text].value)}
            </span>
          </div>
        </div>
      </details>
    </.form>
    """
  end

  def wrap_in_form?, do: false

  # Sub-components

  attr :form, :map, required: true
  attr :node, :map, required: true
  attr :can_edit, :boolean, default: false
  attr :project_variables, :list, default: []
  attr :panel_sections, :map, default: %{}

  def dialogue_responses_form(assigns) do
    ~H"""
    <div class="form-control mt-4">
      <label class="label">
        <span class="label-text">{dgettext("flows", "Responses")}</span>
      </label>
      <div class="space-y-2">
        <.response_item
          :for={response <- @form[:responses].value || []}
          response={response}
          node={@node}
          can_edit={@can_edit}
          project_variables={@project_variables}
          panel_sections={@panel_sections}
        />
        <button
          :if={@can_edit}
          type="button"
          phx-click="add_response"
          phx-value-node-id={@node.id}
          class="btn btn-ghost btn-sm gap-1 w-full border border-dashed border-base-300"
        >
          <.icon name="plus" class="size-4" />
          {dgettext("flows", "Add response")}
        </button>
      </div>
      <p :if={(@form[:responses].value || []) == []} class="text-xs text-base-content/60 mt-1">
        {dgettext("flows", "No responses means a simple dialogue with one output.")}
      </p>
    </div>
    """
  end

  attr :response, :map, required: true
  attr :node, :map, required: true
  attr :can_edit, :boolean, default: false
  attr :project_variables, :list, default: []
  attr :panel_sections, :map, default: %{}

  defp response_item(assigns) do
    raw_condition = assigns.response["condition"] || ""

    condition_data =
      case Condition.parse(raw_condition) do
        :legacy -> Condition.new()
        nil -> Condition.new()
        cond_data -> cond_data
      end

    assigns = assign(assigns, :parsed_condition, condition_data)

    ~H"""
    <div class="p-2 bg-base-200 rounded-lg space-y-2">
      <div class="flex items-center gap-2">
        <input
          type="text"
          value={@response["text"]}
          phx-blur="update_response_text"
          phx-value-response-id={@response["id"]}
          phx-value-node-id={@node.id}
          disabled={!@can_edit}
          placeholder={dgettext("flows", "Response text...")}
          class="input input-sm input-bordered flex-1"
        />
        <button
          :if={@can_edit}
          type="button"
          phx-click="remove_response"
          phx-value-response-id={@response["id"]}
          phx-value-node-id={@node.id}
          class="btn btn-ghost btn-xs btn-square text-error"
          title={dgettext("flows", "Remove response")}
        >
          <.icon name="x" class="size-3" />
        </button>
      </div>
      <details class="collapse collapse-arrow bg-base-100">
        <summary class="collapse-title text-xs py-1 min-h-0 cursor-pointer">
          {dgettext("flows", "Advanced")}
          <span :if={has_advanced_settings?(@response)} class="badge badge-warning badge-xs ml-1">
          </span>
        </summary>
        <div class="collapse-content space-y-3 pt-2">
          <%!-- Condition Builder --%>
          <div class="space-y-1">
            <div class="flex items-center gap-1 text-xs text-base-content/60">
              <.icon name="git-branch" class="size-3" />
              <span>{dgettext("flows", "Condition")}</span>
            </div>
            <.expression_editor
              id={"response-cond-expr-#{@response["id"]}"}
              mode="condition"
              condition={@parsed_condition}
              variables={@project_variables}
              can_edit={@can_edit}
              context={%{"response-id" => @response["id"], "node-id" => @node.id}}
              active_tab={Map.get(@panel_sections, "tab_response-cond-expr-#{@response["id"]}", "builder")}
            />
          </div>

          <%!-- Instruction --%>
          <div class="space-y-1">
            <div class="flex items-center gap-1 text-xs text-base-content/60">
              <.icon name="zap" class="size-3" />
              <span>{dgettext("flows", "Instruction")}</span>
            </div>
            <.expression_editor
              id={"response-inst-expr-#{@response["id"]}"}
              mode="instruction"
              assignments={@response["instruction_assignments"] || []}
              variables={@project_variables}
              can_edit={@can_edit}
              context={%{"response-id" => @response["id"], "node-id" => @node.id}}
              event_name="update_response_instruction_builder"
              active_tab={Map.get(@panel_sections, "tab_response-inst-expr-#{@response["id"]}", "builder")}
            />
          </div>
        </div>
      </details>
    </div>
    """
  end

  defp has_advanced_settings?(response), do: response_has_advanced?(response)

end

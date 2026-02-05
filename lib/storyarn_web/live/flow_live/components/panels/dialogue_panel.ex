defmodule StoryarnWeb.FlowLive.Components.Panels.DialoguePanel do
  @moduledoc """
  Properties panel component for dialogue nodes.

  Renders: speaker, stage directions, text editor, responses, menu text,
  audio, logic fields, and technical fields.
  """

  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext

  import StoryarnWeb.Components.ConditionBuilder
  import StoryarnWeb.Components.CoreComponents
  import StoryarnWeb.FlowLive.Components.NodeTypeHelpers, only: [word_count: 1]

  alias Storyarn.Flows.Condition

  attr :form, :map, required: true
  attr :node, :map, required: true
  attr :can_edit, :boolean, default: false
  attr :speaker_options, :list, required: true
  attr :audio_options, :list, required: true
  attr :selected_audio, :map, default: nil
  attr :panel_sections, :map, default: %{}
  attr :project_variables, :list, default: []

  def dialogue_properties(assigns) do
    ~H"""
    <.input
      field={@form[:speaker_page_id]}
      type="select"
      label={gettext("Speaker")}
      options={@speaker_options}
      disabled={!@can_edit}
    />
    <.input
      field={@form[:stage_directions]}
      type="textarea"
      label={gettext("Stage Directions")}
      placeholder={gettext("(whispering)")}
      disabled={!@can_edit}
      rows={2}
      class="italic font-mono text-sm"
    />
    <div class="form-control mt-4">
      <label class="label">
        <span class="label-text">{gettext("Text")}</span>
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
        {gettext("Menu Text")}
      </summary>
      <div class="collapse-content">
        <.input
          field={@form[:menu_text]}
          type="text"
          placeholder={gettext("Short text shown in response menus")}
          disabled={!@can_edit}
        />
        <p class="text-xs text-base-content/60 mt-1">
          {gettext("Optional shorter text to display in dialogue choice menus.")}
        </p>
      </div>
    </details>
    <details
      class="collapse collapse-arrow bg-base-200 mt-2"
      open={Map.get(@panel_sections, "audio", @selected_audio != nil)}
    >
      <summary
        class="collapse-title text-sm font-medium flex items-center gap-2 cursor-pointer"
        phx-click="toggle_panel_section"
        phx-value-section="audio"
        onclick="event.preventDefault()"
      >
        <.icon name="volume-2" class="size-4" />
        {gettext("Audio")}
        <span :if={@selected_audio} class="badge badge-primary badge-xs">1</span>
      </summary>
      <div class="collapse-content">
        <.input
          field={@form[:audio_asset_id]}
          type="select"
          options={@audio_options}
          disabled={!@can_edit}
        />
        <div
          :if={@selected_audio}
          class="mt-3 p-3 bg-base-100 rounded-lg border border-base-300"
        >
          <p
            class="text-xs text-base-content/60 mb-2 truncate"
            title={@selected_audio.filename}
          >
            {gettext("Preview:")} {@selected_audio.filename}
          </p>
          <audio controls class="w-full h-8">
            <source src={@selected_audio.url} type={@selected_audio.content_type} />
            {gettext("Your browser does not support audio playback.")}
          </audio>
        </div>
        <p :if={!@selected_audio} class="text-xs text-base-content/60 mt-2">
          {gettext("Attach voice-over or ambient audio to this dialogue.")}
        </p>
      </div>
    </details>
    <details
      class="collapse collapse-arrow bg-base-200 mt-2"
      open={Map.get(@panel_sections, "logic", has_logic_fields?(@form))}
    >
      <summary
        class="collapse-title text-sm font-medium flex items-center gap-2 cursor-pointer"
        phx-click="toggle_panel_section"
        phx-value-section="logic"
        onclick="event.preventDefault()"
      >
        <.icon name="zap" class="size-4" />
        {gettext("Logic")}
        <span :if={has_logic_fields?(@form)} class="badge badge-warning badge-xs">⚡</span>
      </summary>
      <div class="collapse-content space-y-3">
        <div class="form-control">
          <label class="label">
            <span class="label-text text-xs">{gettext("Input Condition")}</span>
          </label>
          <input
            type="text"
            name="input_condition"
            value={@form[:input_condition].value || ""}
            phx-blur="update_node_field"
            phx-value-field="input_condition"
            disabled={!@can_edit}
            placeholder={gettext("e.g., reputation > 50")}
            class="input input-sm input-bordered font-mono text-xs"
          />
          <p class="text-xs text-base-content/60 mt-1">
            {gettext("Node is only reachable when this condition is true.")}
          </p>
        </div>
        <div class="form-control">
          <label class="label">
            <span class="label-text text-xs">{gettext("Output Instruction")}</span>
          </label>
          <textarea
            name="output_instruction"
            phx-blur="update_node_field"
            phx-value-field="output_instruction"
            disabled={!@can_edit}
            placeholder={gettext("e.g., set(\"talked_to_merchant\", true)")}
            rows={2}
            class="textarea textarea-sm textarea-bordered font-mono text-xs"
          >{@form[:output_instruction].value || ""}</textarea>
          <p class="text-xs text-base-content/60 mt-1">
            {gettext("Executed when leaving this node (any response).")}
          </p>
        </div>
      </div>
    </details>
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
        {gettext("Technical")}
      </summary>
      <div class="collapse-content space-y-3">
        <div class="form-control">
          <label class="label">
            <span class="label-text text-xs">{gettext("Technical ID")}</span>
          </label>
          <div class="join w-full">
            <input
              type="text"
              name="technical_id"
              value={@form[:technical_id].value || ""}
              phx-blur="update_node_field"
              phx-value-field="technical_id"
              disabled={!@can_edit}
              placeholder={gettext("auto_generated_id")}
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
        <div class="form-control">
          <label class="label">
            <span class="label-text text-xs">{gettext("Localization ID")}</span>
          </label>
          <div class="join w-full">
            <input
              type="text"
              name="localization_id"
              value={@form[:localization_id].value || ""}
              phx-blur="update_node_field"
              phx-value-field="localization_id"
              disabled={!@can_edit}
              placeholder={gettext("dlg_001")}
              class="input input-sm input-bordered join-item flex-1 font-mono text-xs"
            />
            <button
              type="button"
              data-copy-text={@form[:localization_id].value || ""}
              onclick="event.stopPropagation()"
              class="btn btn-sm btn-ghost join-item"
              title={gettext("Copy to clipboard")}
            >
              <.icon name="copy" class="size-3" />
            </button>
          </div>
          <p class="text-xs text-base-content/60 mt-1">
            {gettext("ID for localization tools (Crowdin, Lokalise).")}
          </p>
        </div>
        <div class="divider my-1"></div>
        <div class="flex items-center justify-between text-xs text-base-content/70">
          <span>{gettext("Word count")}</span>
          <span class="font-mono badge badge-ghost badge-sm">
            {word_count(@form[:text].value)}
          </span>
        </div>
      </div>
    </details>
    """
  end

  attr :form, :map, required: true
  attr :node, :map, required: true
  attr :can_edit, :boolean, default: false
  attr :project_variables, :list, default: []

  def dialogue_responses_form(assigns) do
    ~H"""
    <div class="form-control mt-4">
      <label class="label">
        <span class="label-text">{gettext("Responses")}</span>
      </label>
      <div class="space-y-2">
        <.response_item
          :for={response <- @form[:responses].value || []}
          response={response}
          node={@node}
          can_edit={@can_edit}
          project_variables={@project_variables}
        />
        <button
          :if={@can_edit}
          type="button"
          phx-click="add_response"
          phx-value-node-id={@node.id}
          class="btn btn-ghost btn-sm gap-1 w-full border border-dashed border-base-300"
        >
          <.icon name="plus" class="size-4" />
          {gettext("Add response")}
        </button>
      </div>
      <p :if={(@form[:responses].value || []) == []} class="text-xs text-base-content/60 mt-1">
        {gettext("No responses means a simple dialogue with one output.")}
      </p>
    </div>
    """
  end

  attr :response, :map, required: true
  attr :node, :map, required: true
  attr :can_edit, :boolean, default: false
  attr :project_variables, :list, default: []

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
          placeholder={gettext("Response text...")}
          class="input input-sm input-bordered flex-1"
        />
        <button
          :if={@can_edit}
          type="button"
          phx-click="remove_response"
          phx-value-response-id={@response["id"]}
          phx-value-node-id={@node.id}
          class="btn btn-ghost btn-xs btn-square text-error"
          title={gettext("Remove response")}
        >
          <.icon name="x" class="size-3" />
        </button>
      </div>
      <details class="collapse collapse-arrow bg-base-100">
        <summary class="collapse-title text-xs py-1 min-h-0 cursor-pointer">
          {gettext("Advanced")}
          <span :if={has_advanced_settings?(@response)} class="badge badge-warning badge-xs ml-1">
            ⚡
          </span>
        </summary>
        <div class="collapse-content space-y-3 pt-2">
          <%!-- Condition Builder --%>
          <div class="space-y-1">
            <div class="flex items-center gap-1 text-xs text-base-content/60">
              <.icon name="git-branch" class="size-3" />
              <span>{gettext("Condition")}</span>
            </div>
            <.condition_builder
              id={"response-condition-#{@response["id"]}"}
              condition={@parsed_condition}
              variables={@project_variables}
              on_change="update_response_condition_builder"
              can_edit={@can_edit}
              show_expression_toggle={false}
              expression_mode={false}
              raw_expression=""
              context={%{"response-id" => @response["id"], "node-id" => @node.id}}
            />
          </div>

          <%!-- Instruction --%>
          <div class="flex items-center gap-2">
            <.icon name="zap" class="size-3 text-base-content/50 flex-shrink-0" />
            <input
              type="text"
              value={@response["instruction"]}
              phx-blur="update_response_instruction"
              phx-value-response-id={@response["id"]}
              phx-value-node-id={@node.id}
              disabled={!@can_edit}
              placeholder={gettext("Instruction (optional)")}
              class="input input-xs input-bordered flex-1 font-mono text-xs"
            />
          </div>
        </div>
      </details>
    </div>
    """
  end

  defp has_advanced_settings?(response) do
    condition = response["condition"]
    instruction = response["instruction"]

    (condition != nil and condition != "") or
      (instruction != nil and instruction != "")
  end

  defp has_logic_fields?(form) do
    input_condition = form[:input_condition] && form[:input_condition].value
    output_instruction = form[:output_instruction] && form[:output_instruction].value

    (input_condition && input_condition != "") ||
      (output_instruction && output_instruction != "")
  end
end

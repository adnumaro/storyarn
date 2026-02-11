defmodule StoryarnWeb.Components.Screenplay.ElementRenderer do
  @moduledoc """
  Renders screenplay elements with industry-standard formatting.

  Dispatches to per-type block functions based on element type.
  Includes inline builders for interactive types (conditional,
  instruction, response) and badge stubs for flow-marker types.
  """

  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext

  import StoryarnWeb.Components.CoreComponents, only: [icon: 1]
  import StoryarnWeb.Components.ConditionBuilder
  import StoryarnWeb.Components.InstructionBuilder

  @editable_types ~w(scene_heading action character dialogue parenthetical transition note section)
  @stub_types ~w(dual_dialogue hub_marker jump_marker title_page)

  attr :element, :map, required: true
  attr :can_edit, :boolean, default: false
  attr :variables, :list, default: []
  attr :linked_pages, :map, default: %{}

  def element_renderer(assigns) do
    assigns = assign(assigns, :editable, assigns.can_edit and assigns.element.type in @editable_types)

    ~H"""
    <div
      id={"sp-el-#{@element.id}"}
      class={[
        "screenplay-element",
        "sp-#{@element.type}",
        empty?(@element) && "sp-empty"
      ]}
      phx-hook={@editable && "ScreenplayElement"}
      phx-update={@editable && "ignore"}
      data-element-id={@element.id}
      data-element-type={@element.type}
      data-position={@element.position}
    >
      {render_block(assigns)}
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Standard blocks — single template, per-type placeholder
  # ---------------------------------------------------------------------------

  defp render_block(%{element: %{type: type}} = assigns) when type in @editable_types do
    assigns = assign(assigns, :placeholder, placeholder_for(type))

    ~H"""
    <div class="sp-block" contenteditable={to_string(@can_edit)} data-placeholder={@placeholder}>{@element.content}</div>
    """
  end

  # ---------------------------------------------------------------------------
  # Page break — visual separator (not editable)
  # ---------------------------------------------------------------------------

  defp render_block(%{element: %{type: "page_break"}} = assigns) do
    ~H"""
    <div class="sp-page-break-line"></div>
    """
  end

  # ---------------------------------------------------------------------------
  # Conditional block — inline condition builder
  # ---------------------------------------------------------------------------

  defp render_block(%{element: %{type: "conditional"}} = assigns) do
    ~H"""
    <div class="sp-interactive-block sp-interactive-condition">
      <div class="sp-interactive-header">
        <.icon name="git-branch" class="size-4 opacity-60" />
        <span class="sp-interactive-label">{gettext("Condition")}</span>
      </div>
      <.condition_builder
        id={"sp-condition-#{@element.id}"}
        condition={@element.data["condition"]}
        variables={@variables}
        can_edit={@can_edit}
        context={%{"element-id" => to_string(@element.id)}}
        event_name="update_screenplay_condition"
      />
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Instruction block — inline instruction builder
  # ---------------------------------------------------------------------------

  defp render_block(%{element: %{type: "instruction"}} = assigns) do
    ~H"""
    <div class="sp-interactive-block sp-interactive-instruction">
      <div class="sp-interactive-header">
        <.icon name="zap" class="size-4 opacity-60" />
        <span class="sp-interactive-label">{gettext("Instruction")}</span>
      </div>
      <.instruction_builder
        id={"sp-instruction-#{@element.id}"}
        assignments={@element.data["assignments"] || []}
        variables={@variables}
        can_edit={@can_edit}
        context={%{"element-id" => to_string(@element.id)}}
        event_name="update_screenplay_instruction"
      />
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Response block — editable choices list
  # ---------------------------------------------------------------------------

  defp render_block(%{element: %{type: "response"}} = assigns) do
    choices = assigns.element.data["choices"] || []
    linked_count = Enum.count(choices, & &1["linked_screenplay_id"])
    total = length(choices)

    assigns =
      assigns
      |> assign(:choices, choices)
      |> assign(:all_linked, linked_count > 0 and linked_count == total)
      |> assign(:some_unlinked, linked_count > 0 and linked_count < total)
      |> assign(:has_unlinked, total > 0 and linked_count < total)

    ~H"""
    <div class="sp-interactive-block sp-interactive-response">
      <div class="sp-interactive-header">
        <.icon name="list" class="size-4 opacity-60" />
        <span class="sp-interactive-label">{gettext("Responses")}</span>
        <.icon :if={@all_linked} name="check-circle" class="size-3.5 text-success" />
        <.icon :if={@some_unlinked} name="alert-circle" class="size-3.5 text-warning" />
        <button
          :if={@can_edit && @has_unlinked}
          type="button"
          class="sp-generate-pages-btn"
          phx-click="generate_all_linked_pages"
          phx-value-element-id={@element.id}
          title={gettext("Create pages for all unlinked choices")}
        >
          <.icon name="files" class="size-3" />
          {gettext("Generate pages")}
        </button>
      </div>
      <div :if={@choices == [] && !@can_edit} class="sp-choice-empty">
        {gettext("No choices defined")}
      </div>
      <div :if={@choices == [] && @can_edit} class="sp-choice-empty">
        {gettext("No choices yet. Add one below.")}
      </div>
      <div :for={{choice, idx} <- Enum.with_index(@choices)} class="sp-choice-group">
        <div class="sp-choice-row">
          <span class="sp-choice-number">{idx + 1}.</span>
          <input
            :if={@can_edit}
            type="text"
            value={choice["text"]}
            placeholder={gettext("Choice text...")}
            class="sp-choice-input"
            phx-blur="update_response_choice_text"
            phx-value-element-id={@element.id}
            phx-value-choice-id={choice["id"]}
          />
          <span :if={!@can_edit} class="sp-choice-text">{choice["text"]}</span>
          <div :if={choice["linked_screenplay_id"]} class="sp-choice-link">
            <button
              type="button"
              class="sp-choice-page-link"
              phx-click="navigate_to_linked_page"
              phx-value-element-id={@element.id}
              phx-value-choice-id={choice["id"]}
              title={gettext("Go to linked page")}
            >
              <.icon name="file-text" class="size-3" />
              <span class="sp-choice-page-name">{linked_page_name(choice, @linked_pages)}</span>
            </button>
            <button
              :if={@can_edit}
              type="button"
              class="sp-choice-unlink"
              phx-click="unlink_choice_screenplay"
              phx-value-element-id={@element.id}
              phx-value-choice-id={choice["id"]}
              title={gettext("Unlink page")}
            >
              <.icon name="unlink" class="size-3" />
            </button>
          </div>
          <button
            :if={@can_edit && !choice["linked_screenplay_id"]}
            type="button"
            class="sp-choice-create-page"
            phx-click="create_linked_page"
            phx-value-element-id={@element.id}
            phx-value-choice-id={choice["id"]}
            title={gettext("Create page for this choice")}
          >
            <.icon name="file-plus" class="size-3" />
          </button>
          <button
            :if={@can_edit}
            type="button"
            class={["sp-choice-toggle", choice["condition"] && "sp-choice-toggle-active"]}
            title={gettext("Toggle condition")}
            phx-click="toggle_choice_condition"
            phx-value-element-id={@element.id}
            phx-value-choice-id={choice["id"]}
          >
            <.icon name="git-branch" class="size-3" />
          </button>
          <button
            :if={@can_edit}
            type="button"
            class={["sp-choice-toggle", choice["instruction"] && "sp-choice-toggle-active"]}
            title={gettext("Toggle instruction")}
            phx-click="toggle_choice_instruction"
            phx-value-element-id={@element.id}
            phx-value-choice-id={choice["id"]}
          >
            <.icon name="zap" class="size-3" />
          </button>
          <button
            :if={@can_edit}
            type="button"
            class="sp-choice-remove"
            phx-click="remove_response_choice"
            phx-value-element-id={@element.id}
            phx-value-choice-id={choice["id"]}
          >
            <.icon name="x" class="size-3" />
          </button>
        </div>
        <div :if={choice["condition"]} class="sp-choice-extras">
          <.condition_builder
            id={"sp-choice-cond-#{choice["id"]}"}
            condition={choice["condition"]}
            variables={@variables}
            can_edit={@can_edit}
            context={%{"element-id" => to_string(@element.id), "choice-id" => choice["id"]}}
            event_name="update_response_choice_condition"
          />
        </div>
        <div :if={choice["instruction"]} class="sp-choice-extras">
          <.instruction_builder
            id={"sp-choice-instr-#{choice["id"]}"}
            assignments={choice["instruction"]}
            variables={@variables}
            can_edit={@can_edit}
            context={%{"element-id" => to_string(@element.id), "choice-id" => choice["id"]}}
            event_name="update_response_choice_instruction"
          />
        </div>
      </div>
      <button
        :if={@can_edit}
        type="button"
        class="sp-add-choice"
        phx-click="add_response_choice"
        phx-value-element-id={@element.id}
      >
        <.icon name="plus" class="size-3" />
        {gettext("Add choice")}
      </button>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Interactive / flow-marker / stub blocks (Phase 5)
  # ---------------------------------------------------------------------------

  defp render_block(%{element: %{type: type}} = assigns) when type in @stub_types do
    assigns = assign(assigns, :type_label, humanize_type(type))

    ~H"""
    <div class="sp-stub">
      <span class="sp-stub-badge">{@type_label}</span>
    </div>
    """
  end

  # Fallback for unknown types
  defp render_block(assigns) do
    ~H"""
    <div class="sp-block">{@element.content}</div>
    """
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp placeholder_for("scene_heading"), do: gettext("INT. LOCATION - TIME")
  defp placeholder_for("action"), do: gettext("Describe the action...")
  defp placeholder_for("character"), do: gettext("CHARACTER NAME")
  defp placeholder_for("dialogue"), do: gettext("Dialogue text...")
  defp placeholder_for("parenthetical"), do: gettext("(acting direction)")
  defp placeholder_for("transition"), do: gettext("CUT TO:")
  defp placeholder_for("note"), do: gettext("Note...")
  defp placeholder_for("section"), do: gettext("Section heading")
  defp placeholder_for(_), do: ""

  defp linked_page_name(choice, linked_pages) do
    case Map.get(linked_pages, choice["linked_screenplay_id"]) do
      nil -> gettext("(deleted)")
      name -> name
    end
  end

  defp empty?(%{content: nil}), do: true
  defp empty?(%{content: ""}), do: true
  defp empty?(_), do: false

  defp humanize_type(type) do
    type
    |> String.replace("_", " ")
    |> String.split(" ")
    |> Enum.map_join(" ", &String.capitalize/1)
  end
end

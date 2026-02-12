defmodule StoryarnWeb.Components.Screenplay.ElementRenderer do
  @moduledoc """
  Renders screenplay elements with industry-standard formatting.

  Dispatches to per-type block functions based on element type.
  Includes inline builders for interactive types (conditional,
  instruction, response) and badge stubs for flow-marker types.

  Note: Text elements (action, dialogue, etc.) are now handled by the unified
  TipTap editor (`ScreenplayEditor` hook). This component is only used for
  interactive blocks in edit mode and all elements in read mode. The TipTap
  text block rendering paths and placeholder helpers will be removed in Phase 2.
  """

  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext

  alias Storyarn.Screenplays.CharacterExtension
  alias Storyarn.Screenplays.ContentUtils
  alias Storyarn.Screenplays.ScreenplayElement

  import Phoenix.HTML, only: [raw: 1]
  import StoryarnWeb.Components.CoreComponents, only: [icon: 1]
  import StoryarnWeb.Components.ConditionBuilder
  import StoryarnWeb.Components.InstructionBuilder

  @editable_types ScreenplayElement.keyboard_types()
  @tiptap_types ScreenplayElement.tiptap_types()
  @stub_types ~w(hub_marker jump_marker title_page)

  attr :element, :map, required: true
  attr :can_edit, :boolean, default: false
  attr :variables, :list, default: []
  attr :linked_pages, :map, default: %{}
  attr :continuations, :any, default: MapSet.new()
  attr :sheets_map, :map, default: %{}

  def element_renderer(assigns) do
    assigns = compute_element_flags(assigns)

    ~H"""
    <div
      id={"sp-el-#{@element.id}-#{@element.type}#{if @sheet_ref, do: "-ref", else: ""}"}
      class={[
        "screenplay-element",
        "sp-#{@element.type}",
        empty?(@element) && "sp-empty",
        left_transition?(@element) && "sp-transition-left"
      ]}
      phx-hook={@hook}
      phx-update={@ignore_update && "ignore"}
      data-element-id={@element.id}
      data-element-type={@element.type}
      data-position={@element.position}
    >
      {render_block(assigns)}
      <span
        :if={@element.type == "character" and show_contd?(@element, @continuations)}
        class="sp-contd"
      >(CONT'D)</span>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Character with sheet reference — non-editable name from sheet
  # ---------------------------------------------------------------------------

  defp render_block(
         %{element: %{type: "character", data: %{"sheet_id" => sheet_id}}, can_edit: true} =
           assigns
       )
       when not is_nil(sheet_id) do
    int_id = safe_int(sheet_id)
    sheet = Map.get(assigns.sheets_map, int_id)
    assigns = assign(assigns, :sheet, sheet)
    assigns = assign(assigns, :sheet_name, if(sheet, do: String.upcase(sheet.name), else: "???"))

    ~H"""
    <div class="sp-block sp-character-ref">
      <span class="sp-character-ref-name">{@sheet_name}</span>
      <button
        type="button"
        class="sp-character-nav"
        phx-click="navigate_to_sheet"
        phx-value-sheet-id={@element.data["sheet_id"]}
        title={gettext("Go to sheet")}
      >
        <.icon name="external-link" class="size-3" />
      </button>
      <button
        type="button"
        class="sp-character-clear"
        phx-click="clear_character_sheet"
        phx-value-id={@element.id}
        title={gettext("Remove sheet reference")}
      >
        <.icon name="x" class="size-3" />
      </button>
    </div>
    """
  end

  # Character with sheet reference — read-only display
  defp render_block(
         %{element: %{type: "character", data: %{"sheet_id" => sheet_id}}} = assigns
       )
       when not is_nil(sheet_id) do
    int_id = safe_int(sheet_id)
    sheet = Map.get(assigns.sheets_map, int_id)
    assigns = assign(assigns, :sheet_name, if(sheet, do: String.upcase(sheet.name), else: "???"))

    ~H"""
    <div class="sp-block sp-character-ref">
      <span class="sp-character-ref-name">{@sheet_name}</span>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # TipTap-powered text blocks (editable) — dialogue, action, etc.
  # ---------------------------------------------------------------------------

  defp render_block(%{element: %{type: type}, tiptap: true, can_edit: true} = assigns)
       when type in @tiptap_types do
    assigns = assign(assigns, :placeholder, placeholder_for(type))

    ~H"""
    <div
      id={"sp-tiptap-#{@element.id}"}
      class="sp-tiptap-container"
      phx-update="ignore"
      data-content={@element.content || ""}
      data-can-edit="true"
      data-placeholder={@placeholder}
    >
    </div>
    """
  end

  # TipTap types (read-only) — render HTML content directly
  defp render_block(%{element: %{type: type}} = assigns) when type in @tiptap_types do
    ~H"""
    <div class="sp-block sp-tiptap-readonly">{raw(ContentUtils.sanitize_html(@element.content))}</div>
    """
  end

  # ---------------------------------------------------------------------------
  # Standard blocks — character (plain contenteditable)
  # ---------------------------------------------------------------------------

  defp render_block(%{element: %{type: "character"}, can_edit: true} = assigns) do
    assigns = assign(assigns, :placeholder, placeholder_for("character"))

    ~H"""
    <div class="sp-block" contenteditable="true" data-placeholder={@placeholder}>{@element.content}</div>
    """
  end

  defp render_block(%{element: %{type: "character"}} = assigns) do
    ~H"""
    <div class="sp-block">{@element.content}</div>
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
      <.interactive_header icon="git-branch" label={gettext("Condition")} can_edit={@can_edit} element_id={@element.id} />
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
      <.interactive_header icon="zap" label={gettext("Instruction")} can_edit={@can_edit} element_id={@element.id} />
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
      <.interactive_header icon="list" label={gettext("Responses")} can_edit={@can_edit} element_id={@element.id}>
        <:actions>
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
        </:actions>
      </.interactive_header>
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
  # Dual dialogue block — two speakers side by side
  # ---------------------------------------------------------------------------

  defp render_block(%{element: %{type: "dual_dialogue"}} = assigns) do
    data = assigns.element.data || %{}

    assigns =
      assigns
      |> assign(:left, data["left"] || %{})
      |> assign(:right, data["right"] || %{})

    ~H"""
    <div class="sp-dual-dialogue-wrapper">
      <button
        :if={@can_edit}
        type="button"
        class="sp-interactive-delete sp-dual-delete"
        phx-click="delete_element"
        phx-value-id={@element.id}
        title={gettext("Delete block")}
      >
        <.icon name="trash-2" class="size-3.5" />
      </button>
      <div class="sp-dual-dialogue">
        <.dual_column side="left" data={@left} element={@element} can_edit={@can_edit} />
        <.dual_column side="right" data={@right} element={@element} can_edit={@can_edit} />
      </div>
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
  # Dual dialogue sub-component
  # ---------------------------------------------------------------------------

  attr :side, :string, required: true
  attr :data, :map, required: true
  attr :element, :map, required: true
  attr :can_edit, :boolean, required: true

  defp dual_column(assigns) do
    ~H"""
    <div class="sp-dual-column">
      <div class="sp-dual-character">
        <input
          :if={@can_edit}
          type="text"
          value={@data["character"]}
          placeholder={gettext("CHARACTER")}
          class="sp-dual-character-input"
          phx-blur="update_dual_dialogue"
          phx-value-element-id={@element.id}
          phx-value-side={@side}
          phx-value-field="character"
        />
        <span :if={!@can_edit} class="sp-dual-character-text">{@data["character"]}</span>
      </div>
      <div :if={@data["parenthetical"] != nil} class="sp-dual-parenthetical">
        <input
          :if={@can_edit}
          type="text"
          value={@data["parenthetical"]}
          placeholder={gettext("(direction)")}
          class="sp-dual-paren-input"
          phx-blur="update_dual_dialogue"
          phx-value-element-id={@element.id}
          phx-value-side={@side}
          phx-value-field="parenthetical"
        />
        <span :if={!@can_edit} class="sp-dual-paren-text">{@data["parenthetical"]}</span>
      </div>
      <button
        :if={@can_edit}
        type="button"
        class={["sp-dual-toggle-paren", @data["parenthetical"] != nil && "sp-dual-toggle-paren-active"]}
        phx-click="toggle_dual_parenthetical"
        phx-value-element-id={@element.id}
        phx-value-side={@side}
        title={gettext("Toggle parenthetical")}
      >
        <.icon name={if @data["parenthetical"] != nil, do: "minus", else: "plus"} class="size-3" />
      </button>
      <div class="sp-dual-dialogue-text">
        <textarea
          :if={@can_edit}
          placeholder={gettext("Dialogue...")}
          class="sp-dual-dialogue-input"
          phx-blur="update_dual_dialogue"
          phx-value-element-id={@element.id}
          phx-value-side={@side}
          phx-value-field="dialogue"
        >{@data["dialogue"]}</textarea>
        <span :if={!@can_edit} class="sp-dual-dialogue-readonly">{@data["dialogue"]}</span>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :can_edit, :boolean, required: true
  attr :element_id, :any, required: true
  slot :actions

  defp interactive_header(assigns) do
    ~H"""
    <div class="sp-interactive-header">
      <.icon name={@icon} class="size-4 opacity-60" />
      <span class="sp-interactive-label">{@label}</span>
      {render_slot(@actions)}
      <button
        :if={@can_edit}
        type="button"
        class="sp-interactive-delete"
        phx-click="delete_element"
        phx-value-id={@element_id}
        title={gettext("Delete block")}
      >
        <.icon name="trash-2" class="size-3.5" />
      </button>
    </div>
    """
  end

  defp compute_element_flags(assigns) do
    editable = assigns.can_edit and assigns.element.type in @editable_types
    sheet_ref? = sheet_ref?(assigns.element)
    tiptap? = editable and assigns.element.type in @tiptap_types
    hook = resolve_hook(editable, tiptap?)
    ignore_update = editable and not tiptap? and not sheet_ref?

    assigns
    |> assign(:editable, editable)
    |> assign(:sheet_ref, sheet_ref?)
    |> assign(:tiptap, tiptap?)
    |> assign(:hook, hook)
    |> assign(:ignore_update, ignore_update)
  end

  defp sheet_ref?(%{type: "character", data: %{"sheet_id" => id}}) when not is_nil(id), do: true
  defp sheet_ref?(_), do: false

  # Text elements are handled by the unified TipTap editor; per-element hooks removed.
  defp resolve_hook(_editable, _tiptap), do: nil

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

  defp safe_int(val) when is_integer(val), do: val

  defp safe_int(val) when is_binary(val) do
    case Integer.parse(val) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp safe_int(_), do: nil

  defp show_contd?(element, continuations) do
    MapSet.member?(continuations, element.id) and
      (sheet_ref?(element) or not CharacterExtension.has_contd?(element.content))
  end

  defp left_transition?(%{type: "transition", content: content}) when is_binary(content) do
    content |> String.trim() |> String.upcase() |> String.ends_with?("IN:")
  end

  defp left_transition?(_), do: false

  defp empty?(%{content: nil}), do: true
  defp empty?(%{content: ""}), do: true
  defp empty?(%{content: "<p></p>"}), do: true
  defp empty?(_), do: false

  defp humanize_type(type) do
    type
    |> String.replace("_", " ")
    |> String.split(" ")
    |> Enum.map_join(" ", &String.capitalize/1)
  end
end

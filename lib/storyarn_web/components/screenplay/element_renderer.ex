defmodule StoryarnWeb.Components.Screenplay.ElementRenderer do
  @moduledoc """
  Renders screenplay elements with industry-standard formatting.

  Dispatches to per-type block functions based on element type.
  Interactive and flow-marker types render as stubs (Phase 5).
  """

  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext

  @editable_types ~w(scene_heading action character dialogue parenthetical transition note section)
  @stub_types ~w(conditional instruction response dual_dialogue hub_marker jump_marker title_page)

  attr :element, :map, required: true
  attr :can_edit, :boolean, default: false

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

defmodule StoryarnWeb.Components.Screenplay.ElementRenderer do
  @moduledoc """
  Renders screenplay elements with industry-standard formatting (read mode only).

  All elements in edit mode are handled by the unified TipTap editor.
  This component is only used for read mode rendering via `visible_elements/2`.
  """

  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext

  alias Storyarn.Screenplays.CharacterExtension
  alias Storyarn.Screenplays.ContentUtils
  alias Storyarn.Screenplays.ScreenplayElement

  import Phoenix.HTML, only: [raw: 1]

  @tiptap_types ScreenplayElement.tiptap_types()

  attr :element, :map, required: true
  attr :continuations, :any, default: MapSet.new()
  attr :sheets_map, :map, default: %{}

  def element_renderer(assigns) do
    assigns =
      assigns
      |> assign(:sheet_ref, sheet_ref?(assigns.element))

    ~H"""
    <div
      id={"sp-el-#{@element.id}-#{@element.type}#{if @sheet_ref, do: "-ref", else: ""}"}
      class={[
        "screenplay-element",
        "sp-#{@element.type}",
        empty?(@element) && "sp-empty",
        left_transition?(@element) && "sp-transition-left"
      ]}
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
  # Character with sheet reference — read-only display
  # ---------------------------------------------------------------------------

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
  # TipTap types (read-only) — render HTML content directly
  # ---------------------------------------------------------------------------

  defp render_block(%{element: %{type: type}} = assigns) when type in @tiptap_types do
    ~H"""
    <div class="sp-block sp-tiptap-readonly">{raw(ContentUtils.sanitize_html(@element.content))}</div>
    """
  end

  # ---------------------------------------------------------------------------
  # Character (read-only)
  # ---------------------------------------------------------------------------

  defp render_block(%{element: %{type: "character"}} = assigns) do
    ~H"""
    <div class="sp-block">{@element.content}</div>
    """
  end

  # ---------------------------------------------------------------------------
  # Page break — visual separator
  # ---------------------------------------------------------------------------

  defp render_block(%{element: %{type: "page_break"}} = assigns) do
    ~H"""
    <div class="sp-page-break-line"></div>
    """
  end

  # ---------------------------------------------------------------------------
  # Dual dialogue block — read-only two speakers side by side
  # ---------------------------------------------------------------------------

  defp render_block(%{element: %{type: "dual_dialogue"}} = assigns) do
    data = assigns.element.data || %{}

    assigns =
      assigns
      |> assign(:left, data["left"] || %{})
      |> assign(:right, data["right"] || %{})

    ~H"""
    <div class="sp-dual-dialogue-wrapper">
      <div class="sp-dual-dialogue">
        <.dual_column side="left" data={@left} />
        <.dual_column side="right" data={@right} />
      </div>
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
  # Dual dialogue sub-component (read-only)
  # ---------------------------------------------------------------------------

  attr :side, :string, required: true
  attr :data, :map, required: true

  defp dual_column(assigns) do
    ~H"""
    <div class="sp-dual-column">
      <div class="sp-dual-character">
        <span class="sp-dual-character-text">{@data["character"]}</span>
      </div>
      <div :if={@data["parenthetical"] != nil} class="sp-dual-parenthetical">
        <span class="sp-dual-paren-text">{@data["parenthetical"]}</span>
      </div>
      <div class="sp-dual-dialogue-text">
        <span class="sp-dual-dialogue-readonly">{@data["dialogue"]}</span>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp sheet_ref?(%{type: "character", data: %{"sheet_id" => id}}) when not is_nil(id), do: true
  defp sheet_ref?(_), do: false

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

end

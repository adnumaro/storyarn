defmodule StoryarnWeb.FlowLive.Nodes.Annotation.Node do
  @moduledoc """
  Annotation node type definition.

  Annotations are free-floating sticky notes stored as FlowNode with
  type "annotation". They have no input/output pins and are not part
  of the dialogue flow — they serve as canvas documentation.

  Data: text (plain text), color (hex), font_size ("sm"|"md"|"lg").
  """

  use Gettext, backend: Storyarn.Gettext

  import Phoenix.Component, only: [assign: 3]

  # -- Type metadata --

  def type, do: "annotation"
  def icon_name, do: "sticky-note"
  def label, do: dgettext("flows", "Note")

  def default_data do
    %{
      "text" => "",
      "color" => "#fbbf24",
      "font_size" => "md"
    }
  end

  def extract_form_data(data) do
    Map.take(data, ["text", "color", "font_size"])
  end

  @doc "Selecting an annotation shows the annotation toolbar (not the node toolbar)."
  def on_select(_node, socket) do
    assign(socket, :editing_mode, :annotation)
  end

  @doc "Double-clicking an annotation triggers inline text editing on the JS side."
  def on_double_click(_node), do: :toolbar

  def duplicate_data_cleanup(data), do: data
end

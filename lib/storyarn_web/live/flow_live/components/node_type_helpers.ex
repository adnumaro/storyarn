defmodule StoryarnWeb.FlowLive.Components.NodeTypeHelpers do
  @moduledoc """
  Helper functions and components for flow node types.

  Provides:
  - `node_type_icon/1` - Component to render the appropriate icon for a node type
  - `node_type_label/1` - Returns the translated label for a node type
  - `default_node_data/1` - Returns the default data structure for a node type
  """

  use Phoenix.Component
  use Gettext, backend: StoryarnWeb.Gettext

  import StoryarnWeb.Components.CoreComponents, only: [icon: 1]

  @doc """
  Renders an icon for the given node type.

  ## Attributes

  * `:type` - Required. The node type string ("dialogue", "hub", "condition", "instruction", "jump")
  """
  attr :type, :string, required: true

  def node_type_icon(assigns) do
    icon =
      case assigns.type do
        "entry" -> "play"
        "exit" -> "square"
        "dialogue" -> "message-square"
        "hub" -> "git-merge"
        "condition" -> "git-branch"
        "instruction" -> "zap"
        "jump" -> "arrow-down-right"
        _ -> "circle"
      end

    assigns = assign(assigns, :icon, icon)

    ~H"""
    <.icon name={@icon} class="size-4" />
    """
  end

  @doc """
  Returns the translated label for a node type.

  ## Examples

      iex> node_type_label("dialogue")
      "Dialogue"
  """
  @spec node_type_label(String.t()) :: String.t()
  def node_type_label(type) do
    case type do
      "entry" -> gettext("Entry")
      "exit" -> gettext("Exit")
      "dialogue" -> gettext("Dialogue")
      "hub" -> gettext("Hub")
      "condition" -> gettext("Condition")
      "instruction" -> gettext("Instruction")
      "jump" -> gettext("Jump")
      _ -> type
    end
  end

  @doc """
  Returns the default data map for a given node type.

  ## Examples

      iex> default_node_data("dialogue")
      %{"speaker_page_id" => nil, "text" => "", "responses" => []}
  """
  @spec default_node_data(String.t()) :: map()
  def default_node_data(type) do
    case type do
      "entry" ->
        %{}

      "exit" ->
        %{"label" => ""}

      "dialogue" ->
        %{
          "speaker_page_id" => nil,
          "text" => "",
          "stage_directions" => "",
          "menu_text" => "",
          "audio_asset_id" => nil,
          "technical_id" => "",
          "localization_id" => generate_localization_id(),
          "responses" => []
        }

      "hub" ->
        %{"hub_id" => "", "color" => "purple"}

      "condition" ->
        %{"expression" => ""}

      "instruction" ->
        %{"action" => "", "parameters" => ""}

      "jump" ->
        %{"target_hub_id" => ""}

      _ ->
        %{}
    end
  end

  @doc """
  Generates a technical ID with format: {flow_slug}_{speaker}_{speaker_count}

  ## Examples

      iex> generate_technical_id("intro", "Old Merchant", 1)
      "intro_old_merchant_1"

      iex> generate_technical_id("main_quest", nil, 3)
      "main_quest_narrator_3"

      iex> generate_technical_id(nil, "Guard", 1)
      "dlg_guard_1"
  """
  @spec generate_technical_id(String.t() | nil, String.t() | nil, pos_integer()) :: String.t()
  def generate_technical_id(flow_slug, speaker_name, speaker_count) do
    flow_part = normalize_for_id(flow_slug || "")
    speaker_part = normalize_for_id(speaker_name || "")

    flow_part = if flow_part == "", do: "dlg", else: flow_part
    speaker_part = if speaker_part == "", do: "narrator", else: speaker_part

    "#{flow_part}_#{speaker_part}_#{speaker_count}"
  end

  @doc """
  Generates a localization ID following i18n best practices.

  Uses hierarchical naming: dialogue.{context}.{unique_id}
  """
  @spec generate_localization_id(String.t() | nil) :: String.t()
  def generate_localization_id(context \\ nil) do
    suffix = unique_suffix()

    case normalize_for_id(context || "") do
      "" -> "dialogue.#{suffix}"
      ctx -> "dialogue.#{ctx}.#{suffix}"
    end
  end

  # Generates a short unique suffix (6 chars hex)
  defp unique_suffix do
    :erlang.unique_integer([:positive])
    |> Integer.to_string(16)
    |> String.downcase()
    |> String.slice(0, 6)
  end

  @doc """
  Counts words in a text string, stripping HTML tags first.
  """
  @spec word_count(String.t() | nil) :: non_neg_integer()
  def word_count(nil), do: 0
  def word_count(""), do: 0

  def word_count(text) do
    text
    |> strip_html()
    |> String.split(~r/\s+/, trim: true)
    |> length()
  end

  # Normalizes a string for use in an ID (lowercase, alphanumeric + underscores)
  defp normalize_for_id(text) when is_binary(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "_")
    |> String.trim("_")
  end

  defp normalize_for_id(_), do: ""

  # Strips HTML tags from text
  defp strip_html(text) when is_binary(text) do
    text
    |> String.replace(~r/<[^>]+>/, " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp strip_html(_), do: ""
end

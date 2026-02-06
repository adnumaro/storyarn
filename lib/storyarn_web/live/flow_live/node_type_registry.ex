defmodule StoryarnWeb.FlowLive.NodeTypeRegistry do
  @moduledoc """
  Single source of truth for flow node type definitions.

  Centralizes type metadata (icons, labels, default data, form extraction)
  so that adding a new node type requires updating only this module.

  Consumers:
  - `NodeTypeHelpers` delegates icon_name, label, default_data
  - `FormHelpers` delegates extract_form_data
  """

  use Gettext, backend: StoryarnWeb.Gettext

  @types ~w(entry exit dialogue hub condition instruction jump)

  @doc "All known node types."
  @spec types() :: [String.t()]
  def types, do: @types

  @doc "Node types that users can add via the toolbar."
  @spec user_addable_types() :: [String.t()]
  def user_addable_types, do: @types -- ["entry"]

  @doc "Returns the Lucide icon name for a node type."
  @spec icon_name(String.t()) :: String.t()
  def icon_name("entry"), do: "play"
  def icon_name("exit"), do: "square"
  def icon_name("dialogue"), do: "message-square"
  def icon_name("hub"), do: "log-in"
  def icon_name("condition"), do: "git-branch"
  def icon_name("instruction"), do: "zap"
  def icon_name("jump"), do: "log-out"
  def icon_name(_), do: "circle"

  @doc "Returns the translated label for a node type."
  @spec label(String.t()) :: String.t()
  def label("entry"), do: gettext("Entry")
  def label("exit"), do: gettext("Exit")
  def label("dialogue"), do: gettext("Dialogue")
  def label("hub"), do: gettext("Hub")
  def label("condition"), do: gettext("Condition")
  def label("instruction"), do: gettext("Instruction")
  def label("jump"), do: gettext("Jump")
  def label(type), do: type

  @doc "Returns the default data map for a given node type."
  @spec default_data(String.t()) :: map()
  def default_data("entry"), do: %{}
  def default_data("exit"), do: %{"label" => "", "technical_id" => "", "is_success" => true}

  def default_data("dialogue") do
    %{
      "speaker_page_id" => nil,
      "text" => "",
      "stage_directions" => "",
      "menu_text" => "",
      "audio_asset_id" => nil,
      "technical_id" => "",
      "localization_id" => generate_localization_id(),
      "input_condition" => "",
      "output_instruction" => "",
      "responses" => []
    }
  end

  def default_data("hub"), do: %{"hub_id" => "", "label" => "", "color" => "purple"}

  def default_data("condition") do
    %{
      "condition" => %{"logic" => "all", "rules" => []},
      "switch_mode" => false
    }
  end

  def default_data("instruction"), do: %{"action" => "", "parameters" => ""}
  def default_data("jump"), do: %{"target_hub_id" => ""}
  def default_data(_), do: %{}

  @doc "Extracts form-compatible data from a node based on its type."
  @spec extract_form_data(String.t(), map()) :: map()
  def extract_form_data("dialogue", data) do
    %{
      "speaker_page_id" => data["speaker_page_id"] || "",
      "text" => data["text"] || "",
      "stage_directions" => data["stage_directions"] || "",
      "menu_text" => data["menu_text"] || "",
      "audio_asset_id" => data["audio_asset_id"],
      "technical_id" => data["technical_id"] || "",
      "localization_id" => data["localization_id"] || "",
      "input_condition" => data["input_condition"] || "",
      "output_instruction" => data["output_instruction"] || "",
      "responses" => data["responses"] || []
    }
  end

  def extract_form_data("hub", data) do
    %{
      "hub_id" => data["hub_id"] || "",
      "label" => data["label"] || "",
      "color" => data["color"] || "purple"
    }
  end

  def extract_form_data("condition", data) do
    %{
      "condition" => data["condition"] || %{"logic" => "all", "rules" => []},
      "switch_mode" => data["switch_mode"] || false
    }
  end

  def extract_form_data("instruction", data) do
    %{"action" => data["action"] || "", "parameters" => data["parameters"] || ""}
  end

  def extract_form_data("jump", data) do
    %{"target_hub_id" => data["target_hub_id"] || ""}
  end

  def extract_form_data("exit", data) do
    %{
      "label" => data["label"] || "",
      "technical_id" => data["technical_id"] || "",
      "is_success" => data["is_success"] != false
    }
  end

  def extract_form_data(_type, _data), do: %{}

  # Generates a localization ID (used in dialogue default_data)
  defp generate_localization_id do
    suffix =
      :erlang.unique_integer([:positive])
      |> Integer.to_string(16)
      |> String.downcase()
      |> String.slice(0, 6)

    "dialogue.#{suffix}"
  end
end

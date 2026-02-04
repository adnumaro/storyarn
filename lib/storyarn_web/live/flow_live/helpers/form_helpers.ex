defmodule StoryarnWeb.FlowLive.Helpers.FormHelpers do
  @moduledoc """
  Form building helpers for flow nodes and connections.
  """

  import Phoenix.Component, only: [to_form: 2]

  @doc """
  Builds a form from node data for the properties panel.
  """
  @spec node_data_to_form(map()) :: Phoenix.HTML.Form.t()
  def node_data_to_form(node) do
    data = extract_node_form_data(node.type, node.data)
    to_form(data, as: :node)
  end

  @doc """
  Builds a form from connection data for the properties panel.
  """
  @spec connection_data_to_form(map()) :: Phoenix.HTML.Form.t()
  def connection_data_to_form(connection) do
    data = %{
      "label" => connection.label || "",
      "condition" => connection.condition || "",
      "condition_order" => connection.condition_order || 0
    }

    to_form(data, as: :connection)
  end

  @doc """
  Extracts form-compatible data from a node based on its type.
  """
  @spec extract_node_form_data(String.t(), map()) :: map()
  def extract_node_form_data("dialogue", data) do
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

  def extract_node_form_data("hub", data) do
    %{"hub_id" => data["hub_id"] || "", "color" => data["color"] || "purple"}
  end

  def extract_node_form_data("condition", data) do
    %{
      "expression" => data["expression"] || "",
      "cases" => data["cases"] || []
    }
  end

  def extract_node_form_data("instruction", data) do
    %{"action" => data["action"] || "", "parameters" => data["parameters"] || ""}
  end

  def extract_node_form_data("jump", data) do
    %{"target_hub_id" => data["target_hub_id"] || ""}
  end

  def extract_node_form_data("exit", data) do
    %{"label" => data["label"] || ""}
  end

  def extract_node_form_data(_type, _data), do: %{}

  @doc """
  Builds a map of pages for the canvas (keyed by string ID).
  """
  @spec pages_map(list()) :: map()
  def pages_map(leaf_pages) do
    Map.new(leaf_pages, fn page ->
      avatar_url =
        case page.avatar_asset do
          %{url: url} when is_binary(url) -> url
          _ -> nil
        end

      {to_string(page.id), %{id: page.id, name: page.name, avatar_url: avatar_url}}
    end)
  end

  @doc """
  Extracts the name part from an email address.
  """
  @spec get_email_name(any()) :: String.t()
  def get_email_name(email) when is_binary(email) do
    email |> String.split("@") |> List.first()
  end

  def get_email_name(_), do: "Someone"
end

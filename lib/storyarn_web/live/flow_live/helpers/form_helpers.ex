defmodule StoryarnWeb.FlowLive.Helpers.FormHelpers do
  @moduledoc """
  Form building helpers for flow nodes.

  Form data extraction is delegated to `NodeTypeRegistry`.
  """

  import Phoenix.Component, only: [to_form: 2]

  alias StoryarnWeb.FlowLive.NodeTypeRegistry

  @doc """
  Builds a form from node data for the properties panel.
  """
  @spec node_data_to_form(map()) :: Phoenix.HTML.Form.t()
  def node_data_to_form(node) do
    data = NodeTypeRegistry.extract_form_data(node.type, node.data)
    to_form(data, as: :node)
  end

  @doc """
  Builds a map of sheets for the canvas (keyed by string ID).
  """
  @spec sheets_map(list()) :: map()
  def sheets_map(all_sheets) do
    Map.new(all_sheets, fn sheet ->
      avatar_url =
        case sheet.avatar_asset do
          %{url: url} when is_binary(url) -> url
          _ -> nil
        end

      {to_string(sheet.id),
       %{id: sheet.id, name: sheet.name, avatar_url: avatar_url, color: sheet.color}}
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

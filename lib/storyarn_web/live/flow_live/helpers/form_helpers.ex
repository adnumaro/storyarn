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
  Builds a map of pages for the canvas (keyed by string ID).
  """
  @spec pages_map(list()) :: map()
  def pages_map(all_pages) do
    Map.new(all_pages, fn page ->
      avatar_url =
        case page.avatar_asset do
          %{url: url} when is_binary(url) -> url
          _ -> nil
        end

      {to_string(page.id),
       %{id: page.id, name: page.name, avatar_url: avatar_url, color: page.color}}
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

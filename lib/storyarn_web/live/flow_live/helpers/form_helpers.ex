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

  Optionally accepts `gallery_by_sheet` — a map of `sheet_id => [%BlockGalleryImage{}]`
  to include gallery images per sheet for the image override picker.
  """
  @spec sheets_map(list(), map()) :: map()
  def sheets_map(all_sheets, gallery_by_sheet \\ %{}) do
    Map.new(all_sheets, fn sheet ->
      {to_string(sheet.id), build_sheet_entry(sheet, gallery_by_sheet)}
    end)
  end

  defp build_sheet_entry(sheet, gallery_by_sheet) do
    %{
      id: sheet.id,
      name: sheet.name,
      avatar_url: extract_asset_url(sheet.avatar_asset),
      banner_url: extract_asset_url(sheet.banner_asset),
      color: sheet.color,
      gallery_images: build_gallery_images(Map.get(gallery_by_sheet, sheet.id))
    }
  end

  defp extract_asset_url(%{url: url}) when is_binary(url), do: url
  defp extract_asset_url(_), do: nil

  defp build_gallery_images(nil), do: []

  defp build_gallery_images(images) do
    images
    |> Enum.map(fn gi ->
      %{id: gi.id, url: gi.asset && gi.asset.url, label: gi.label || (gi.asset && gi.asset.filename)}
    end)
    |> Enum.filter(& &1.url)
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

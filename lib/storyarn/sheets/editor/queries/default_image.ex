defmodule Storyarn.Sheets.Editor.Queries.DefaultImage do
  @moduledoc """
  Resolves the editor's display image fallback for a Sheet.

  The ordered policy is default avatar, banner, then first gallery image.
  """

  alias Storyarn.Sheets.Editor.Queries.Avatars
  alias Storyarn.Sheets.Editor.Queries.Galleries
  alias Storyarn.Sheets.Sheet
  alias Storyarn.Sheets.SheetAvatar

  def get(%Sheet{avatars: avatars} = sheet) when is_list(avatars) do
    case Enum.find(avatars, & &1.is_default) do
      %SheetAvatar{asset: asset} when not is_nil(asset) -> asset
      _other -> fallback(sheet)
    end
  end

  def get(%Sheet{} = sheet) do
    case Avatars.get_default(sheet.id) do
      %SheetAvatar{asset: asset} when not is_nil(asset) -> asset
      _other -> fallback(sheet)
    end
  end

  defp fallback(sheet) do
    if sheet.banner_asset_id do
      sheet.banner_asset
    else
      Galleries.get_first_for_sheet(sheet.id)
    end
  end
end

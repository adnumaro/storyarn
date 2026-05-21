defmodule StoryarnWeb.SheetLive.Handlers.GalleryHandlersTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AssetsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Repo
  alias Storyarn.Sheets

  setup :register_and_log_in_user

  setup %{user: user} do
    project = user |> project_fixture() |> Repo.preload(:workspace)
    sheet = sheet_fixture(project, %{name: "Gallery Sheet"})
    block = block_fixture(sheet, %{type: "gallery", config: %{"label" => "Gallery"}})
    asset = image_asset_fixture(project, user)

    url = ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}"

    %{asset: asset, block: block, project: project, sheet: sheet, url: url}
  end

  defp mount_sheet(conn, url) do
    {:ok, view, _html} = live(conn, url)
    await_async(view)
    view
  end

  describe "attach_gallery_image event" do
    test "adds an image to a gallery block", %{conn: conn, asset: asset, block: block, url: url} do
      view = mount_sheet(conn, url)

      render_hook(view, "attach_gallery_image", %{
        "block_id" => to_string(block.id),
        "asset_id" => asset.id
      })

      gallery_images = Sheets.list_gallery_images(block.id)
      assert Enum.map(gallery_images, & &1.asset_id) == [asset.id]
    end

    test "ignores non-gallery blocks", %{conn: conn, asset: asset, sheet: sheet, url: url} do
      block = block_fixture(sheet, %{type: "text"})
      view = mount_sheet(conn, url)

      render_hook(view, "attach_gallery_image", %{
        "block_id" => to_string(block.id),
        "asset_id" => asset.id
      })

      assert Sheets.list_gallery_images(block.id) == []
    end
  end
end

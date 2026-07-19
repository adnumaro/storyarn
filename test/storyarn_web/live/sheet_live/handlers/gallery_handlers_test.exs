defmodule StoryarnWeb.SheetLive.Handlers.GalleryHandlersTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AssetsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Phoenix.LiveView.Socket
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Sheets
  alias StoryarnWeb.SheetLive.Handlers.GalleryHandlers

  setup :register_and_log_in_user

  setup %{user: user} do
    project = user |> project_fixture() |> Repo.preload(:workspace)
    sheet = sheet_fixture(project, %{name: "Gallery Sheet"})
    block = block_fixture(sheet, %{type: "gallery", config: %{"label" => "Gallery"}})
    asset = image_asset_fixture(project, user)

    url = ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}"

    %{asset: asset, block: block, project: project, sheet: sheet, url: url, user: user}
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

  describe "reorder_gallery_images event" do
    test "does not mutate another block through forged block and image IDs", %{
      conn: conn,
      asset: asset,
      block: block,
      project: project,
      user: user,
      url: url
    } do
      local_asset = image_asset_fixture(project, user)
      {:ok, local_first} = Sheets.add_gallery_image(block, asset.id)
      {:ok, local_second} = Sheets.add_gallery_image(block, local_asset.id)

      other_sheet = sheet_fixture(project, %{name: "Other"})
      other_block = block_fixture(other_sheet, %{type: "gallery"})
      other_asset_1 = image_asset_fixture(project, user)
      other_asset_2 = image_asset_fixture(project, user)
      {:ok, foreign_first} = Sheets.add_gallery_image(other_block, other_asset_1.id)
      {:ok, foreign_second} = Sheets.add_gallery_image(other_block, other_asset_2.id)

      view = mount_sheet(conn, url)

      render_hook(view, "reorder_gallery_images", %{
        "block_id" => to_string(other_block.id),
        "ids" => [to_string(foreign_second.id), to_string(foreign_first.id)]
      })

      assert Enum.map(Sheets.list_gallery_images(other_block.id), & &1.id) == [
               foreign_first.id,
               foreign_second.id
             ]

      render_hook(view, "reorder_gallery_images", %{
        "block_id" => to_string(block.id),
        "ids" => [to_string(foreign_second.id), to_string(foreign_first.id)]
      })

      assert Enum.map(Sheets.list_gallery_images(block.id), & &1.id) == [
               local_first.id,
               local_second.id
             ]
    end
  end

  describe "failed gallery writes" do
    test "does not reload or broadcast a rejected non-image attachment", %{
      block: block,
      project: project,
      sheet: sheet,
      user: user
    } do
      audio = audio_asset_fixture(project, user)
      socket = handler_socket(project, sheet)
      helpers = tracking_helpers()

      assert {:noreply, _socket} =
               GalleryHandlers.handle_attach(
                 %{"block_id" => block.id, "asset_id" => audio.id},
                 socket,
                 helpers
               )

      refute_received :gallery_reload
      refute_received {:gallery_broadcast, _action}
      assert Sheets.list_gallery_images(block.id) == []
    end

    test "does not reload or broadcast an update under a trashed gallery", %{
      asset: asset,
      block: block,
      project: project,
      sheet: sheet
    } do
      {:ok, image} = Sheets.add_gallery_image(block, asset.id)

      block
      |> Ecto.Changeset.change(deleted_at: TimeHelpers.now())
      |> Repo.update!()

      socket = handler_socket(project, sheet)
      helpers = tracking_helpers()

      assert {:noreply, _socket} =
               GalleryHandlers.handle_update(
                 %{
                   "gallery_image_id" => image.id,
                   "field" => "label",
                   "value" => "Changed"
                 },
                 socket,
                 helpers
               )

      refute_received :gallery_reload
      refute_received {:gallery_broadcast, _action}
      assert Sheets.get_gallery_image(image.id).label == nil
    end
  end

  defp handler_socket(project, sheet) do
    %Socket{
      assigns: %{
        __changed__: %{},
        flash: %{},
        membership: %{role: "owner"},
        project: project,
        sheet: sheet
      }
    }
  end

  defp tracking_helpers do
    parent = self()

    %{
      parse_id: fn
        id when is_integer(id) -> id
        id when is_binary(id) -> String.to_integer(id)
      end,
      reload_blocks: fn socket ->
        send(parent, :gallery_reload)
        socket
      end,
      broadcast: fn socket, action ->
        send(parent, {:gallery_broadcast, action})
        socket
      end
    }
  end
end

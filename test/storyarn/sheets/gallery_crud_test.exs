defmodule Storyarn.Sheets.GalleryCrudTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Sheets

  setup do
    user = user_fixture()
    project = project_fixture(user)
    sheet = sheet_fixture(project)
    block = block_fixture(sheet, %{type: "gallery"})

    assets =
      Enum.map(1..4, fn index ->
        image_asset_fixture(project, user, %{filename: "gallery-#{index}.png"})
      end)

    %{assets: assets, block: block, project: project, sheet: sheet, user: user}
  end

  describe "add_gallery_image/2" do
    test "rejects same-project non-image assets for single and batch writes", %{
      block: block,
      project: project,
      user: user
    } do
      first_audio = audio_asset_fixture(project, user)
      second_audio = audio_asset_fixture(project, user)

      assert {:error, {:invalid_asset_content_type, :gallery_asset_id, first_id}} =
               Sheets.add_gallery_image(block, first_audio.id)

      assert first_id == first_audio.id

      assert {:error, {:invalid_asset_content_type, :gallery_asset_id, invalid_id}} =
               Sheets.add_gallery_images(block, [first_audio.id, second_audio.id])

      assert invalid_id in [first_audio.id, second_audio.id]
      assert Sheets.list_gallery_images(block.id) == []
    end
  end

  describe "update_gallery_image/2" do
    test "updates a persisted image in an active gallery", %{assets: assets, block: block} do
      [image] = add_images(block, [hd(assets)])

      assert {:ok, updated} =
               Sheets.update_gallery_image(image, %{
                 label: "Portrait",
                 description: "Primary portrait"
               })

      assert updated.label == "Portrait"
      assert updated.description == "Primary portrait"
    end

    test "rejects a forged block owner without mutation", %{
      assets: assets,
      block: block,
      project: project
    } do
      [local] = add_images(block, [hd(assets)])
      other_sheet = sheet_fixture(project, %{name: "Other"})
      other_block = block_fixture(other_sheet, %{type: "gallery"})
      [foreign] = add_images(other_block, [Enum.at(assets, 1)])

      assert {:error, :not_found} =
               Sheets.update_gallery_image(
                 %{foreign | block_id: block.id},
                 %{label: "Forged"}
               )

      assert Sheets.get_gallery_image(local.id).label == nil
      assert Sheets.get_gallery_image(foreign.id).label == nil
    end

    test "rejects updates when the gallery block or sheet is in trash", %{
      assets: assets,
      block: block,
      sheet: sheet
    } do
      [image] = add_images(block, [hd(assets)])

      block
      |> Ecto.Changeset.change(deleted_at: TimeHelpers.now())
      |> Repo.update!()

      assert {:error, :gallery_not_active} =
               Sheets.update_gallery_image(image, %{label: "Changed"})

      assert Sheets.get_gallery_image(image.id).label == nil

      block
      |> Ecto.Changeset.change(deleted_at: nil)
      |> Repo.update!()

      sheet
      |> Ecto.Changeset.change(deleted_at: TimeHelpers.now())
      |> Repo.update!()

      assert {:error, :gallery_not_active} =
               Sheets.update_gallery_image(image, %{label: "Changed"})

      assert Sheets.get_gallery_image(image.id).label == nil
    end
  end

  describe "remove_gallery_image/2" do
    test "rejects foreign ownership without deleting the image", %{
      assets: assets,
      project: project,
      sheet: sheet
    } do
      other_sheet = sheet_fixture(project, %{name: "Other"})
      other_block = block_fixture(other_sheet, %{type: "gallery"})
      [foreign] = add_images(other_block, [hd(assets)])

      assert {:error, :not_found} =
               Sheets.remove_gallery_image(sheet.id, foreign.id)

      assert Sheets.get_gallery_image(foreign.id)
    end

    test "rejects deletion when the gallery block is in trash", %{
      assets: assets,
      block: block,
      sheet: sheet
    } do
      [image] = add_images(block, [hd(assets)])

      block
      |> Ecto.Changeset.change(deleted_at: TimeHelpers.now())
      |> Repo.update!()

      assert {:error, :gallery_not_active} =
               Sheets.remove_gallery_image(sheet.id, image.id)

      assert Sheets.get_gallery_image(image.id)
    end

    test "rejects deletion when the gallery sheet is in trash", %{
      assets: assets,
      block: block,
      sheet: sheet
    } do
      [image] = add_images(block, [hd(assets)])

      sheet
      |> Ecto.Changeset.change(deleted_at: TimeHelpers.now())
      |> Repo.update!()

      assert {:error, :gallery_not_active} =
               Sheets.remove_gallery_image(sheet.id, image.id)

      assert Sheets.get_gallery_image(image.id)
    end
  end

  describe "reorder_gallery_images/2" do
    test "reorders the exact image set", %{assets: assets, block: block} do
      [first, second, third] = add_images(block, Enum.take(assets, 3))

      assert {:ok, :ok} =
               Sheets.reorder_gallery_images(block.id, [
                 third.id,
                 first.id,
                 second.id
               ])

      assert Enum.map(Sheets.list_gallery_images(block.id), & &1.id) == [
               third.id,
               first.id,
               second.id
             ]
    end

    test "rejects incomplete, duplicate, malformed, and foreign sets atomically", %{
      assets: assets,
      block: block,
      project: project
    } do
      [first, second] = add_images(block, Enum.take(assets, 2))
      other_sheet = sheet_fixture(project, %{name: "Other"})
      other_block = block_fixture(other_sheet, %{type: "gallery"})
      [foreign] = add_images(other_block, [Enum.at(assets, 2)])
      original = image_positions(block.id)

      invalid_payloads = [
        [second.id],
        [second.id, second.id],
        [second.id, foreign.id],
        [second.id, first.id, "invalid"],
        [second.id, first.id, 0]
      ]

      Enum.each(invalid_payloads, fn payload ->
        assert {:error, {:invalid_gallery_reorder, ^payload}} =
                 Sheets.reorder_gallery_images(block.id, payload)

        assert image_positions(block.id) == original
        assert image_positions(other_block.id) == %{foreign.id => 0}
      end)
    end

    test "rejects a gallery whose block is in trash without mutation", %{
      assets: assets,
      block: block
    } do
      [first, second] = add_images(block, Enum.take(assets, 2))
      original = image_positions(block.id)

      block
      |> Ecto.Changeset.change(deleted_at: TimeHelpers.now())
      |> Repo.update!()

      assert {:error, :gallery_not_active} =
               Sheets.reorder_gallery_images(block.id, [second.id, first.id])

      assert image_positions(block.id) == original
    end

    test "rejects a gallery whose sheet is in trash without mutation", %{
      assets: assets,
      block: block,
      sheet: sheet
    } do
      [first, second] = add_images(block, Enum.take(assets, 2))
      original = image_positions(block.id)

      sheet
      |> Ecto.Changeset.change(deleted_at: TimeHelpers.now())
      |> Repo.update!()

      assert {:error, :gallery_not_active} =
               Sheets.reorder_gallery_images(block.id, [second.id, first.id])

      assert image_positions(block.id) == original
    end
  end

  defp add_images(block, assets) do
    Enum.map(assets, fn asset ->
      {:ok, image} = Sheets.add_gallery_image(block, asset.id)
      image
    end)
  end

  defp image_positions(block_id) do
    block_id
    |> Sheets.list_gallery_images()
    |> Map.new(&{&1.id, &1.position})
  end
end

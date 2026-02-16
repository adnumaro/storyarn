defmodule Storyarn.AssetsTest do
  use Storyarn.DataCase

  alias Storyarn.Assets
  alias Storyarn.Assets.Asset

  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.ProjectsFixtures

  describe "assets" do
    setup do
      user = user_fixture()
      project = project_fixture(user)
      %{project: project, user: user}
    end

    test "list_assets/2 returns all assets for a project", %{project: project, user: user} do
      asset = asset_fixture(project, user)
      assets = Assets.list_assets(project.id)

      assert length(assets) == 1
      assert hd(assets).id == asset.id
    end

    test "list_assets/2 filters by content_type", %{project: project, user: user} do
      _image = image_asset_fixture(project, user)
      audio = audio_asset_fixture(project, user)

      assets = Assets.list_assets(project.id, content_type: "audio/")

      assert length(assets) == 1
      assert hd(assets).id == audio.id
    end

    test "list_assets/2 filters images only", %{project: project, user: user} do
      image = image_asset_fixture(project, user)
      _audio = audio_asset_fixture(project, user)

      assets = Assets.list_assets(project.id, images_only: true)

      assert length(assets) == 1
      assert hd(assets).id == image.id
    end

    test "list_assets/2 searches by filename", %{project: project, user: user} do
      _asset1 = asset_fixture(project, user, %{filename: "hero_portrait.jpg"})
      asset2 = asset_fixture(project, user, %{filename: "villain_portrait.png"})

      assets = Assets.list_assets(project.id, search: "villain")

      assert length(assets) == 1
      assert hd(assets).id == asset2.id
    end

    test "list_assets/2 with empty search returns all", %{project: project, user: user} do
      _asset = asset_fixture(project, user)

      assets = Assets.list_assets(project.id, search: "")
      assert length(assets) == 1
    end

    test "get_asset/2 returns asset by id", %{project: project, user: user} do
      asset = asset_fixture(project, user)

      assert found = Assets.get_asset(project.id, asset.id)
      assert found.id == asset.id
    end

    test "get_asset/2 returns nil for wrong project", %{user: user} do
      other_project = project_fixture()
      asset = asset_fixture(other_project, user)

      another_project = project_fixture()
      assert Assets.get_asset(another_project.id, asset.id) == nil
    end

    test "get_asset_by_key/2 returns asset by storage key", %{project: project, user: user} do
      asset = asset_fixture(project, user)

      assert found = Assets.get_asset_by_key(project.id, asset.key)
      assert found.id == asset.id
    end

    test "get_asset_by_key/2 returns nil for unknown key", %{project: project} do
      assert Assets.get_asset_by_key(project.id, "unknown/key.jpg") == nil
    end

    test "create_asset/3 creates an asset", %{project: project, user: user} do
      attrs = %{
        filename: "test.jpg",
        content_type: "image/jpeg",
        size: 5000,
        key: "projects/#{project.id}/assets/#{Ecto.UUID.generate()}/test.jpg",
        url: "/uploads/projects/#{project.id}/assets/test.jpg"
      }

      assert {:ok, asset} = Assets.create_asset(project, user, attrs)
      assert asset.filename == "test.jpg"
      assert asset.content_type == "image/jpeg"
      assert asset.size == 5000
      assert asset.project_id == project.id
      assert asset.uploaded_by_id == user.id
    end

    test "create_asset/3 validates required fields", %{project: project, user: user} do
      assert {:error, changeset} = Assets.create_asset(project, user, %{})
      assert "can't be blank" in errors_on(changeset).filename
      assert "can't be blank" in errors_on(changeset).content_type
      assert "can't be blank" in errors_on(changeset).key
    end

    test "create_asset/3 validates content_type", %{project: project, user: user} do
      attrs = valid_asset_attributes(%{content_type: "application/x-malware"})

      assert {:error, changeset} = Assets.create_asset(project, user, attrs)
      assert errors_on(changeset).content_type != []
    end

    test "create_asset/3 validates file size", %{project: project, user: user} do
      attrs = valid_asset_attributes(%{size: -100})

      assert {:error, changeset} = Assets.create_asset(project, user, attrs)
      assert errors_on(changeset).size != []
    end

    test "create_asset/3 enforces unique key per project", %{project: project, user: user} do
      key = "projects/#{project.id}/assets/#{Ecto.UUID.generate()}/unique.jpg"
      _asset = asset_fixture(project, user, %{key: key})

      attrs = valid_asset_attributes(%{key: key})

      assert {:error, changeset} = Assets.create_asset(project, user, attrs)
      assert "has already been taken" in errors_on(changeset).key
    end

    test "create_asset/2 creates asset without user", %{project: project} do
      attrs = valid_asset_attributes()

      assert {:ok, asset} = Assets.create_asset(project, attrs)
      assert asset.filename != nil
      assert asset.uploaded_by_id == nil
    end

    test "update_asset/2 updates an asset", %{project: project, user: user} do
      asset = asset_fixture(project, user)

      assert {:ok, updated} = Assets.update_asset(asset, %{metadata: %{"width" => 1024}})
      assert updated.metadata == %{"width" => 1024}
    end

    test "delete_asset/1 deletes an asset", %{project: project, user: user} do
      asset = asset_fixture(project, user)

      assert {:ok, _} = Assets.delete_asset(asset)
      assert Assets.get_asset(project.id, asset.id) == nil
    end

    test "change_asset/2 returns a changeset", %{project: project, user: user} do
      asset = asset_fixture(project, user)

      assert %Ecto.Changeset{} = Assets.change_asset(asset)
    end

    test "count_assets_by_type/1 returns counts grouped by type", %{project: project, user: user} do
      _image1 = image_asset_fixture(project, user)
      _image2 = image_asset_fixture(project, user)
      _audio = audio_asset_fixture(project, user)

      counts = Assets.count_assets_by_type(project.id)

      assert counts["image"] == 2
      assert counts["audio"] == 1
    end

    test "total_storage_size/1 returns total size", %{project: project, user: user} do
      _asset1 = asset_fixture(project, user, %{size: 1000})
      _asset2 = asset_fixture(project, user, %{size: 2000})

      assert Assets.total_storage_size(project.id) == 3000
    end

    test "total_storage_size/1 returns 0 for empty project", %{project: project} do
      assert Assets.total_storage_size(project.id) == 0
    end
  end

  describe "generate_key/2" do
    test "generates a unique storage key" do
      project = project_fixture()
      filename = "test.jpg"

      key = Assets.generate_key(project, filename)

      assert String.starts_with?(key, "projects/#{project.id}/assets/")
      assert String.ends_with?(key, "/test.jpg")
    end

    test "preserves file extension" do
      project = project_fixture()

      assert String.ends_with?(Assets.generate_key(project, "file.png"), ".png")
      assert String.ends_with?(Assets.generate_key(project, "file.jpeg"), ".jpeg")
      assert String.ends_with?(Assets.generate_key(project, "file.gif"), ".gif")
    end

    test "sanitizes filename" do
      project = project_fixture()

      key = Assets.generate_key(project, "Hello World!.jpg")
      assert String.ends_with?(key, "/hello_world_.jpg")
    end
  end

  describe "thumbnail_key/1" do
    test "generates thumbnail key from original key" do
      key = "projects/abc/assets/123/image.jpg"

      thumb_key = Assets.thumbnail_key(key)

      assert thumb_key == "projects/abc/thumbnails/123/image.jpg"
    end
  end

  describe "get_asset_usages/2" do
    setup do
      user = user_fixture()
      project = project_fixture(user)
      %{project: project, user: user}
    end

    test "returns flow node usages for audio assets", %{project: project, user: user} do
      import Storyarn.FlowsFixtures

      audio = audio_asset_fixture(project, user)
      flow = flow_fixture(project, %{name: "Intro Flow"})

      node_fixture(flow, %{
        type: "dialogue",
        data: %{"audio_asset_id" => audio.id, "text" => "Hello"}
      })

      usages = Assets.get_asset_usages(project.id, audio.id)

      assert length(usages.flow_nodes) == 1
      assert hd(usages.flow_nodes).flow_name == "Intro Flow"
    end

    test "returns sheet avatar usages", %{project: project, user: user} do
      import Storyarn.SheetsFixtures

      image = image_asset_fixture(project, user)
      sheet = sheet_fixture(project, %{name: "Hero", avatar_asset_id: image.id})

      usages = Assets.get_asset_usages(project.id, image.id)

      assert length(usages.sheet_avatars) == 1
      assert hd(usages.sheet_avatars).id == sheet.id
    end

    test "returns sheet banner usages", %{project: project, user: user} do
      import Storyarn.SheetsFixtures

      image = image_asset_fixture(project, user)
      sheet = sheet_fixture(project, %{name: "Hero", banner_asset_id: image.id})

      usages = Assets.get_asset_usages(project.id, image.id)

      assert length(usages.sheet_banners) == 1
      assert hd(usages.sheet_banners).id == sheet.id
    end

    test "returns empty when asset is unused", %{project: project, user: user} do
      asset = asset_fixture(project, user)

      usages = Assets.get_asset_usages(project.id, asset.id)

      assert usages.flow_nodes == []
      assert usages.sheet_avatars == []
      assert usages.sheet_banners == []
    end

    test "excludes soft-deleted nodes", %{project: project, user: user} do
      import Storyarn.FlowsFixtures

      audio = audio_asset_fixture(project, user)
      flow = flow_fixture(project)

      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"audio_asset_id" => audio.id, "text" => "Hello"}
        })

      # Soft-delete the node
      Storyarn.Flows.FlowNode.soft_delete_changeset(node)
      |> Storyarn.Repo.update!()

      usages = Assets.get_asset_usages(project.id, audio.id)

      assert usages.flow_nodes == []
    end

    test "excludes soft-deleted sheets", %{project: project, user: user} do
      import Storyarn.SheetsFixtures

      image = image_asset_fixture(project, user)
      sheet = sheet_fixture(project, %{name: "Hero", avatar_asset_id: image.id})

      # Soft-delete the sheet via raw changeset
      Ecto.Changeset.change(sheet, deleted_at: DateTime.utc_now() |> DateTime.truncate(:second))
      |> Storyarn.Repo.update!()

      usages = Assets.get_asset_usages(project.id, image.id)

      assert usages.sheet_avatars == []
    end
  end

  describe "Asset schema" do
    test "image?/1 returns true for image content types" do
      assert Asset.image?(%Asset{content_type: "image/jpeg"})
      assert Asset.image?(%Asset{content_type: "image/png"})
      assert Asset.image?(%Asset{content_type: "image/gif"})
      assert Asset.image?(%Asset{content_type: "image/webp"})
      refute Asset.image?(%Asset{content_type: "audio/mpeg"})
      refute Asset.image?(%Asset{content_type: "application/pdf"})
    end

    test "audio?/1 returns true for audio content types" do
      assert Asset.audio?(%Asset{content_type: "audio/mpeg"})
      assert Asset.audio?(%Asset{content_type: "audio/wav"})
      assert Asset.audio?(%Asset{content_type: "audio/ogg"})
      refute Asset.audio?(%Asset{content_type: "image/jpeg"})
      refute Asset.audio?(%Asset{content_type: "application/pdf"})
    end

    test "allowed_content_types/0 returns expected types" do
      types = Asset.allowed_content_types()

      assert "image/jpeg" in types
      assert "image/png" in types
      assert "audio/mpeg" in types
    end

    test "allowed_content_type?/1 returns true for valid types" do
      assert Asset.allowed_content_type?("image/jpeg")
      assert Asset.allowed_content_type?("audio/mpeg")
      refute Asset.allowed_content_type?("application/x-malware")
    end
  end
end

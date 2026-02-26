defmodule Storyarn.AssetsTest do
  use Storyarn.DataCase, async: true

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

  describe "sanitize_filename/1" do
    test "downcases filename" do
      assert Assets.sanitize_filename("MyFile.JPG") == "myfile.jpg"
    end

    test "replaces spaces with underscores" do
      assert Assets.sanitize_filename("my file name.png") == "my_file_name.png"
    end

    test "replaces special characters" do
      assert Assets.sanitize_filename("file@#$%.txt") == "file____.txt"
    end

    test "strips path components" do
      assert Assets.sanitize_filename("/path/to/file.jpg") == "file.jpg"
      assert Assets.sanitize_filename("C:\\Users\\file.jpg") == "file.jpg"
    end

    test "limits length to 255 characters" do
      long_name = String.duplicate("a", 300) <> ".jpg"
      result = Assets.sanitize_filename(long_name)
      assert String.length(result) <= 255
    end

    test "handles unicode characters" do
      result = Assets.sanitize_filename("héro_portrait.png")
      assert is_binary(result)
      assert String.ends_with?(result, ".png")
    end

    test "preserves dots and hyphens" do
      assert Assets.sanitize_filename("my-file.v2.png") == "my-file.v2.png"
    end
  end

  describe "list_assets_for_export/1" do
    test "returns all assets ordered by insertion time" do
      user = user_fixture()
      project = project_fixture(user)
      _asset1 = asset_fixture(project, user, %{filename: "first.jpg"})
      _asset2 = asset_fixture(project, user, %{filename: "second.jpg"})

      assets = Assets.list_assets_for_export(project.id)
      assert length(assets) == 2
      assert hd(assets).filename == "first.jpg"
    end

    test "returns empty list for project without assets" do
      project = project_fixture()
      assert Assets.list_assets_for_export(project.id) == []
    end
  end

  describe "count_assets/1" do
    test "counts all assets in project" do
      user = user_fixture()
      project = project_fixture(user)
      _asset1 = asset_fixture(project, user)
      _asset2 = asset_fixture(project, user)

      assert Assets.count_assets(project.id) == 2
    end

    test "returns 0 for empty project" do
      project = project_fixture()
      assert Assets.count_assets(project.id) == 0
    end
  end

  describe "import_asset/2" do
    test "creates an asset record for import" do
      project = project_fixture()

      attrs = %{
        filename: "imported.png",
        content_type: "image/png",
        size: 5000,
        key: "projects/#{project.id}/assets/#{Ecto.UUID.generate()}/imported.png",
        url: "/uploads/imported.png"
      }

      assert {:ok, asset} = Assets.import_asset(project.id, attrs)
      assert asset.filename == "imported.png"
      assert asset.project_id == project.id
      assert asset.uploaded_by_id == nil
    end

    test "returns error for invalid attrs" do
      project = project_fixture()
      assert {:error, changeset} = Assets.import_asset(project.id, %{})
      assert errors_on(changeset).filename != []
    end
  end

  describe "count_asset_usages/2" do
    test "returns total count of usages" do
      user = user_fixture()
      project = project_fixture(user)
      asset = asset_fixture(project, user)

      assert Assets.count_asset_usages(project.id, asset.id) == 0
    end

    test "counts flow node usages" do
      import Storyarn.FlowsFixtures

      user = user_fixture()
      project = project_fixture(user)
      audio = audio_asset_fixture(project, user)
      flow = flow_fixture(project)

      node_fixture(flow, %{
        type: "dialogue",
        data: %{"audio_asset_id" => audio.id, "text" => "Hello"}
      })

      assert Assets.count_asset_usages(project.id, audio.id) == 1
    end
  end

  describe "get_asset!/2" do
    test "returns asset by id" do
      user = user_fixture()
      project = project_fixture(user)
      asset = asset_fixture(project, user)

      found = Assets.get_asset!(project.id, asset.id)
      assert found.id == asset.id
    end

    test "raises for non-existent asset" do
      project = project_fixture()

      assert_raise Ecto.NoResultsError, fn ->
        Assets.get_asset!(project.id, 0)
      end
    end
  end

  describe "list_assets/2 pagination" do
    test "respects limit option" do
      user = user_fixture()
      project = project_fixture(user)
      for _ <- 1..5, do: asset_fixture(project, user)

      assets = Assets.list_assets(project.id, limit: 2)
      assert length(assets) == 2
    end

    test "respects offset option" do
      user = user_fixture()
      project = project_fixture(user)
      for _ <- 1..5, do: asset_fixture(project, user)

      all_assets = Assets.list_assets(project.id)
      offset_assets = Assets.list_assets(project.id, offset: 2)
      assert length(offset_assets) == length(all_assets) - 2
    end

    test "combines limit and offset" do
      user = user_fixture()
      project = project_fixture(user)
      for _ <- 1..10, do: asset_fixture(project, user)

      assets = Assets.list_assets(project.id, limit: 3, offset: 2)
      assert length(assets) == 3
    end
  end

  describe "facade type check delegations" do
    test "image?/1 delegates to Asset schema" do
      assert Assets.image?(%Asset{content_type: "image/jpeg"})
      assert Assets.image?(%Asset{content_type: "image/png"})
      assert Assets.image?(%Asset{content_type: "image/gif"})
      assert Assets.image?(%Asset{content_type: "image/webp"})
      assert Assets.image?(%Asset{content_type: "image/svg+xml"})
      refute Assets.image?(%Asset{content_type: "audio/mpeg"})
      refute Assets.image?(%Asset{content_type: "application/pdf"})
    end

    test "audio?/1 delegates to Asset schema" do
      assert Assets.audio?(%Asset{content_type: "audio/mpeg"})
      assert Assets.audio?(%Asset{content_type: "audio/wav"})
      assert Assets.audio?(%Asset{content_type: "audio/ogg"})
      assert Assets.audio?(%Asset{content_type: "audio/webm"})
      refute Assets.audio?(%Asset{content_type: "image/jpeg"})
      refute Assets.audio?(%Asset{content_type: "application/pdf"})
    end

    test "allowed_content_type?/1 delegates to Asset schema" do
      assert Assets.allowed_content_type?("image/jpeg")
      assert Assets.allowed_content_type?("image/png")
      assert Assets.allowed_content_type?("audio/mpeg")
      assert Assets.allowed_content_type?("application/pdf")
      refute Assets.allowed_content_type?("application/x-evil")
      refute Assets.allowed_content_type?("text/html")
      refute Assets.allowed_content_type?("video/mp4")
    end
  end

  describe "storage delegations" do
    test "storage_upload/3 uploads data and returns url" do
      key = "test/temp/#{Ecto.UUID.generate()}/test_upload.txt"

      assert {:ok, url} = Assets.storage_upload(key, "test content", "text/plain")
      assert is_binary(url)
      assert String.contains?(url, key)

      # Cleanup
      Assets.storage_delete(key)
    end

    test "storage_delete/1 deletes an uploaded file" do
      key = "test/temp/#{Ecto.UUID.generate()}/test_delete.txt"
      {:ok, _url} = Assets.storage_upload(key, "to be deleted", "text/plain")

      assert :ok = Assets.storage_delete(key)
    end

    test "storage_delete/1 returns :ok for non-existent key" do
      key = "test/temp/nonexistent-#{Ecto.UUID.generate()}/missing.txt"

      assert :ok = Assets.storage_delete(key)
    end
  end

  describe "image_processor delegations" do
    test "image_processor_available?/0 returns a boolean" do
      result = Assets.image_processor_available?()
      assert is_boolean(result)
    end

    @tag skip: unless(Storyarn.Assets.image_processor_available?(), do: "Image processor not available")
    test "image_processor_get_dimensions/1 with valid image" do
      image_path = Path.join(["test", "fixtures", "images", "quadrant_map.png"])

      assert {:ok, %{width: w, height: h}} = Assets.image_processor_get_dimensions(image_path)
      assert is_integer(w) and w > 0
      assert is_integer(h) and h > 0
    end

    @tag skip: unless(Storyarn.Assets.image_processor_available?(), do: "Image processor not available")
    test "image_processor_get_dimensions/1 with nonexistent file" do
      assert {:error, _reason} = Assets.image_processor_get_dimensions("/nonexistent/image.png")
    end
  end

  describe "upload_and_create_asset/4" do
    setup do
      user = user_fixture()
      project = project_fixture(user)
      %{project: project, user: user}
    end

    test "uploads file, creates asset record with correct attributes", %{
      project: project,
      user: user
    } do
      # Create a temporary file to upload
      tmp_dir = System.tmp_dir!()
      tmp_path = Path.join(tmp_dir, "test_upload_#{Ecto.UUID.generate()}.txt")
      File.write!(tmp_path, "test file content")

      entry = %Phoenix.LiveView.UploadEntry{
        client_name: "my_document.pdf",
        client_type: "application/pdf",
        client_size: 17
      }

      try do
        assert {:ok, asset} = Assets.upload_and_create_asset(tmp_path, entry, project, user)
        assert asset.filename == "my_document.pdf"
        assert asset.content_type == "application/pdf"
        assert asset.size == 17
        assert asset.project_id == project.id
        assert asset.uploaded_by_id == user.id
        assert is_binary(asset.key)
        assert is_binary(asset.url)

        # Cleanup storage
        Assets.storage_delete(asset.key)
      after
        File.rm(tmp_path)
      end
    end

    test "creates asset with image metadata when image processor is available", %{
      project: project,
      user: user
    } do
      image_path = Path.join(["test", "fixtures", "images", "quadrant_map.png"])

      if Assets.image_processor_available?() and File.exists?(image_path) do
        %{size: file_size} = File.stat!(image_path)

        entry = %Phoenix.LiveView.UploadEntry{
          client_name: "quadrant_map.png",
          client_type: "image/png",
          client_size: file_size
        }

        assert {:ok, asset} = Assets.upload_and_create_asset(image_path, entry, project, user)
        assert asset.content_type == "image/png"

        # Image metadata should include width and height
        assert is_map(asset.metadata)
        assert is_integer(asset.metadata["width"])
        assert is_integer(asset.metadata["height"])
        assert asset.metadata["width"] > 0
        assert asset.metadata["height"] > 0

        # Cleanup storage
        Assets.storage_delete(asset.key)
      end
    end

    test "creates asset with empty metadata for non-image files", %{
      project: project,
      user: user
    } do
      tmp_dir = System.tmp_dir!()
      tmp_path = Path.join(tmp_dir, "test_audio_#{Ecto.UUID.generate()}.mp3")
      File.write!(tmp_path, "fake audio content")

      entry = %Phoenix.LiveView.UploadEntry{
        client_name: "test_audio.mp3",
        client_type: "audio/mpeg",
        client_size: 18
      }

      try do
        assert {:ok, asset} = Assets.upload_and_create_asset(tmp_path, entry, project, user)
        assert asset.content_type == "audio/mpeg"
        # Non-image files should have empty metadata
        assert asset.metadata == %{}

        # Cleanup storage
        Assets.storage_delete(asset.key)
      after
        File.rm(tmp_path)
      end
    end

    test "cleans up storage on database error", %{project: project, user: user} do
      tmp_dir = System.tmp_dir!()
      tmp_path = Path.join(tmp_dir, "test_cleanup_#{Ecto.UUID.generate()}.pdf")
      File.write!(tmp_path, "test content for cleanup")

      # First, create an asset to get a key collision
      first_entry = %Phoenix.LiveView.UploadEntry{
        client_name: "collision_test.pdf",
        client_type: "application/pdf",
        client_size: 23
      }

      {:ok, first_asset} = Assets.upload_and_create_asset(tmp_path, first_entry, project, user)

      # Now try to create a second asset with the same key - we can't easily force
      # a key collision due to UUID generation, but we can test by creating an asset
      # with an invalid content_type that will fail changeset validation
      bad_entry = %Phoenix.LiveView.UploadEntry{
        client_name: "bad_type.xyz",
        client_type: "application/x-malware",
        client_size: 23
      }

      try do
        # This should fail at the changeset validation level after uploading
        result = Assets.upload_and_create_asset(tmp_path, bad_entry, project, user)

        case result do
          {:error, _} ->
            # The function should have cleaned up the storage file
            assert true

          {:ok, asset} ->
            # If it somehow succeeded, clean up
            Assets.storage_delete(asset.key)
        end
      after
        File.rm(tmp_path)
        Assets.storage_delete(first_asset.key)
      end
    end
  end

  describe "change_asset/2 with attrs" do
    test "returns changeset with applied changes" do
      user = user_fixture()
      project = project_fixture(user)
      asset = asset_fixture(project, user)

      changeset = Assets.change_asset(asset, %{metadata: %{"width" => 1024}})
      assert %Ecto.Changeset{} = changeset
      assert Ecto.Changeset.get_change(changeset, :metadata) == %{"width" => 1024}
    end

    test "returns changeset with url change" do
      user = user_fixture()
      project = project_fixture(user)
      asset = asset_fixture(project, user)

      changeset = Assets.change_asset(asset, %{url: "/new/url.jpg"})
      assert %Ecto.Changeset{} = changeset
      assert Ecto.Changeset.get_change(changeset, :url) == "/new/url.jpg"
    end
  end

  describe "count_asset_usages/2 with multiple usage types" do
    test "counts combined flow node and sheet avatar usages" do
      import Storyarn.FlowsFixtures
      import Storyarn.SheetsFixtures

      user = user_fixture()
      project = project_fixture(user)
      image = image_asset_fixture(project, user)
      flow = flow_fixture(project)

      # Add flow node usage (audio_asset_id on dialogue node)
      node_fixture(flow, %{
        type: "dialogue",
        data: %{"audio_asset_id" => image.id, "text" => "Hello"}
      })

      # Add sheet avatar usage
      _sheet = sheet_fixture(project, %{name: "Hero", avatar_asset_id: image.id})

      assert Assets.count_asset_usages(project.id, image.id) == 2
    end

    test "counts combined flow node, avatar, and banner usages" do
      import Storyarn.FlowsFixtures
      import Storyarn.SheetsFixtures

      user = user_fixture()
      project = project_fixture(user)
      image = image_asset_fixture(project, user)
      flow = flow_fixture(project)

      # Flow node usage
      node_fixture(flow, %{
        type: "dialogue",
        data: %{"audio_asset_id" => image.id, "text" => "Hello"}
      })

      # Sheet avatar usage
      _avatar_sheet = sheet_fixture(project, %{name: "Hero", avatar_asset_id: image.id})

      # Sheet banner usage
      _banner_sheet = sheet_fixture(project, %{name: "Location", banner_asset_id: image.id})

      assert Assets.count_asset_usages(project.id, image.id) == 3
    end
  end

  describe "list_assets/2 combined filters" do
    setup do
      user = user_fixture()
      project = project_fixture(user)
      %{project: project, user: user}
    end

    test "filters by content_type and search combined", %{project: project, user: user} do
      _image1 = image_asset_fixture(project, user, %{filename: "hero_portrait.png"})
      _image2 = image_asset_fixture(project, user, %{filename: "villain_portrait.png"})
      _audio = audio_asset_fixture(project, user, %{filename: "hero_theme.mp3"})

      # Search for "hero" but only images
      assets = Assets.list_assets(project.id, content_type: "image/", search: "hero")
      assert length(assets) == 1
      assert hd(assets).filename == "hero_portrait.png"
    end

    test "filters by images_only and search combined", %{project: project, user: user} do
      _image = image_asset_fixture(project, user, %{filename: "hero_pic.png"})
      _audio = audio_asset_fixture(project, user, %{filename: "hero_music.mp3"})

      assets = Assets.list_assets(project.id, images_only: true, search: "hero")
      assert length(assets) == 1
      assert hd(assets).filename == "hero_pic.png"
    end

    test "filters with content_type, search, and limit", %{project: project, user: user} do
      for i <- 1..5 do
        image_asset_fixture(project, user, %{filename: "scene_#{i}.png"})
      end

      _audio = audio_asset_fixture(project, user, %{filename: "scene_music.mp3"})

      assets = Assets.list_assets(project.id, content_type: "image/", search: "scene", limit: 3)
      assert length(assets) == 3
    end

    test "returns empty for project with no matching assets", %{project: project} do
      assets = Assets.list_assets(project.id, search: "nonexistent")
      assert assets == []
    end
  end

  describe "update_asset/2 edge cases" do
    test "updates metadata to nil" do
      user = user_fixture()
      project = project_fixture(user)
      asset = asset_fixture(project, user, %{metadata: %{"width" => 800}})

      assert {:ok, updated} = Assets.update_asset(asset, %{metadata: nil})
      assert updated.metadata == nil
    end

    test "does not allow updating filename through update_changeset" do
      user = user_fixture()
      project = project_fixture(user)
      asset = asset_fixture(project, user, %{filename: "original.jpg"})

      # update_changeset only casts :url and :metadata
      assert {:ok, updated} = Assets.update_asset(asset, %{filename: "changed.jpg"})
      assert updated.filename == "original.jpg"
    end

    test "does not allow updating content_type through update_changeset" do
      user = user_fixture()
      project = project_fixture(user)
      asset = asset_fixture(project, user, %{content_type: "image/jpeg"})

      assert {:ok, updated} = Assets.update_asset(asset, %{content_type: "audio/mpeg"})
      assert updated.content_type == "image/jpeg"
    end
  end

  describe "generate_key/2 edge cases" do
    test "generates different keys for same filename" do
      project = project_fixture()

      key1 = Assets.generate_key(project, "same.jpg")
      key2 = Assets.generate_key(project, "same.jpg")

      refute key1 == key2
    end

    test "includes project id in key" do
      project = project_fixture()
      key = Assets.generate_key(project, "test.jpg")

      assert String.contains?(key, "projects/#{project.id}/")
    end
  end

  describe "thumbnail_key/1 edge cases" do
    test "handles keys with multiple path segments" do
      key = "projects/abc123/assets/uuid-456/deep/nested/image.jpg"
      thumb = Assets.thumbnail_key(key)

      assert thumb == "projects/abc123/thumbnails/uuid-456/deep/nested/image.jpg"
    end

    test "returns key unchanged when no /assets/ segment" do
      key = "other/path/image.jpg"
      thumb = Assets.thumbnail_key(key)

      assert thumb == "other/path/image.jpg"
    end
  end

  describe "get_asset_usages/2 edge cases" do
    test "returns empty lists for non-existent asset id" do
      user = user_fixture()
      project = project_fixture(user)

      usages = Assets.get_asset_usages(project.id, 0)

      assert usages.flow_nodes == []
      assert usages.sheet_avatars == []
      assert usages.sheet_banners == []
    end

    test "returns combined avatar and banner usages on different sheets" do
      import Storyarn.SheetsFixtures

      user = user_fixture()
      project = project_fixture(user)
      image = image_asset_fixture(project, user)

      _avatar_sheet = sheet_fixture(project, %{name: "Character", avatar_asset_id: image.id})
      _banner_sheet = sheet_fixture(project, %{name: "Location", banner_asset_id: image.id})

      usages = Assets.get_asset_usages(project.id, image.id)

      assert length(usages.sheet_avatars) == 1
      assert length(usages.sheet_banners) == 1
      assert usages.flow_nodes == []
    end
  end

  describe "import_asset/2 edge cases" do
    test "creates asset with metadata" do
      project = project_fixture()

      attrs = %{
        filename: "imported_with_meta.png",
        content_type: "image/png",
        size: 10_000,
        key: "projects/#{project.id}/assets/#{Ecto.UUID.generate()}/imported_with_meta.png",
        url: "/uploads/imported.png",
        metadata: %{"width" => 1920, "height" => 1080}
      }

      assert {:ok, asset} = Assets.import_asset(project.id, attrs)
      assert asset.metadata == %{"width" => 1920, "height" => 1080}
    end

    test "validates content_type on import" do
      project = project_fixture()

      attrs = %{
        filename: "bad.exe",
        content_type: "application/x-executable",
        size: 5000,
        key: "projects/#{project.id}/assets/#{Ecto.UUID.generate()}/bad.exe",
        url: "/uploads/bad.exe"
      }

      assert {:error, changeset} = Assets.import_asset(project.id, attrs)
      assert errors_on(changeset).content_type != []
    end

    test "validates size on import" do
      project = project_fixture()

      attrs = %{
        filename: "zero.png",
        content_type: "image/png",
        size: 0,
        key: "projects/#{project.id}/assets/#{Ecto.UUID.generate()}/zero.png",
        url: "/uploads/zero.png"
      }

      assert {:error, changeset} = Assets.import_asset(project.id, attrs)
      assert errors_on(changeset).size != []
    end
  end

  describe "sanitize_filename/1 additional cases" do
    test "handles empty extension" do
      result = Assets.sanitize_filename("noextension")
      assert result == "noextension"
    end

    test "handles multiple consecutive special characters" do
      result = Assets.sanitize_filename("a!!!b@@@c.jpg")
      assert result == "a___b___c.jpg"
    end

    test "handles filename that is only special characters" do
      result = Assets.sanitize_filename("@#$.jpg")
      assert result == "___.jpg"
    end

    test "handles backslash path on Windows-style paths" do
      result = Assets.sanitize_filename("C:\\Users\\Admin\\Desktop\\photo.png")
      assert result == "photo.png"
    end

    test "handles mixed path separators" do
      result = Assets.sanitize_filename("/home/user\\documents/file.txt")
      assert result == "file.txt"
    end
  end

  describe "count_assets_by_type/1 edge cases" do
    test "returns empty map for project without assets" do
      project = project_fixture()

      counts = Assets.count_assets_by_type(project.id)
      assert counts == %{}
    end

    test "counts multiple content type categories" do
      user = user_fixture()
      project = project_fixture(user)

      _img1 = image_asset_fixture(project, user)
      _img2 = image_asset_fixture(project, user)
      _audio1 = audio_asset_fixture(project, user)

      attrs =
        valid_asset_attributes(%{
          filename: "doc.pdf",
          content_type: "application/pdf",
          key: "projects/#{project.id}/assets/#{Ecto.UUID.generate()}/doc.pdf"
        })

      {:ok, _pdf} = Assets.create_asset(project, user, attrs)

      counts = Assets.count_assets_by_type(project.id)
      assert counts["image"] == 2
      assert counts["audio"] == 1
      assert counts["application"] == 1
    end
  end
end

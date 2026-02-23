defmodule StoryarnWeb.AssetLive.IndexTest do
  use StoryarnWeb.ConnCase

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Repo

  describe "Index" do
    setup :register_and_log_in_user

    test "renders Assets page for project owner", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)

      {:ok, _view, html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/assets")

      assert html =~ "Assets"
    end

    test "renders empty state when no assets exist", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)

      {:ok, _view, html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/assets")

      assert html =~ "No assets yet"
    end

    test "renders Assets link in sidebar", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/assets")

      assert has_element?(view, "a", "Assets")
    end

    test "redirects unauthorized user", %{conn: conn} do
      other_user = user_fixture()
      project = project_fixture(other_user) |> Repo.preload(:workspace)

      assert {:error, {:redirect, %{to: "/workspaces", flash: %{"error" => error_msg}}}} =
               live(
                 conn,
                 ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/assets"
               )

      assert error_msg =~ "You don't have access to this project."
    end
  end

  describe "Asset grid and filtering" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      %{project: project}
    end

    test "lists all assets with filename and size", %{conn: conn, user: user, project: project} do
      image_asset_fixture(project, user, %{filename: "hero.png", size: 50_000})
      audio_asset_fixture(project, user, %{filename: "theme.mp3", size: 1_200_000})

      {:ok, _view, html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/assets")

      assert html =~ "hero.png"
      assert html =~ "theme.mp3"
      assert html =~ "48.8 KB"
      assert html =~ "1.1 MB"
    end

    test "shows type badge per asset", %{conn: conn, user: user, project: project} do
      image_asset_fixture(project, user)
      audio_asset_fixture(project, user)

      {:ok, _view, html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/assets")

      assert html =~ "Image"
      assert html =~ "Audio"
    end

    test "shows asset count per filter tab", %{conn: conn, user: user, project: project} do
      image_asset_fixture(project, user)
      image_asset_fixture(project, user)
      audio_asset_fixture(project, user)

      {:ok, _view, html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/assets")

      # All tab shows total count (3)
      assert html =~ ">3</span>"
      # Images tab shows 2
      assert html =~ ">2</span>"
      # Audio tab shows 1
      assert html =~ ">1</span>"
    end

    test "filter 'image' shows only images", %{conn: conn, user: user, project: project} do
      image_asset_fixture(project, user, %{filename: "photo.png"})
      audio_asset_fixture(project, user, %{filename: "voice.mp3"})

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/assets")

      html = view |> element("[phx-value-type=image]") |> render_click()

      assert html =~ "photo.png"
      refute html =~ "voice.mp3"
    end

    test "filter 'audio' shows only audio", %{conn: conn, user: user, project: project} do
      image_asset_fixture(project, user, %{filename: "photo.png"})
      audio_asset_fixture(project, user, %{filename: "voice.mp3"})

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/assets")

      html = view |> element("[phx-value-type=audio]") |> render_click()

      refute html =~ "photo.png"
      assert html =~ "voice.mp3"
    end

    test "filter 'all' shows everything", %{conn: conn, user: user, project: project} do
      image_asset_fixture(project, user, %{filename: "photo.png"})
      audio_asset_fixture(project, user, %{filename: "voice.mp3"})

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/assets")

      # Filter to image first, then back to all
      view |> element("[phx-value-type=image]") |> render_click()
      html = view |> element("[phx-value-type=all]") |> render_click()

      assert html =~ "photo.png"
      assert html =~ "voice.mp3"
    end
  end

  describe "Search" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      %{project: project}
    end

    test "search filters assets by filename substring", %{
      conn: conn,
      user: user,
      project: project
    } do
      image_asset_fixture(project, user, %{filename: "hero_banner.png"})
      audio_asset_fixture(project, user, %{filename: "battle_theme.mp3"})

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/assets")

      html =
        view
        |> form("form[phx-change='search_assets']", %{search: "hero"})
        |> render_change()

      assert html =~ "hero_banner.png"
      refute html =~ "battle_theme.mp3"
    end

    test "empty search shows all assets", %{conn: conn, user: user, project: project} do
      image_asset_fixture(project, user, %{filename: "hero_banner.png"})
      audio_asset_fixture(project, user, %{filename: "battle_theme.mp3"})

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/assets")

      # Search then clear
      view |> form("form[phx-change='search_assets']", %{search: "hero"}) |> render_change()
      html = view |> form("form[phx-change='search_assets']", %{search: ""}) |> render_change()

      assert html =~ "hero_banner.png"
      assert html =~ "battle_theme.mp3"
    end

    test "search combines with type filter", %{conn: conn, user: user, project: project} do
      image_asset_fixture(project, user, %{filename: "hero_banner.png"})
      image_asset_fixture(project, user, %{filename: "villain_portrait.png"})
      audio_asset_fixture(project, user, %{filename: "hero_theme.mp3"})

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/assets")

      # Filter to images first
      view |> element("[phx-value-type=image]") |> render_click()

      # Then search for "hero"
      html =
        view |> form("form[phx-change='search_assets']", %{search: "hero"}) |> render_change()

      assert html =~ "hero_banner.png"
      refute html =~ "villain_portrait.png"
      refute html =~ "hero_theme.mp3"
    end

    test "search is case-insensitive", %{conn: conn, user: user, project: project} do
      image_asset_fixture(project, user, %{filename: "hero_banner.png"})

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/assets")

      html =
        view |> form("form[phx-change='search_assets']", %{search: "HERO"}) |> render_change()

      assert html =~ "hero_banner.png"
    end
  end

  describe "Detail panel" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      %{project: project}
    end

    test "clicking asset shows detail panel", %{conn: conn, user: user, project: project} do
      asset = image_asset_fixture(project, user, %{filename: "hero.png"})

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/assets")

      html =
        view
        |> element("[phx-click='select_asset'][phx-value-id='#{asset.id}']")
        |> render_click()

      assert html =~ "Details"
      assert html =~ "Filename"
      assert html =~ "hero.png"
    end

    test "detail panel shows filename, size, type", %{conn: conn, user: user, project: project} do
      asset =
        image_asset_fixture(project, user, %{
          filename: "portrait.png",
          size: 250_000,
          content_type: "image/png"
        })

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/assets")

      html =
        view
        |> element("[phx-click='select_asset'][phx-value-id='#{asset.id}']")
        |> render_click()

      assert html =~ "portrait.png"
      assert html =~ "244.1 KB"
      assert html =~ "image/png"
    end

    test "audio assets show player in detail panel", %{
      conn: conn,
      user: user,
      project: project
    } do
      asset = audio_asset_fixture(project, user, %{filename: "theme.mp3"})

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/assets")

      html =
        view
        |> element("[phx-click='select_asset'][phx-value-id='#{asset.id}']")
        |> render_click()

      assert html =~ "<audio"
      assert html =~ "theme.mp3"
    end

    test "usage section shows 'Not used anywhere' for unused asset", %{
      conn: conn,
      user: user,
      project: project
    } do
      asset = image_asset_fixture(project, user)

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/assets")

      html =
        view
        |> element("[phx-click='select_asset'][phx-value-id='#{asset.id}']")
        |> render_click()

      assert html =~ "Not used anywhere"
    end

    test "usage section shows linked flows", %{conn: conn, user: user, project: project} do
      import Storyarn.FlowsFixtures

      audio = audio_asset_fixture(project, user)
      flow = flow_fixture(project, %{name: "Battle Flow"})

      node_fixture(flow, %{
        type: "dialogue",
        data: %{"audio_asset_id" => audio.id, "text" => "Attack!"}
      })

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/assets")

      html =
        view
        |> element("[phx-click='select_asset'][phx-value-id='#{audio.id}']")
        |> render_click()

      assert html =~ "Battle Flow"
      assert html =~ "/flows/#{flow.id}"
    end

    test "usage section shows linked sheets", %{conn: conn, user: user, project: project} do
      import Storyarn.SheetsFixtures

      image = image_asset_fixture(project, user)
      sheet = sheet_fixture(project, %{name: "Hero Character", avatar_asset_id: image.id})

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/assets")

      html =
        view
        |> element("[phx-click='select_asset'][phx-value-id='#{image.id}']")
        |> render_click()

      assert html =~ "Hero Character"
      assert html =~ "/sheets/#{sheet.id}"
      assert html =~ "avatar"
    end

    test "deselect closes detail panel", %{conn: conn, user: user, project: project} do
      asset = image_asset_fixture(project, user, %{filename: "hero.png"})

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/assets")

      # Select
      view |> element("[phx-click='select_asset'][phx-value-id='#{asset.id}']") |> render_click()
      # Deselect
      html = view |> element("[phx-click=deselect_asset]") |> render_click()

      refute html =~ "Details"
      refute html =~ "Filename"
    end
  end

  describe "Upload" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      %{project: project}
    end

    test "upload button renders for editor", %{conn: conn, project: project} do
      {:ok, _view, html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/assets")

      assert html =~ "Upload"
      assert html =~ "asset-upload-input"
    end

    test "upload creates asset and shows it in the grid", %{conn: conn, project: project} do
      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/assets")

      # Simulate the JS hook pushing the upload_asset event with base64 data
      # A minimal 1x1 PNG pixel
      png_data = Base.encode64(<<137, 80, 78, 71, 13, 10, 26, 10>>)

      html =
        render_hook(view, "upload_asset", %{
          "filename" => "test_upload.png",
          "content_type" => "image/png",
          "data" => "data:image/png;base64,#{png_data}"
        })

      assert html =~ "test_upload.png"
      assert html =~ "Asset uploaded successfully."
    end

    test "upload auto-selects the new asset", %{conn: conn, project: project} do
      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/assets")

      png_data = Base.encode64(<<137, 80, 78, 71, 13, 10, 26, 10>>)

      html =
        render_hook(view, "upload_asset", %{
          "filename" => "new_image.png",
          "content_type" => "image/png",
          "data" => "data:image/png;base64,#{png_data}"
        })

      # Detail panel should be open with the uploaded asset
      assert html =~ "Details"
      assert html =~ "new_image.png"
    end

    test "upload validation error shows flash", %{conn: conn, project: project} do
      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/assets")

      html =
        render_hook(view, "upload_validation_error", %{
          "message" => "File must be less than 20MB."
        })

      assert html =~ "File must be less than 20MB."
    end
  end

  describe "Delete" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      %{project: project}
    end

    test "delete button renders for editor in detail panel", %{
      conn: conn,
      user: user,
      project: project
    } do
      asset = image_asset_fixture(project, user)

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/assets")

      html =
        view
        |> element("[phx-click='select_asset'][phx-value-id='#{asset.id}']")
        |> render_click()

      assert html =~ "Delete asset"
    end

    test "deleting removes asset from grid", %{conn: conn, user: user, project: project} do
      asset = image_asset_fixture(project, user, %{filename: "doomed.png"})

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/assets")

      # Select the asset
      view
      |> element("[phx-click='select_asset'][phx-value-id='#{asset.id}']")
      |> render_click()

      # Confirm delete
      html = render_hook(view, "confirm_delete_asset", %{})

      refute html =~ "doomed.png"
      assert html =~ "Asset deleted."
    end

    test "delete closes detail panel", %{conn: conn, user: user, project: project} do
      asset = image_asset_fixture(project, user)

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/assets")

      view
      |> element("[phx-click='select_asset'][phx-value-id='#{asset.id}']")
      |> render_click()

      html = render_hook(view, "confirm_delete_asset", %{})

      refute html =~ "Details"
    end

    test "delete modal shows usage warning when asset is in use", %{
      conn: conn,
      user: user,
      project: project
    } do
      import Storyarn.FlowsFixtures

      audio = audio_asset_fixture(project, user)
      flow = flow_fixture(project, %{name: "Battle Flow"})

      node_fixture(flow, %{
        type: "dialogue",
        data: %{"audio_asset_id" => audio.id, "text" => "Attack!"}
      })

      {:ok, view, _html} =
        live(conn, ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/assets")

      html =
        view
        |> element("[phx-click='select_asset'][phx-value-id='#{audio.id}']")
        |> render_click()

      assert html =~ "used in"
      assert html =~ "1 place"
    end
  end
end

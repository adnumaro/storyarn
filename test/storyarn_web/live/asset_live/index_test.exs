defmodule StoryarnWeb.AssetLive.IndexTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Assets.Asset
  alias Storyarn.Repo
  alias Storyarn.Sheets.SheetAvatar

  defp assets_path(project) do
    ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/assets"
  end

  defp get_assets_vue(view) do
    LiveVue.Test.get_vue(view, name: "live/assets/dashboard/AssetsDashboard")
  end

  defp get_header_actions_vue(view) do
    LiveVue.Test.get_vue(view, name: "live/assets/dashboard/AssetsHeaderActions")
  end

  defp get_sidebar_live(view, project) do
    find_live_child(view, "sidebar-assets-#{project.id}")
  end

  defp get_sidebar_props(view, project) do
    project
    |> then(&get_sidebar_live(view, &1))
    |> LiveVue.Test.get_vue(name: "live/assets/sidebar/AssetsSidebar")
    |> then(& &1.props["sidebar-props"])
  end

  describe "Index" do
    setup :register_and_log_in_user

    test "renders Assets Vue component for project owner", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)

      {:ok, view, _html} = live(conn, assets_path(project))

      vue = get_assets_vue(view)
      assert vue.component == "live/assets/dashboard/AssetsDashboard"
      assert vue.props["can-edit"] == true
    end

    test "passes empty assets list when no assets exist", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)

      {:ok, view, _html} = live(conn, assets_path(project))

      vue = get_assets_vue(view)
      assert vue.props["assets"] == []
    end

    test "redirects unauthorized user", %{conn: conn} do
      other_user = user_fixture()
      project = other_user |> project_fixture() |> Repo.preload(:workspace)

      assert {:error, {:redirect, %{to: "/workspaces", flash: %{"error" => error_msg}}}} =
               live(conn, assets_path(project))

      assert error_msg =~ "You don't have access to this project."
    end
  end

  describe "Asset grid and filtering" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      %{project: project}
    end

    test "passes all assets with filename and size", %{conn: conn, user: user, project: project} do
      image_asset_fixture(project, user, %{filename: "hero.png", size: 50_000})
      audio_asset_fixture(project, user, %{filename: "theme.mp3", size: 1_200_000})

      {:ok, view, _html} = live(conn, assets_path(project))

      vue = get_assets_vue(view)
      filenames = Enum.map(vue.props["assets"], & &1["filename"])
      assert "hero.png" in filenames
      assert "theme.mp3" in filenames
    end

    test "passes type-counts for each filter tab", %{
      conn: conn,
      user: user,
      project: project
    } do
      image_asset_fixture(project, user)
      image_asset_fixture(project, user)
      audio_asset_fixture(project, user)

      {:ok, view, _html} = live(conn, assets_path(project))

      sidebar_props = get_sidebar_props(view, project)
      assert sidebar_props["typeCounts"]["image"] == 2
      assert sidebar_props["typeCounts"]["audio"] == 1
    end

    test "filter 'image' updates filter and filters assets via event", %{
      conn: conn,
      user: user,
      project: project
    } do
      image_asset_fixture(project, user, %{filename: "photo.png"})
      audio_asset_fixture(project, user, %{filename: "voice.mp3"})

      {:ok, view, _html} = live(conn, assets_path(project))
      sidebar = get_sidebar_live(view, project)

      render_click(sidebar, "filter_assets", %{"type" => "image"})

      assert get_sidebar_props(view, project)["filter"] == "image"
      vue = get_assets_vue(view)
      filenames = Enum.map(vue.props["assets"], & &1["filename"])
      assert "photo.png" in filenames
      refute "voice.mp3" in filenames
    end

    test "filter 'audio' updates filter", %{conn: conn, user: user, project: project} do
      image_asset_fixture(project, user, %{filename: "photo.png"})
      audio_asset_fixture(project, user, %{filename: "voice.mp3"})

      {:ok, view, _html} = live(conn, assets_path(project))
      sidebar = get_sidebar_live(view, project)

      render_click(sidebar, "filter_assets", %{"type" => "audio"})

      assert get_sidebar_props(view, project)["filter"] == "audio"
      vue = get_assets_vue(view)
      filenames = Enum.map(vue.props["assets"], & &1["filename"])
      refute "photo.png" in filenames
      assert "voice.mp3" in filenames
    end

    test "filter 'all' shows everything", %{conn: conn, user: user, project: project} do
      image_asset_fixture(project, user, %{filename: "photo.png"})
      audio_asset_fixture(project, user, %{filename: "voice.mp3"})

      {:ok, view, _html} = live(conn, assets_path(project))
      sidebar = get_sidebar_live(view, project)

      render_click(sidebar, "filter_assets", %{"type" => "image"})
      render_click(sidebar, "filter_assets", %{"type" => "all"})

      assert get_sidebar_props(view, project)["filter"] == "all"
      vue = get_assets_vue(view)
      filenames = Enum.map(vue.props["assets"], & &1["filename"])
      assert "photo.png" in filenames
      assert "voice.mp3" in filenames
    end
  end

  describe "Search" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      %{project: project}
    end

    test "search filters assets by filename substring", %{
      conn: conn,
      user: user,
      project: project
    } do
      image_asset_fixture(project, user, %{filename: "hero_banner.png"})
      audio_asset_fixture(project, user, %{filename: "battle_theme.mp3"})

      {:ok, view, _html} = live(conn, assets_path(project))
      sidebar = get_sidebar_live(view, project)

      render_change(sidebar, "search_assets", %{"search" => "hero"})

      assert get_sidebar_props(view, project)["search"] == "hero"
      vue = get_assets_vue(view)
      filenames = Enum.map(vue.props["assets"], & &1["filename"])
      assert "hero_banner.png" in filenames
      refute "battle_theme.mp3" in filenames
    end

    test "empty search shows all assets", %{conn: conn, user: user, project: project} do
      image_asset_fixture(project, user, %{filename: "hero_banner.png"})
      audio_asset_fixture(project, user, %{filename: "battle_theme.mp3"})

      {:ok, view, _html} = live(conn, assets_path(project))
      sidebar = get_sidebar_live(view, project)

      render_change(sidebar, "search_assets", %{"search" => "hero"})
      render_change(sidebar, "search_assets", %{"search" => ""})

      vue = get_assets_vue(view)
      filenames = Enum.map(vue.props["assets"], & &1["filename"])
      assert "hero_banner.png" in filenames
      assert "battle_theme.mp3" in filenames
    end

    test "search combines with type filter", %{conn: conn, user: user, project: project} do
      image_asset_fixture(project, user, %{filename: "hero_banner.png"})
      image_asset_fixture(project, user, %{filename: "villain_portrait.png"})
      audio_asset_fixture(project, user, %{filename: "hero_theme.mp3"})

      {:ok, view, _html} = live(conn, assets_path(project))
      sidebar = get_sidebar_live(view, project)

      render_click(sidebar, "filter_assets", %{"type" => "image"})
      render_change(sidebar, "search_assets", %{"search" => "hero"})

      vue = get_assets_vue(view)
      filenames = Enum.map(vue.props["assets"], & &1["filename"])
      assert "hero_banner.png" in filenames
      refute "villain_portrait.png" in filenames
      refute "hero_theme.mp3" in filenames
    end

    test "search is case-insensitive", %{conn: conn, user: user, project: project} do
      image_asset_fixture(project, user, %{filename: "hero_banner.png"})

      {:ok, view, _html} = live(conn, assets_path(project))
      sidebar = get_sidebar_live(view, project)

      render_change(sidebar, "search_assets", %{"search" => "HERO"})

      vue = get_assets_vue(view)
      filenames = Enum.map(vue.props["assets"], & &1["filename"])
      assert "hero_banner.png" in filenames
    end
  end

  describe "Detail panel (select_asset)" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      %{project: project}
    end

    test "selecting asset sets selected-asset prop", %{conn: conn, user: user, project: project} do
      asset = image_asset_fixture(project, user, %{filename: "hero.png"})

      {:ok, view, _html} = live(conn, assets_path(project))

      render_click(view, "select_asset", %{"id" => to_string(asset.id)})

      vue = get_assets_vue(view)
      assert vue.props["selected-asset"]["filename"] == "hero.png"
    end

    test "selected-asset contains filename, size, type", %{
      conn: conn,
      user: user,
      project: project
    } do
      asset =
        image_asset_fixture(project, user, %{
          filename: "portrait.png",
          size: 250_000,
          content_type: "image/png"
        })

      {:ok, view, _html} = live(conn, assets_path(project))

      render_click(view, "select_asset", %{"id" => to_string(asset.id)})

      vue = get_assets_vue(view)
      selected = vue.props["selected-asset"]
      assert selected["filename"] == "portrait.png"
      assert selected["size"] == 250_000
      assert selected["contentType"] == "image/png"
    end

    test "usage section shows empty list for unused asset", %{
      conn: conn,
      user: user,
      project: project
    } do
      asset = image_asset_fixture(project, user)

      {:ok, view, _html} = live(conn, assets_path(project))

      render_click(view, "select_asset", %{"id" => to_string(asset.id)})

      vue = get_assets_vue(view)
      usages = vue.props["asset-usages"]

      assert usages["flowNodes"] == []
      assert usages["sheetAvatars"] == []
      assert usages["sheetBanners"] == []
    end

    test "usage section includes linked flows", %{conn: conn, user: user, project: project} do
      import Storyarn.FlowsFixtures

      audio = audio_asset_fixture(project, user)
      flow = flow_fixture(project, %{name: "Battle Flow"})

      node_fixture(flow, %{
        type: "dialogue",
        data: %{"audio_asset_id" => audio.id, "text" => "Attack!"}
      })

      {:ok, view, _html} = live(conn, assets_path(project))

      render_click(view, "select_asset", %{"id" => to_string(audio.id)})

      vue = get_assets_vue(view)
      usages = vue.props["asset-usages"]
      flow_nodes = usages["flowNodes"] || []
      assert Enum.any?(flow_nodes, fn u -> u["flowName"] == "Battle Flow" end)
    end

    test "usage section includes linked sheet avatars", %{
      conn: conn,
      user: user,
      project: project
    } do
      import Storyarn.SheetsFixtures

      image = image_asset_fixture(project, user)
      sheet = sheet_fixture(project, %{name: "Hero Character"})
      {:ok, _} = Storyarn.Sheets.add_avatar(sheet, image.id, %{is_default: true})

      {:ok, view, _html} = live(conn, assets_path(project))

      render_click(view, "select_asset", %{"id" => to_string(image.id)})

      vue = get_assets_vue(view)
      usages = vue.props["asset-usages"]
      avatars = usages["sheetAvatars"] || []
      assert Enum.any?(avatars, fn u -> u["name"] == "Hero Character" end)
    end

    test "deselect clears selected-asset", %{conn: conn, user: user, project: project} do
      asset = image_asset_fixture(project, user, %{filename: "hero.png"})

      {:ok, view, _html} = live(conn, assets_path(project))

      render_click(view, "select_asset", %{"id" => to_string(asset.id)})
      render_click(view, "deselect_asset", %{})

      vue = get_assets_vue(view)
      assert vue.props["selected-asset"] == nil
    end
  end

  describe "Upload" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      %{project: project}
    end

    test "passes uploading=false initially", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, assets_path(project))

      vue = get_header_actions_vue(view)
      assert vue.props["uploading"] == false
    end

    test "upload creates asset and selects it", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, assets_path(project))

      # A minimal 1x1 PNG pixel (header bytes)
      png_data = Base.encode64(<<137, 80, 78, 71, 13, 10, 26, 10>>)

      render_hook(view, "upload_asset", %{
        "filename" => "test_upload.png",
        "content_type" => "image/png",
        "data" => "data:image/png;base64,#{png_data}"
      })

      vue = get_assets_vue(view)
      filenames = Enum.map(vue.props["assets"], & &1["filename"])
      assert "test_upload.png" in filenames
      assert vue.props["selected-asset"]["filename"] == "test_upload.png"
    end

    test "upload validation error keeps the asset UI mounted", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, assets_path(project))

      html =
        render_hook(view, "upload_validation_error", %{
          "message" => "File must be less than 20MB."
        })

      assert is_binary(html)
      assert get_assets_vue(view).component == "live/assets/dashboard/AssetsDashboard"
    end
  end

  describe "Delete" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      %{project: project}
    end

    test "deleting removes asset from grid", %{conn: conn, user: user, project: project} do
      asset = image_asset_fixture(project, user, %{filename: "doomed.png"})

      {:ok, view, _html} = live(conn, assets_path(project))

      render_click(view, "select_asset", %{"id" => to_string(asset.id)})
      render_hook(view, "confirm_delete_asset", %{})

      vue = get_assets_vue(view)
      filenames = Enum.map(vue.props["assets"], & &1["filename"])
      refute "doomed.png" in filenames
    end

    test "delete clears selected-asset", %{conn: conn, user: user, project: project} do
      asset = image_asset_fixture(project, user)

      {:ok, view, _html} = live(conn, assets_path(project))

      render_click(view, "select_asset", %{"id" => to_string(asset.id)})
      render_hook(view, "confirm_delete_asset", %{})

      vue = get_assets_vue(view)
      assert vue.props["selected-asset"] == nil
    end

    test "deleting an asset used as a sheet avatar detaches the avatar and keeps the UI mounted", %{
      conn: conn,
      user: user,
      project: project
    } do
      import Storyarn.SheetsFixtures

      asset = image_asset_fixture(project, user, %{filename: "portrait.png"})
      sheet = sheet_fixture(project, %{name: "Hero"})
      {:ok, avatar} = Storyarn.Sheets.add_avatar(sheet, asset.id, %{is_default: true})

      {:ok, view, _html} = live(conn, assets_path(project))

      render_click(view, "select_asset", %{"id" => to_string(asset.id)})
      html = render_hook(view, "confirm_delete_asset", %{})

      assert is_binary(html)
      assert Repo.get(Asset, asset.id) == nil
      assert Repo.get(SheetAvatar, avatar.id) == nil
      assert get_assets_vue(view).props["selected-asset"] == nil
    end

    test "selecting asset in use passes usages to Vue", %{
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

      {:ok, view, _html} = live(conn, assets_path(project))

      render_click(view, "select_asset", %{"id" => to_string(audio.id)})

      vue = get_assets_vue(view)
      usages = vue.props["asset-usages"]

      total_usages =
        length(usages["flowNodes"] || []) +
          length(usages["sheetAvatars"] || []) +
          length(usages["sheetBanners"] || [])

      assert total_usages >= 1
    end
  end
end

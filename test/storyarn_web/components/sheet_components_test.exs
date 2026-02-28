defmodule StoryarnWeb.Components.SheetComponentsTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures
  import Storyarn.AssetsFixtures

  alias Storyarn.Repo
  alias StoryarnWeb.Components.SheetComponents

  # =============================================================================
  # sheet_avatar/1
  # =============================================================================

  describe "sheet_avatar/1" do
    test "renders fallback icon when avatar_asset is nil" do
      html = render_component(&SheetComponents.sheet_avatar/1, avatar_asset: nil)

      # Should render an icon, not an image
      refute html =~ "<img"
      assert html =~ "opacity-60"
    end

    test "renders fallback icon when avatar_asset is not loaded" do
      html =
        render_component(&SheetComponents.sheet_avatar/1,
          avatar_asset: %Ecto.Association.NotLoaded{
            __field__: :avatar_asset,
            __owner__: Storyarn.Sheets.Sheet,
            __cardinality__: :one
          }
        )

      refute html =~ "<img"
      assert html =~ "opacity-60"
    end

    test "renders image when avatar_asset is an image" do
      user = user_fixture()
      project = project_fixture(user) |> Repo.preload(:workspace)
      asset = image_asset_fixture(project, user)

      html =
        render_component(&SheetComponents.sheet_avatar/1,
          avatar_asset: asset,
          name: "Test Character"
        )

      assert html =~ "<img"
      assert html =~ asset.url
      assert html =~ "Test Character"
      assert html =~ "rounded"
    end

    test "renders fallback icon for non-image asset" do
      user = user_fixture()
      project = project_fixture(user) |> Repo.preload(:workspace)

      asset =
        asset_fixture(project, user, %{
          content_type: "application/pdf",
          filename: "document.pdf"
        })

      html = render_component(&SheetComponents.sheet_avatar/1, avatar_asset: asset)

      refute html =~ "<img"
      assert html =~ "opacity-60"
    end

    test "uses default alt text when name is nil" do
      user = user_fixture()
      project = project_fixture(user) |> Repo.preload(:workspace)
      asset = image_asset_fixture(project, user)

      html =
        render_component(&SheetComponents.sheet_avatar/1,
          avatar_asset: asset,
          name: nil
        )

      assert html =~ "Sheet avatar"
    end

    test "applies sm size class" do
      html =
        render_component(&SheetComponents.sheet_avatar/1,
          avatar_asset: nil,
          size: "sm"
        )

      assert html =~ "size-4"
    end

    test "applies md size class (default)" do
      html = render_component(&SheetComponents.sheet_avatar/1, avatar_asset: nil)

      assert html =~ "size-5"
    end

    test "applies lg size class" do
      html =
        render_component(&SheetComponents.sheet_avatar/1,
          avatar_asset: nil,
          size: "lg"
        )

      assert html =~ "size-6"
    end

    test "applies xl size class" do
      html =
        render_component(&SheetComponents.sheet_avatar/1,
          avatar_asset: nil,
          size: "xl"
        )

      assert html =~ "size-10"
    end

    test "applies size class to image when avatar present" do
      user = user_fixture()
      project = project_fixture(user) |> Repo.preload(:workspace)
      asset = image_asset_fixture(project, user)

      html =
        render_component(&SheetComponents.sheet_avatar/1,
          avatar_asset: asset,
          size: "xl"
        )

      assert html =~ "size-10"
      assert html =~ "object-cover"
    end
  end

  # =============================================================================
  # sheet_breadcrumb/1
  # =============================================================================

  describe "sheet_breadcrumb/1" do
    setup do
      user = user_fixture()
      project = project_fixture(user) |> Repo.preload(:workspace)
      workspace = project.workspace

      %{user: user, project: project, workspace: workspace}
    end

    test "renders breadcrumb with single ancestor", %{project: project, workspace: workspace} do
      parent = sheet_fixture(project, %{name: "Parent Sheet"})
      parent = Repo.preload(parent, :avatar_asset)

      html =
        render_component(&SheetComponents.sheet_breadcrumb/1,
          ancestors: [parent],
          workspace: workspace,
          project: project
        )

      assert html =~ "Parent Sheet"

      assert html =~
               ~p"/workspaces/#{workspace.slug}/projects/#{project.slug}/sheets/#{parent.id}"

      # Should not have separator for single item (separator is <span class="opacity-50">/</span>)
      refute html =~ "opacity-50"
    end

    test "renders breadcrumb with multiple ancestors", %{project: project, workspace: workspace} do
      grandparent = sheet_fixture(project, %{name: "Grandparent"})
      parent = sheet_fixture(project, %{name: "Parent", parent_id: grandparent.id})

      ancestors =
        [grandparent, parent]
        |> Enum.map(&Repo.preload(&1, :avatar_asset))

      html =
        render_component(&SheetComponents.sheet_breadcrumb/1,
          ancestors: ancestors,
          workspace: workspace,
          project: project
        )

      assert html =~ "Grandparent"
      assert html =~ "Parent"
      # Should have a separator between items
      assert html =~ "/"
    end

    test "renders navigation links for each ancestor", %{
      project: project,
      workspace: workspace
    } do
      ancestor1 = sheet_fixture(project, %{name: "Ancestor1"}) |> Repo.preload(:avatar_asset)
      ancestor2 = sheet_fixture(project, %{name: "Ancestor2"}) |> Repo.preload(:avatar_asset)

      html =
        render_component(&SheetComponents.sheet_breadcrumb/1,
          ancestors: [ancestor1, ancestor2],
          workspace: workspace,
          project: project
        )

      expected_path1 =
        ~p"/workspaces/#{workspace.slug}/projects/#{project.slug}/sheets/#{ancestor1.id}"

      expected_path2 =
        ~p"/workspaces/#{workspace.slug}/projects/#{project.slug}/sheets/#{ancestor2.id}"

      assert html =~ expected_path1
      assert html =~ expected_path2
    end

    test "renders sheet avatars for each ancestor", %{project: project, workspace: workspace} do
      ancestor = sheet_fixture(project, %{name: "Ancestor"}) |> Repo.preload(:avatar_asset)

      html =
        render_component(&SheetComponents.sheet_breadcrumb/1,
          ancestors: [ancestor],
          workspace: workspace,
          project: project
        )

      # Avatar should be rendered in sm size since breadcrumb uses size="sm"
      assert html =~ "size-4"
    end

    test "has correct container styling", %{project: project, workspace: workspace} do
      ancestor = sheet_fixture(project, %{name: "Test"}) |> Repo.preload(:avatar_asset)

      html =
        render_component(&SheetComponents.sheet_breadcrumb/1,
          ancestors: [ancestor],
          workspace: workspace,
          project: project
        )

      assert html =~ "surface-panel"
    end

    test "truncates long ancestor names", %{project: project, workspace: workspace} do
      ancestor = sheet_fixture(project, %{name: "Very Long"}) |> Repo.preload(:avatar_asset)

      html =
        render_component(&SheetComponents.sheet_breadcrumb/1,
          ancestors: [ancestor],
          workspace: workspace,
          project: project
        )

      assert html =~ "truncate"
      assert html =~ "max-w-[120px]"
    end
  end

  # =============================================================================
  # Integration: sheet_breadcrumb renders through LiveView
  # =============================================================================

  describe "sheet_breadcrumb in LiveView" do
    setup :register_and_log_in_user

    test "breadcrumb appears for nested sheet", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      parent = sheet_fixture(project, %{name: "Parent Character"})
      child = sheet_fixture(project, %{name: "Child Character", parent_id: parent.id})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{child.id}"
        )

      html = render_async(view, 500)
      assert html =~ "Parent Character"
    end

    test "no breadcrumb for root-level sheet", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Root Sheet"})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}"
        )

      html = render_async(view, 500)
      # Breadcrumb uses sheet_breadcrumb component which renders ancestor names as links
      # Root-level sheets have no ancestors, so no breadcrumb navigation links appear
      refute html =~ "sheet-breadcrumb"
    end
  end
end

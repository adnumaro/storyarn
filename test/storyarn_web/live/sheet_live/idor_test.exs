defmodule StoryarnWeb.SheetLive.IdorTest do
  @moduledoc """
  Security tests for IDOR (Insecure Direct Object Reference) vulnerabilities
  in the sheet avatar and gallery image subsystem.

  Verifies that users cannot delete or modify resources belonging to sheets
  in other projects, even if they have edit_content permission on their own project.
  """

  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Repo
  alias Storyarn.Sheets

  # ===========================================================================
  # Helpers
  # ===========================================================================

  defp sheet_path(project, sheet) do
    ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}"
  end

  defp mount_sheet(conn, project, sheet) do
    {:ok, view, _html} = live(conn, sheet_path(project, sheet))
    _html = await_async(view)
    view
  end

  defp create_avatar(sheet, project, user) do
    asset = image_asset_fixture(project, user)
    {:ok, avatar} = Sheets.add_avatar(sheet, asset.id)
    avatar
  end

  defp create_gallery_block_with_image(sheet, project, user) do
    block = block_fixture(sheet, %{type: "gallery", config: %{"label" => "Gallery"}})
    asset = image_asset_fixture(project, user)
    {:ok, gallery_image} = Sheets.add_gallery_image(block, asset.id)
    {block, gallery_image}
  end

  # ===========================================================================
  # Cross-project IDOR tests
  # ===========================================================================

  describe "cross-project IDOR: avatars" do
    setup :register_and_log_in_user

    setup %{user: attacker} do
      # Victim's project and sheet with avatar
      victim = user_fixture()
      victim_project = project_fixture(victim) |> Repo.preload(:workspace)
      victim_sheet = sheet_fixture(victim_project, %{name: "Victim Sheet"})
      victim_avatar = create_avatar(victim_sheet, victim_project, victim)

      # Attacker's project (attacker is owner, has edit_content)
      attacker_project = project_fixture(attacker) |> Repo.preload(:workspace)
      attacker_sheet = sheet_fixture(attacker_project, %{name: "Attacker Sheet"})

      %{
        victim_project: victim_project,
        victim_sheet: victim_sheet,
        victim_avatar: victim_avatar,
        attacker_project: attacker_project,
        attacker_sheet: attacker_sheet
      }
    end

    test "cannot delete avatar from another project's sheet",
         %{conn: conn, attacker_project: ap, attacker_sheet: as, victim_avatar: va} do
      view = mount_sheet(conn, ap, as)

      render_hook(view, "remove_avatar", %{"id" => va.id})

      # Victim's avatar must still exist
      assert Sheets.get_avatar(va.id) != nil
    end
  end

  describe "cross-project IDOR: gallery images" do
    setup :register_and_log_in_user

    setup %{user: attacker} do
      victim = user_fixture()
      victim_project = project_fixture(victim) |> Repo.preload(:workspace)
      victim_sheet = sheet_fixture(victim_project, %{name: "Victim Sheet"})
      {_block, victim_gi} = create_gallery_block_with_image(victim_sheet, victim_project, victim)

      attacker_project = project_fixture(attacker) |> Repo.preload(:workspace)
      attacker_sheet = sheet_fixture(attacker_project, %{name: "Attacker Sheet"})

      %{
        victim_project: victim_project,
        victim_sheet: victim_sheet,
        victim_gi: victim_gi,
        attacker_project: attacker_project,
        attacker_sheet: attacker_sheet
      }
    end

    test "cannot delete gallery image from another project",
         %{conn: conn, attacker_project: ap, attacker_sheet: as, victim_gi: vgi} do
      view = mount_sheet(conn, ap, as)

      render_hook(view, "remove_gallery_image", %{"gallery_image_id" => vgi.id})

      assert Sheets.get_gallery_image(vgi.id) != nil
    end

    test "cannot update gallery image from another project",
         %{conn: conn, attacker_project: ap, attacker_sheet: as, victim_gi: vgi} do
      original_label = vgi.label
      view = mount_sheet(conn, ap, as)

      render_hook(view, "update_gallery_image", %{
        "gallery_image_id" => vgi.id,
        "field" => "label",
        "value" => "Hacked label"
      })

      unchanged = Sheets.get_gallery_image(vgi.id)
      assert unchanged.label == original_label
    end
  end

  # ===========================================================================
  # Viewer denial tests
  # ===========================================================================

  describe "viewer cannot modify avatars" do
    setup :register_and_log_in_user

    setup %{user: viewer} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, viewer, "viewer")
      sheet = sheet_fixture(project, %{name: "Shared Sheet"})
      avatar = create_avatar(sheet, project, owner)

      %{project: project, sheet: sheet, avatar: avatar}
    end

    test "viewer cannot delete avatar",
         %{conn: conn, project: p, sheet: s, avatar: a} do
      view = mount_sheet(conn, p, s)

      render_hook(view, "remove_avatar", %{"id" => a.id})

      assert Sheets.get_avatar(a.id) != nil
    end
  end

  describe "viewer cannot modify gallery images" do
    setup :register_and_log_in_user

    setup %{user: viewer} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, viewer, "viewer")
      sheet = sheet_fixture(project, %{name: "Shared Sheet"})
      {_block, gallery_image} = create_gallery_block_with_image(sheet, project, owner)

      %{project: project, sheet: sheet, gallery_image: gallery_image}
    end

    test "viewer cannot delete gallery image",
         %{conn: conn, project: p, sheet: s, gallery_image: gi} do
      view = mount_sheet(conn, p, s)

      render_hook(view, "remove_gallery_image", %{"gallery_image_id" => gi.id})

      assert Sheets.get_gallery_image(gi.id) != nil
    end

    test "viewer cannot update gallery image",
         %{conn: conn, project: p, sheet: s, gallery_image: gi} do
      original_label = gi.label
      view = mount_sheet(conn, p, s)

      render_hook(view, "update_gallery_image", %{
        "gallery_image_id" => gi.id,
        "field" => "label",
        "value" => "Hacked"
      })

      unchanged = Sheets.get_gallery_image(gi.id)
      assert unchanged.label == original_label
    end
  end

  # ===========================================================================
  # Positive tests (verify fixes don't break happy path)
  # ===========================================================================

  describe "owner can manage own avatars" do
    setup :register_and_log_in_user

    setup %{user: owner} do
      project = project_fixture(owner) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "My Sheet"})
      avatar = create_avatar(sheet, project, owner)

      %{project: project, sheet: sheet, avatar: avatar}
    end

    test "owner can delete own avatar",
         %{conn: conn, project: p, sheet: s, avatar: a} do
      view = mount_sheet(conn, p, s)

      render_hook(view, "remove_avatar", %{"id" => a.id})

      assert Sheets.get_avatar(a.id) == nil
    end
  end

  describe "owner can manage own gallery images" do
    setup :register_and_log_in_user

    setup %{user: owner} do
      project = project_fixture(owner) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "My Sheet"})
      {_block, gallery_image} = create_gallery_block_with_image(sheet, project, owner)

      %{project: project, sheet: sheet, gallery_image: gallery_image}
    end

    test "owner can delete own gallery image",
         %{conn: conn, project: p, sheet: s, gallery_image: gi} do
      view = mount_sheet(conn, p, s)

      render_hook(view, "remove_gallery_image", %{"gallery_image_id" => gi.id})

      assert Sheets.get_gallery_image(gi.id) == nil
    end

    test "owner can update own gallery image",
         %{conn: conn, project: p, sheet: s, gallery_image: gi} do
      view = mount_sheet(conn, p, s)

      render_hook(view, "update_gallery_image", %{
        "gallery_image_id" => gi.id,
        "field" => "label",
        "value" => "New label"
      })

      updated = Sheets.get_gallery_image(gi.id)
      assert updated.label == "New label"
    end
  end
end

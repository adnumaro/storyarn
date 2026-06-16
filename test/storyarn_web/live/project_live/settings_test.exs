defmodule StoryarnWeb.ProjectLive.SettingsTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Localization
  alias Storyarn.Projects.Project
  alias Storyarn.Repo

  defp settings_path(project, section \\ nil) do
    base = ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings"
    if section, do: "#{base}/#{section}", else: base
  end

  defp get_general_vue(view) do
    LiveVue.Test.get_vue(view, name: "live/project/settings/ProjectSettingsGeneral")
  end

  defp get_usage_limits_vue(view) do
    LiveVue.Test.get_vue(view, name: "live/project/settings/ProjectSettingsUsageLimits")
  end

  defp get_settings_layout_vue(view) do
    LiveVue.Test.get_vue(view, name: "live/layouts/settings/Layout")
  end

  describe "General section" do
    setup :register_and_log_in_user

    test "renders general settings Vue component", %{conn: conn, user: user} do
      project = user |> project_fixture(%{name: "My Project"}) |> Repo.preload(:workspace)

      {:ok, view, _html} = live(conn, settings_path(project))

      vue = get_general_vue(view)
      assert vue.component == "live/project/settings/ProjectSettingsGeneral"
      assert vue.props["project-details"]["name"] == "My Project"
      assert vue.props["project-details"]["type"] == "game"
      assert vue.props["project-details"]["subtype"] == "rpg"
      assert vue.props["project-metrics-options"]["project_types"] == ["game", "film", "novel", "other"]
      assert vue.props["source-language"]["localeCode"] == "en"
    end

    test "redirects non-owner", %{conn: conn, user: user} do
      owner = user_fixture()
      project = owner |> project_fixture() |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "editor")

      {:error, {:redirect, %{to: path, flash: flash}}} =
        live(conn, settings_path(project))

      assert path =~ "/workspaces/#{project.workspace.slug}/projects/#{project.slug}"
      assert flash["error"] =~ "permission"
    end

    test "updates project details via update_project event", %{conn: conn, user: user} do
      project = user |> project_fixture(%{name: "Old Name"}) |> Repo.preload(:workspace)

      {:ok, view, _html} = live(conn, settings_path(project))

      html =
        render_click(view, "update_project", %{"project" => %{"name" => "New Name"}})

      assert html =~ "updated successfully"

      vue = get_general_vue(view)
      assert vue.props["project-details"]["name"] == "New Name"
    end

    test "updates project type metadata via update_project event", %{conn: conn, user: user} do
      project = user |> project_fixture(%{name: "Typed Project"}) |> Repo.preload(:workspace)

      {:ok, view, _html} = live(conn, settings_path(project))

      html =
        render_click(view, "update_project", %{
          "project" => %{
            "name" => "Typed Project",
            "description" => project.description || "",
            "project_type" => "film",
            "project_subtype" => "short_film",
            "project_type_other" => ""
          }
        })

      assert html =~ "updated successfully"

      project = Repo.get!(Project, project.id)
      assert project.project_type == "film"
      assert project.project_subtype == "short_film"

      vue = get_general_vue(view)
      assert vue.props["project-details"]["type"] == "film"
      assert vue.props["project-details"]["subtype"] == "short_film"
    end

    test "updates the project source language via change_source_language event", %{
      conn: conn,
      user: user
    } do
      project = user |> project_fixture() |> Repo.preload(:workspace)

      {:ok, view, _html} = live(conn, settings_path(project))

      html = render_click(view, "change_source_language", %{"locale_code" => "es-419"})

      assert html =~ "Source language updated."

      vue = get_general_vue(view)
      assert vue.props["source-language"]["localeCode"] == "es-419"

      source_language = Localization.get_source_language(project.id)
      assert source_language.locale_code == "es-419"
      assert Localization.get_language_by_locale(project.id, "en") == nil
    end

    test "deletes project via delete_project event", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)

      {:ok, view, _html} = live(conn, settings_path(project))

      render_click(view, "delete_project")

      {path, flash} = assert_redirect(view)
      assert path == "/workspaces/#{project.workspace.slug}"
      assert flash["info"] =~ "deleted"
    end
  end

  describe "Members section" do
    setup :register_and_log_in_user

    test "passes members list to Vue", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      member = user_fixture(%{email: "member@example.com"})
      _membership = membership_fixture(project, member, "editor")

      {:ok, view, _html} = live(conn, settings_path(project, "members"))

      vue = LiveVue.Test.get_vue(view, name: "live/project/settings/ProjectSettingsMembers")
      assert vue.component == "live/project/settings/ProjectSettingsMembers"
      members = vue.props["members"]
      assert Enum.any?(members, fn m -> m["email"] == user.email end)
      assert Enum.any?(members, fn m -> m["email"] == "member@example.com" end)
    end

    test "sends invitation request via invite_member event", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)

      {:ok, view, _html} = live(conn, settings_path(project, "members"))

      html =
        render_click(view, "send_invitation", %{
          "invite" => %{"email" => "newmember@example.com", "role" => "editor"}
        })

      assert html =~ "Invitation request sent"
    end

    test "removes member via remove_member event", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      member = user_fixture(%{email: "removeme@example.com"})
      membership = membership_fixture(project, member, "editor")

      {:ok, view, _html} = live(conn, settings_path(project, "members"))

      vue = LiveVue.Test.get_vue(view, name: "live/project/settings/ProjectSettingsMembers")
      assert Enum.any?(vue.props["members"], fn m -> m["email"] == "removeme@example.com" end)

      render_click(view, "remove_member", %{"id" => to_string(membership.id)})

      vue = LiveVue.Test.get_vue(view, name: "live/project/settings/ProjectSettingsMembers")
      refute Enum.any?(vue.props["members"], fn m -> m["email"] == "removeme@example.com" end)
    end
  end

  describe "Usage limits section" do
    setup :register_and_log_in_user

    test "passes project and workspace usage limits to Vue", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      _sheet = sheet_fixture(project)
      flow = flow_fixture(project)
      _node = node_fixture(flow)
      _scene = scene_fixture(project)
      _asset = asset_fixture(project, user, %{size: 2_048})

      {:ok, view, _html} = live(conn, settings_path(project, "usage-limits"))

      layout = get_settings_layout_vue(view)

      assert layout.props["current-path"] ==
               "/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings/usage-limits"

      vue = get_usage_limits_vue(view)
      assert vue.component == "live/project/settings/ProjectSettingsUsageLimits"

      usage = vue.props["usage-limits"]
      assert usage["plan"] == %{"key" => "free", "name" => "Free"}
      assert usage["project"]["items"] == %{"used" => 6, "limit" => 700}

      assert usage["itemBreakdown"] == %{
               "sheets" => 1,
               "flows" => 1,
               "scenes" => 1,
               "flowNodes" => 3
             }

      assert usage["storage"] == %{"projectBytes" => 2_048, "assetCount" => 1}

      assert usage["workspace"]["storageBytes"] == %{
               "used" => 2_048,
               "limit" => 262_144_000
             }
    end

    test "redirects non-owner", %{conn: conn, user: user} do
      owner = user_fixture()
      project = owner |> project_fixture() |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "editor")

      {:error, {:redirect, %{to: path, flash: flash}}} =
        live(conn, settings_path(project, "usage-limits"))

      assert path =~ "/workspaces/#{project.workspace.slug}/projects/#{project.slug}"
      assert flash["error"] =~ "permission"
    end
  end
end

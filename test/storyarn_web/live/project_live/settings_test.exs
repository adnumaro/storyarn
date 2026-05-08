defmodule StoryarnWeb.ProjectLive.SettingsTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Localization
  alias Storyarn.Repo

  defp settings_path(project, section \\ nil) do
    base = ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings"
    if section, do: "#{base}/#{section}", else: base
  end

  defp get_general_vue(view) do
    LiveVue.Test.get_vue(view, name: "modules/projects/settings/General")
  end

  describe "General section" do
    setup :register_and_log_in_user

    test "renders general settings Vue component", %{conn: conn, user: user} do
      project = user |> project_fixture(%{name: "My Project"}) |> Repo.preload(:workspace)

      {:ok, view, _html} = live(conn, settings_path(project))

      vue = get_general_vue(view)
      assert vue.component == "modules/projects/settings/General"
      assert vue.props["project-name"] == "My Project"
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
      assert vue.props["project-name"] == "New Name"
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

      vue = LiveVue.Test.get_vue(view, name: "modules/projects/settings/Members")
      assert vue.component == "modules/projects/settings/Members"
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

      vue = LiveVue.Test.get_vue(view, name: "modules/projects/settings/Members")
      assert Enum.any?(vue.props["members"], fn m -> m["email"] == "removeme@example.com" end)

      render_click(view, "remove_member", %{"id" => to_string(membership.id)})

      vue = LiveVue.Test.get_vue(view, name: "modules/projects/settings/Members")
      refute Enum.any?(vue.props["members"], fn m -> m["email"] == "removeme@example.com" end)
    end
  end
end

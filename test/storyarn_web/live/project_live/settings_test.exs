defmodule StoryarnWeb.ProjectLive.SettingsTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.LocalizationFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.SheetsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.Localization
  alias Storyarn.Projects
  alias Storyarn.Projects.Project
  alias Storyarn.Projects.ProjectInvitation
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

      assert vue.props["source-language"] == %{
               "flagCode" => "gb",
               "label" => "English",
               "languageTag" => "en",
               "localeCode" => "en",
               "shortLabel" => "EN",
               "value" => "en"
             }

      assert %{
               "flagCode" => "us",
               "label" => "English (US)",
               "languageTag" => "en-US",
               "shortLabel" => "EN",
               "value" => "en-us"
             } in vue.props["source-language-options"]
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

      previous_source = Localization.get_language_by_locale(project.id, "en")
      refute previous_source.is_source
      assert previous_source.archived_at == nil
    end

    test "resets translations only after explicit confirmation when changing source language", %{
      conn: conn,
      user: user
    } do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      text = localized_text_fixture(project.id)

      {:ok, view, _html} = live(conn, settings_path(project))

      html =
        render_click(view, "change_source_language", %{
          "locale_code" => "es",
          "reset_translations" => true
        })

      assert html =~ "Source language updated."
      assert Localization.get_source_language(project.id).locale_code == "es"
      assert Localization.get_text(project.id, text.id) == nil
    end

    test "does not coerce arbitrary reset values when changing source language", %{
      conn: conn,
      user: user
    } do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      text = localized_text_fixture(project.id)

      {:ok, view, _html} = live(conn, settings_path(project))

      html =
        render_click(view, "change_source_language", %{
          "locale_code" => "es",
          "reset_translations" => "yes"
        })

      assert html =~ "Could not update the source language."
      assert Localization.get_source_language(project.id).locale_code == "en"
      assert Localization.get_text(project.id, text.id)
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

    test "sends an invitation directly to the project member", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)

      {:ok, view, _html} = live(conn, settings_path(project, "members"))

      html =
        render_click(view, "send_invitation", %{
          "invite" => %{"email" => "newmember@example.com", "role" => "editor"}
        })

      assert html =~ "Invitation queued for delivery"
      assert_push_event(view, "invitation_sent", %{})

      assert [invitation] = Projects.list_pending_invitations(project.id)
      assert invitation.email == "newmember@example.com"
      assert invitation.invited_by_id == user.id

      vue = LiveVue.Test.get_vue(view, name: "live/project/settings/ProjectSettingsMembers")

      assert [%{"id" => invitation_id, "email" => "newmember@example.com"}] =
               vue.props["pending-invitations"]

      assert invitation_id == invitation.id
    end

    test "shows the plan limit after the remaining project seat is reserved", %{
      conn: conn,
      user: user
    } do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      {:ok, view, _html} = live(conn, settings_path(project, "members"))

      render_click(view, "send_invitation", %{
        "invite" => %{"email" => "first@example.com", "role" => "editor"}
      })

      html =
        render_click(view, "send_invitation", %{
          "invite" => %{"email" => "second@example.com", "role" => "viewer"}
        })

      assert html =~ "Member limit reached for your plan"

      assert Enum.map(Projects.list_pending_invitations(project.id), & &1.email) == [
               "first@example.com"
             ]
    end

    test "revokes a pending project invitation and releases its seat", %{
      conn: conn,
      user: user
    } do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      {:ok, view, _html} = live(conn, settings_path(project, "members"))

      render_click(view, "send_invitation", %{
        "invite" => %{"email" => "revoke-project@example.com", "role" => "editor"}
      })

      [invitation] = Projects.list_pending_invitations(project.id)

      result =
        render_click(view, "revoke_invitation", %{"id" => to_string(invitation.id)})

      assert result =~ "Invitation revoked"
      assert Projects.list_pending_invitations(project.id) == []

      vue = LiveVue.Test.get_vue(view, name: "live/project/settings/ProjectSettingsMembers")
      assert vue.props["pending-invitations"] == []
    end

    test "does not revoke an invitation from another project", %{conn: conn, user: user} do
      workspace = workspace_fixture(user)
      project = user |> project_fixture(%{workspace: workspace}) |> Repo.preload(:workspace)
      other_project = project_fixture(user, %{workspace: workspace})

      assert {:ok, other_invitation} =
               Projects.create_invitation(
                 other_project,
                 user,
                 "other-project@example.com",
                 "editor"
               )

      {:ok, view, _html} = live(conn, settings_path(project, "members"))

      result =
        render_click(view, "revoke_invitation", %{"id" => to_string(other_invitation.id)})

      assert result =~ "Invitation not found"
      assert [%{id: invitation_id}] = Projects.list_pending_invitations(other_project.id)
      assert invitation_id == other_invitation.id
    end

    test "a members socket cannot invite after the project is deleted", %{
      conn: conn,
      user: user
    } do
      project = user |> project_fixture() |> Repo.preload(:workspace)
      {:ok, view, _html} = live(conn, settings_path(project, "members"))

      render_click(view, "send_invitation", %{
        "invite" => %{"email" => "deleted-project@example.com", "role" => "editor"}
      })

      assert [invitation] = Projects.list_pending_invitations(project.id)
      assert {:ok, _deleted_project} = Projects.delete_project(project, user.id)
      refute Repo.get(ProjectInvitation, invitation.id)

      result =
        render_click(view, "send_invitation", %{
          "invite" => %{"email" => "after-delete@example.com", "role" => "editor"}
        })

      assert result =~ "permission to manage this project"
      assert Projects.list_pending_invitations(project.id) == []
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

    test "shows a pending invitation as an occupied member seat", %{conn: conn, user: user} do
      project = user |> project_fixture() |> Repo.preload(:workspace)

      assert {:ok, _invitation} =
               Projects.create_invitation(
                 project,
                 user,
                 "usage-pending@example.com",
                 "editor"
               )

      {:ok, view, _html} = live(conn, settings_path(project, "usage-limits"))
      vue = LiveVue.Test.get_vue(view, name: "live/project/settings/ProjectSettingsUsageLimits")

      assert vue.props["usage-limits"]["workspace"]["members"] == %{
               "used" => 2,
               "limit" => 2
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

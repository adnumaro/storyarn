defmodule StoryarnWeb.SheetLive.Handlers.HistoryHandlersTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Phoenix.LiveView.Socket
  alias Storyarn.Accounts.Scope
  alias Storyarn.Repo
  alias Storyarn.Sheets
  alias Storyarn.Versioning
  alias StoryarnWeb.SheetLive.Handlers.HistoryHandlers

  setup :register_and_log_in_user

  setup %{user: user} do
    project = user |> project_fixture() |> Repo.preload(:workspace)
    sheet = sheet_fixture(project, %{name: "History Sheet"})

    url = ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}"

    %{project: project, sheet: sheet, url: url}
  end

  defp mount_sheet(conn, url) do
    {:ok, view, _html} = live(conn, url)
    await_async(view)
    view
  end

  describe "create_version event" do
    test "creates a named version", %{conn: conn, url: url, sheet: sheet} do
      view = mount_sheet(conn, url)

      render_click(view, "create_version", %{
        "title" => "First milestone",
        "description" => "Initial playable sheet"
      })

      version = Versioning.get_version("sheet", sheet.id, 1)
      assert version.title == "First milestone"
      assert version.description == "Initial playable sheet"
      refute version.is_auto
    end

    test "requires a title", %{conn: conn, url: url, sheet: sheet} do
      view = mount_sheet(conn, url)

      render_click(view, "create_version", %{"title" => "", "description" => "Ignored"})

      assert Versioning.count_versions("sheet", sheet.id) == 0
    end
  end

  describe "promote_version event" do
    test "updates version title and description", %{conn: conn, user: user, project: project, url: url, sheet: sheet} do
      {:ok, version} =
        Versioning.create_version("sheet", sheet, project.id, user.id, is_auto: true)

      view = mount_sheet(conn, url)

      render_click(view, "promote_version", %{
        "version_number" => to_string(version.version_number),
        "title" => "Named checkpoint",
        "description" => "Ready for review"
      })

      updated = Versioning.get_version("sheet", sheet.id, version.version_number)
      assert updated.title == "Named checkpoint"
      assert updated.description == "Ready for review"
    end
  end

  describe "delete_version event" do
    test "deletes an existing version", %{conn: conn, user: user, project: project, url: url, sheet: sheet} do
      {:ok, version} =
        Versioning.create_version("sheet", sheet, project.id, user.id, title: "Disposable")

      view = mount_sheet(conn, url)

      render_click(view, "delete_version", %{"version_number" => to_string(version.version_number)})

      refute Versioning.get_version("sheet", sheet.id, version.version_number)
    end

    test "does not crash for a missing version", %{conn: conn, url: url, sheet: sheet} do
      view = mount_sheet(conn, url)

      html = render_click(view, "delete_version", %{"version_number" => "999"})

      assert html =~ "History Sheet"
      assert Versioning.count_versions("sheet", sheet.id) == 0
    end
  end

  describe "confirm_restore event" do
    test "restores the sheet from the selected version", %{
      conn: conn,
      user: user,
      project: project,
      url: url,
      sheet: sheet
    } do
      {:ok, version} =
        Versioning.create_version("sheet", sheet, project.id, user.id, title: "Before rename")

      {:ok, _changed_sheet} = Sheets.update_sheet(sheet, %{name: "Changed Sheet"})

      view = mount_sheet(conn, url)

      render_click(view, "confirm_restore", %{
        "version_number" => to_string(version.version_number),
        "skip_pre_snapshot" => true
      })

      restored = Sheets.get_sheet(project.id, sheet.id)
      assert restored.name == "History Sheet"

      versions = Versioning.list_versions("sheet", sheet.id)
      assert length(versions) == 3
      assert Enum.any?(versions, &(&1.title =~ "Before restore"))
      assert Enum.any?(versions, &(&1.title =~ "Restored from"))
    end

    test "explains concurrent changes and missing safety backups", %{
      user: user,
      project: project,
      sheet: sheet
    } do
      {:ok, version} =
        Versioning.create_version("sheet", sheet, project.id, user.id, title: "Restore target")

      cases = [
        {:sheet_changed_since_pre_restore_snapshot,
         "The sheet changed while restore was being prepared. Review the latest changes and try again."},
        {:pre_restore_version_not_durable,
         "The safety backup is no longer available. Restore was aborted. Please try again."}
      ]

      for {reason, message} <- cases do
        socket = handler_socket(user, project, sheet)

        helpers = %{
          restore_version: fn "sheet", received_sheet, received_version, opts ->
            assert received_sheet.id == sheet.id
            assert received_version.id == version.id
            assert opts[:user_id] == user.id
            {:error, reason}
          end
        }

        assert {:noreply, result} =
                 HistoryHandlers.handle_confirm_restore(
                   %{"version_number" => to_string(version.version_number)},
                   socket,
                   helpers
                 )

        assert result.assigns.flash["error"] == message
      end
    end
  end

  defp handler_socket(user, project, sheet) do
    %Socket{
      assigns: %{
        __changed__: %{},
        flash: %{},
        current_scope: Scope.for_user(user),
        membership: %{role: "owner"},
        project: project,
        sheet: sheet
      }
    }
  end
end

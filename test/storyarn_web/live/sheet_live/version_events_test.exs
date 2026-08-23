defmodule StoryarnWeb.SheetLive.VersionEventsTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Phoenix.LiveView.Socket
  alias Storyarn.Accounts.Scope
  alias Storyarn.Repo
  alias Storyarn.Sheets
  alias StoryarnWeb.SheetLive.VersionEvents

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

      version = Sheets.get_version(sheet.id, 1)
      assert version.title == "First milestone"
      assert version.description == "Initial playable sheet"
      refute version.is_auto
    end

    test "requires a title", %{conn: conn, url: url, sheet: sheet} do
      view = mount_sheet(conn, url)

      render_click(view, "create_version", %{"title" => "", "description" => "Ignored"})

      assert Sheets.count_versions(sheet.id) == 0
    end
  end

  describe "promote_version event" do
    test "updates version title and description", %{conn: conn, user: user, url: url, sheet: sheet} do
      {:ok, version} = Sheets.create_version(sheet, user.id, is_auto: true)

      view = mount_sheet(conn, url)

      render_click(view, "promote_version", %{
        "version_number" => to_string(version.version_number),
        "title" => "Named checkpoint",
        "description" => "Ready for review"
      })

      updated = Sheets.get_version(sheet.id, version.version_number)
      assert updated.title == "Named checkpoint"
      assert updated.description == "Ready for review"
    end
  end

  describe "delete_version event" do
    test "deletes an existing version", %{conn: conn, user: user, url: url, sheet: sheet} do
      {:ok, version} = Sheets.create_version(sheet, user.id, title: "Disposable")

      view = mount_sheet(conn, url)

      render_click(view, "delete_version", %{"version_number" => to_string(version.version_number)})

      refute Sheets.get_version(sheet.id, version.version_number)
    end

    test "does not crash for a missing version", %{conn: conn, url: url, sheet: sheet} do
      view = mount_sheet(conn, url)

      html = render_click(view, "delete_version", %{"version_number" => "999"})

      assert html =~ "History Sheet"
      assert Sheets.count_versions(sheet.id) == 0
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
      {:ok, version} = Sheets.create_version(sheet, user.id, title: "Before rename")

      {:ok, _changed_sheet} = Sheets.update_sheet(sheet, %{name: "Changed Sheet"})

      view = mount_sheet(conn, url)

      render_click(view, "confirm_restore", %{
        "version_number" => to_string(version.version_number),
        "request_id" => "sheet-confirm-request"
      })

      assert_push_event(view, "version_restored", %{request_id: "sheet-confirm-request"})

      restored = Sheets.get_sheet(project.id, sheet.id)
      assert restored.name == "History Sheet"

      versions = Sheets.list_versions(sheet.id)
      assert length(versions) == 3
      assert Enum.any?(versions, &(&1.title =~ "Before restore"))
      assert Enum.any?(versions, &(&1.title =~ "Restored from"))
    end
  end

  describe "restore request correlation" do
    test "echoes request IDs from preview and review events", %{
      conn: conn,
      user: user,
      url: url,
      sheet: sheet
    } do
      {:ok, version} = Sheets.create_version(sheet, user.id, title: "Restore target")

      {:ok, _changed_sheet} = Sheets.update_sheet(sheet, %{name: "Changed before preview"})

      view = mount_sheet(conn, url)

      render_click(view, "preview_restore", %{
        "version_number" => to_string(version.version_number),
        "request_id" => "sheet-preview-request"
      })

      assert_push_event(view, "show_unsaved_modal", %{request_id: "sheet-preview-request"})

      render_click(view, "review_restore", %{
        "version_number" => to_string(version.version_number),
        "request_id" => "sheet-review-request"
      })

      assert_push_event(view, "show_restore_modal", %{request_id: "sheet-review-request"})
    end

    test "keeps restore handlers compatible with clients that omit request_id", %{
      user: user,
      project: project,
      sheet: sheet
    } do
      {:ok, version} = Sheets.create_version(sheet, user.id, title: "Restore target")

      socket = handler_socket(user, project, sheet)
      config = sheet_version_config()
      params = %{"version_number" => to_string(version.version_number)}

      assert {:noreply, preview_result} =
               VersionEvents.handle_preview_restore(params, socket, config)

      assert {:noreply, review_result} =
               VersionEvents.handle_review_restore(params, socket, config)

      assert {:noreply, confirm_result} =
               VersionEvents.handle_confirm_restore(params, socket, config)

      preview_event =
        pushed_event(preview_result, "show_unsaved_modal") ||
          pushed_event(preview_result, "show_restore_modal")

      assert preview_event
      assert review_event = pushed_event(review_result, "show_restore_modal")
      assert confirm_event = pushed_event(confirm_result, "version_restored")

      for event <- [preview_event, review_event, confirm_event] do
        payload = pushed_payload(event)
        refute Map.has_key?(payload, :request_id)
        refute Map.has_key?(payload, "request_id")
      end
    end

    test "rejects malformed request IDs before authorization and restore", %{
      user: user,
      project: project,
      sheet: sheet
    } do
      {:ok, version} = Sheets.create_version(sheet, user.id, title: "Restore target")

      owner_socket = handler_socket(user, project, sheet)
      socket = %{owner_socket | assigns: Map.put(owner_socket.assigns, :membership, %{role: "viewer"})}
      config = sheet_version_config()

      for request_id <- [nil, 42, %{}, "", String.duplicate("x", 65)],
          handler <- [
            :handle_preview_restore,
            :handle_review_restore,
            :handle_confirm_restore
          ] do
        params = %{
          "version_number" => to_string(version.version_number),
          "request_id" => request_id
        }

        assert {:noreply, ^socket} = apply(VersionEvents, handler, [params, socket, config])
      end

      refute socket.assigns.flash["error"]
      refute pushed_event(socket, "show_unsaved_modal")
      refute pushed_event(socket, "show_restore_modal")
      refute pushed_event(socket, "version_restored")
      assert Sheets.count_versions(sheet.id) == 1
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
        sheet: sheet,
        workspace: project.workspace
      }
    }
  end

  defp sheet_version_config do
    %{
      reload_blocks: &Function.identity/1,
      clear_undo: &Function.identity/1,
      reload_history: &Function.identity/1,
      broadcast: fn socket, :sheet_restored -> socket end,
      compare_path: fn _socket, _version_number -> "/compare" end
    }
  end

  defp pushed_event(socket, event_name) do
    socket
    |> get_in([Access.key(:private), :live_temp, :push_events])
    |> List.wrap()
    |> Enum.find(fn
      [name, _payload] -> name == event_name
      {name, _payload} -> name == event_name
    end)
  end

  defp pushed_payload([_name, payload]), do: payload
  defp pushed_payload({_name, payload}), do: payload
end

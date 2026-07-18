defmodule StoryarnWeb.SheetLive.Handlers.HeaderHandlersTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AssetsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Phoenix.LiveView.Socket
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Sheets
  alias StoryarnWeb.SheetLive.Handlers.HeaderHandlers

  setup :register_and_log_in_user

  setup %{user: user} do
    project = user |> project_fixture() |> Repo.preload(:workspace)
    sheet = sheet_fixture(project, %{name: "Header Sheet", shortcut: "header-sheet"})

    url = ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}"

    %{project: project, sheet: sheet, url: url}
  end

  defp mount_sheet(conn, url) do
    {:ok, view, _html} = live(conn, url)
    await_async(view)
    view
  end

  describe "save_name event" do
    test "updates the sheet name", %{conn: conn, project: project, sheet: sheet, url: url} do
      view = mount_sheet(conn, url)

      render_click(view, "save_name", %{"name" => "Renamed Header Sheet"})

      updated_sheet = Sheets.get_sheet(project.id, sheet.id)
      assert updated_sheet.name == "Renamed Header Sheet"
    end
  end

  describe "save_shortcut event" do
    test "updates the sheet shortcut", %{conn: conn, project: project, sheet: sheet, url: url} do
      view = mount_sheet(conn, url)

      render_click(view, "save_shortcut", %{"shortcut" => "renamed-header"})

      updated_sheet = Sheets.get_sheet(project.id, sheet.id)
      assert updated_sheet.shortcut == "renamed-header"
    end

    test "normalizes an empty shortcut to nil", %{conn: conn, project: project, sheet: sheet, url: url} do
      view = mount_sheet(conn, url)

      render_click(view, "save_shortcut", %{"shortcut" => ""})

      updated_sheet = Sheets.get_sheet(project.id, sheet.id)
      assert updated_sheet.shortcut == nil
    end

    test "keeps the current shortcut when the new shortcut is invalid", %{
      conn: conn,
      project: project,
      sheet: sheet,
      url: url
    } do
      view = mount_sheet(conn, url)

      render_click(view, "save_shortcut", %{"shortcut" => "Invalid Shortcut!"})

      updated_sheet = Sheets.get_sheet(project.id, sheet.id)
      assert updated_sheet.shortcut == "header-sheet"
    end
  end

  describe "failed asset and avatar writes" do
    test "does not reload or broadcast rejected avatar and banner attachments", %{
      project: project,
      sheet: sheet,
      user: user
    } do
      audio = audio_asset_fixture(project, user)
      socket = handler_socket(project, sheet)
      helpers = tracking_helpers()

      assert {:noreply, _socket} =
               HeaderHandlers.handle_attach_avatar(
                 %{"asset_id" => audio.id},
                 socket,
                 helpers
               )

      refute_received :header_reload
      refute_received {:header_broadcast, _action}
      refute_received {:tree_broadcast, _project_id}
      assert Sheets.list_avatars(sheet.id) == []

      assert {:noreply, _socket} =
               HeaderHandlers.handle_attach_banner(
                 %{"asset_id" => audio.id},
                 socket,
                 helpers
               )

      refute_received :header_reload
      refute_received {:header_broadcast, _action}
      assert is_nil(Sheets.get_sheet(project.id, sheet.id).banner_asset_id)
    end

    test "does not reload or broadcast a failed avatar update or default selection", %{
      project: project,
      sheet: sheet,
      user: user
    } do
      asset = image_asset_fixture(project, user)
      {:ok, avatar} = Sheets.add_avatar(sheet, asset.id, %{name: "original"})

      sheet
      |> Ecto.Changeset.change(deleted_at: TimeHelpers.now())
      |> Repo.update!()

      socket = handler_socket(project, sheet)
      helpers = tracking_helpers()

      assert {:noreply, _socket} =
               HeaderHandlers.handle_gallery_update_name(
                 %{"id" => avatar.id, "value" => "changed"},
                 socket,
                 helpers
               )

      assert {:noreply, _socket} =
               HeaderHandlers.handle_set_default_avatar(
                 %{"id" => avatar.id},
                 socket,
                 helpers
               )

      refute_received :header_reload
      refute_received {:header_broadcast, _action}
      refute_received {:tree_broadcast, _project_id}
      assert Sheets.get_avatar(avatar.id).name == "original"
    end
  end

  defp handler_socket(project, sheet) do
    %Socket{
      assigns: %{
        __changed__: %{},
        flash: %{},
        membership: %{role: "owner"},
        project: project,
        sheet: sheet
      }
    }
  end

  defp tracking_helpers do
    parent = self()

    %{
      parse_id: fn
        id when is_integer(id) -> id
        id when is_binary(id) -> String.to_integer(id)
      end,
      reload_sheet: fn socket ->
        send(parent, :header_reload)
        socket
      end,
      broadcast: fn socket, action ->
        send(parent, {:header_broadcast, action})
        socket
      end,
      broadcast_tree_changed: fn project_id ->
        send(parent, {:tree_broadcast, project_id})
      end
    }
  end
end

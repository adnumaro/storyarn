defmodule StoryarnWeb.SheetLive.Handlers.BlockCrudHandlersTest do
  @moduledoc """
  Integration tests for block CRUD operations in the Sheet LiveView.

  Tests cover the events delegated to BlockCrudHandlers via the ContentTab component:
  - update_block_value: updating block content
  - delete_block: soft-deleting blocks
  """

  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Repo
  alias Storyarn.Sheets

  # ===========================================================================
  # Setup
  # ===========================================================================

  setup :register_and_log_in_user

  setup %{user: user} do
    project = user |> project_fixture() |> Repo.preload(:workspace)
    sheet = sheet_fixture(project, %{name: "Block CRUD Sheet"})
    ws = project.workspace

    url =
      ~p"/workspaces/#{ws.slug}/projects/#{project.slug}/sheets/#{sheet.id}"

    %{project: project, workspace: ws, sheet: sheet, url: url}
  end

  # ===========================================================================
  # Helpers
  # ===========================================================================

  defp mount_sheet(conn, url) do
    {:ok, view, _html} = live(conn, url)
    html = await_async(view)
    {:ok, view, html}
  end

  defp send_to_content_tab(view, event, params) do
    view
    |> with_target("#content-tab")
    |> render_click(event, params)
  end

  # ===========================================================================
  # update_block_value
  # ===========================================================================

  describe "update_block_value" do
    test "updates a text block value", %{conn: conn, url: url, sheet: sheet} do
      block = block_fixture(sheet, %{type: "text"})
      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "update_block_value", %{
        "id" => to_string(block.id),
        "value" => "Hello World"
      })

      updated = Sheets.get_block!(block.id)
      assert updated.value["content"] == "Hello World"
    end

    test "updates a number block value", %{conn: conn, url: url, sheet: sheet} do
      block =
        block_fixture(sheet, %{
          type: "number",
          config: %{"label" => "Health", "placeholder" => ""},
          value: %{"content" => "0"}
        })

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "update_block_value", %{
        "id" => to_string(block.id),
        "value" => "42"
      })

      updated = Sheets.get_block!(block.id)
      assert updated.value["content"] == "42"
    end

    test "updates value multiple times preserving latest", %{
      conn: conn,
      url: url,
      sheet: sheet
    } do
      block = block_fixture(sheet, %{type: "text"})
      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "update_block_value", %{
        "id" => to_string(block.id),
        "value" => "First"
      })

      send_to_content_tab(view, "update_block_value", %{
        "id" => to_string(block.id),
        "value" => "Second"
      })

      send_to_content_tab(view, "update_block_value", %{
        "id" => to_string(block.id),
        "value" => "Third"
      })

      updated = Sheets.get_block!(block.id)
      assert updated.value["content"] == "Third"
    end

    test "returns error for non-existent block without crashing", %{
      conn: conn,
      url: url,
      sheet: sheet
    } do
      block = block_fixture(sheet, %{type: "text", value: %{"content" => "original"}})
      {:ok, view, _html} = mount_sheet(conn, url)

      # Sending update for a non-existent block should not crash the view
      send_to_content_tab(view, "update_block_value", %{
        "id" => "999999",
        "value" => "ghost"
      })

      # View is still alive and the existing block is untouched
      assert render(view) =~ "Block CRUD Sheet"
      assert Sheets.get_block!(block.id).value["content"] == "original"
    end
  end

  # ===========================================================================
  # delete_block
  # ===========================================================================

  describe "delete_block" do
    test "soft-deletes an existing block", %{conn: conn, url: url, sheet: sheet} do
      block = block_fixture(sheet, %{type: "text"})
      assert length(Sheets.list_blocks(sheet.id)) == 1

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "delete_block", %{"id" => to_string(block.id)})

      assert Sheets.list_blocks(sheet.id) == []
    end

    test "returns error for non-existent block without crashing", %{
      conn: conn,
      url: url,
      sheet: sheet
    } do
      block = block_fixture(sheet, %{type: "text"})
      {:ok, view, _html} = mount_sheet(conn, url)

      # Attempting to delete a non-existent block should not crash the view
      send_to_content_tab(view, "delete_block", %{"id" => "999999"})

      # View is still alive and the existing block is untouched
      assert render(view) =~ "Block CRUD Sheet"
      assert length(Sheets.list_blocks(sheet.id)) == 1
      assert Sheets.get_block!(block.id)
    end

    test "deletes one block without affecting others", %{conn: conn, url: url, sheet: sheet} do
      b1 =
        block_fixture(sheet, %{type: "text", config: %{"label" => "Keep", "placeholder" => ""}})

      b2 =
        block_fixture(sheet, %{type: "text", config: %{"label" => "Delete", "placeholder" => ""}})

      assert length(Sheets.list_blocks(sheet.id)) == 2

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "delete_block", %{"id" => to_string(b2.id)})

      remaining = Sheets.list_blocks(sheet.id)
      assert length(remaining) == 1
      assert hd(remaining).id == b1.id
    end

    test "deleting all blocks leaves an empty sheet", %{conn: conn, url: url, sheet: sheet} do
      b1 = block_fixture(sheet, %{type: "text"})
      b2 = block_fixture(sheet, %{type: "number"})
      b3 = block_fixture(sheet, %{type: "boolean"})

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "delete_block", %{"id" => to_string(b1.id)})
      send_to_content_tab(view, "delete_block", %{"id" => to_string(b2.id)})
      send_to_content_tab(view, "delete_block", %{"id" => to_string(b3.id)})

      assert Sheets.list_blocks(sheet.id) == []
    end
  end
end

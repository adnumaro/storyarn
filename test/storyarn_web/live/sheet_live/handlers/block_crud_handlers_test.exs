defmodule StoryarnWeb.SheetLive.Handlers.BlockCrudHandlersTest do
  @moduledoc """
  Integration tests for block CRUD operations in the Sheet LiveView.

  Tests cover the events delegated to BlockCrudHandlers via the ContentTab component:
  - add_block: creating blocks of various types
  - update_block_value: updating block content
  - delete_block: soft-deleting blocks
  - reorder: reordering blocks within a sheet
  """

  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.{Repo, Sheets}

  # ===========================================================================
  # Setup
  # ===========================================================================

  setup :register_and_log_in_user

  setup %{user: user} do
    project = project_fixture(user) |> Repo.preload(:workspace)
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
    live(conn, url)
  end

  defp send_to_content_tab(view, event, params \\ %{}) do
    view
    |> with_target("#content-tab")
    |> render_click(event, params)
  end

  # ===========================================================================
  # add_block
  # ===========================================================================

  describe "add_block" do
    test "creates a text block", %{conn: conn, url: url, sheet: sheet} do
      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "show_block_menu")
      send_to_content_tab(view, "add_block", %{"type" => "text"})

      blocks = Sheets.list_blocks(sheet.id)
      assert length(blocks) == 1
      assert hd(blocks).type == "text"
    end

    test "creates a number block", %{conn: conn, url: url, sheet: sheet} do
      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "show_block_menu")
      send_to_content_tab(view, "add_block", %{"type" => "number"})

      blocks = Sheets.list_blocks(sheet.id)
      assert length(blocks) == 1
      assert hd(blocks).type == "number"
    end

    test "creates a boolean block", %{conn: conn, url: url, sheet: sheet} do
      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "show_block_menu")
      send_to_content_tab(view, "add_block", %{"type" => "boolean"})

      blocks = Sheets.list_blocks(sheet.id)
      assert length(blocks) == 1
      assert hd(blocks).type == "boolean"
    end

    test "creates a select block", %{conn: conn, url: url, sheet: sheet} do
      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "show_block_menu")
      send_to_content_tab(view, "add_block", %{"type" => "select"})

      blocks = Sheets.list_blocks(sheet.id)
      assert length(blocks) == 1
      assert hd(blocks).type == "select"
    end

    test "creates a rich_text block", %{conn: conn, url: url, sheet: sheet} do
      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "show_block_menu")
      send_to_content_tab(view, "add_block", %{"type" => "rich_text"})

      blocks = Sheets.list_blocks(sheet.id)
      assert length(blocks) == 1
      assert hd(blocks).type == "rich_text"
    end

    test "creates a divider block", %{conn: conn, url: url, sheet: sheet} do
      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "show_block_menu")
      send_to_content_tab(view, "add_block", %{"type" => "divider"})

      blocks = Sheets.list_blocks(sheet.id)
      assert length(blocks) == 1
      assert hd(blocks).type == "divider"
    end

    test "creates multiple blocks with sequential positions", %{
      conn: conn,
      url: url,
      sheet: sheet
    } do
      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "show_block_menu")
      send_to_content_tab(view, "add_block", %{"type" => "text"})
      send_to_content_tab(view, "show_block_menu")
      send_to_content_tab(view, "add_block", %{"type" => "number"})
      send_to_content_tab(view, "show_block_menu")
      send_to_content_tab(view, "add_block", %{"type" => "boolean"})

      blocks = Sheets.list_blocks(sheet.id)
      assert length(blocks) == 3

      types = Enum.map(blocks, & &1.type)
      assert types == ["text", "number", "boolean"]

      positions = Enum.map(blocks, & &1.position)
      assert positions == Enum.sort(positions)
    end

    test "new block defaults to 'self' scope", %{conn: conn, url: url, sheet: sheet} do
      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "show_block_menu")
      send_to_content_tab(view, "add_block", %{"type" => "text"})

      block = Sheets.list_blocks(sheet.id) |> hd()
      assert block.scope == "self"
    end
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

    test "clamps number value to min/max constraints", %{
      conn: conn,
      url: url,
      sheet: sheet
    } do
      block =
        block_fixture(sheet, %{
          type: "number",
          config: %{"label" => "Bounded", "placeholder" => "", "min" => 0, "max" => 100},
          value: %{"content" => "50"}
        })

      {:ok, view, _html} = mount_sheet(conn, url)

      # Send a value exceeding the max
      send_to_content_tab(view, "update_block_value", %{
        "id" => to_string(block.id),
        "value" => "200"
      })

      updated = Sheets.get_block!(block.id)
      # The value should be clamped to the max
      assert updated.value["content"] == "100"
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
      assert Sheets.get_block!(block.id) != nil
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

  # ===========================================================================
  # reorder
  # ===========================================================================

  describe "reorder" do
    test "reorders blocks to a new sequence", %{conn: conn, url: url, sheet: sheet} do
      b1 = block_fixture(sheet, %{type: "text", config: %{"label" => "A", "placeholder" => ""}})
      b2 = block_fixture(sheet, %{type: "text", config: %{"label" => "B", "placeholder" => ""}})
      b3 = block_fixture(sheet, %{type: "text", config: %{"label" => "C", "placeholder" => ""}})

      {:ok, view, _html} = mount_sheet(conn, url)

      # Reorder to C, A, B
      new_order = [to_string(b3.id), to_string(b1.id), to_string(b2.id)]
      send_to_content_tab(view, "reorder", %{"ids" => new_order, "group" => "blocks"})

      ids = Sheets.list_blocks(sheet.id) |> Enum.map(& &1.id)
      assert ids == [b3.id, b1.id, b2.id]
    end

    test "reorder with reversed order", %{conn: conn, url: url, sheet: sheet} do
      b1 =
        block_fixture(sheet, %{type: "text", config: %{"label" => "First", "placeholder" => ""}})

      b2 =
        block_fixture(sheet, %{
          type: "number",
          config: %{"label" => "Second", "placeholder" => ""}
        })

      {:ok, view, _html} = mount_sheet(conn, url)

      # Reverse the order
      new_order = [to_string(b2.id), to_string(b1.id)]
      send_to_content_tab(view, "reorder", %{"ids" => new_order, "group" => "blocks"})

      ids = Sheets.list_blocks(sheet.id) |> Enum.map(& &1.id)
      assert ids == [b2.id, b1.id]
    end

    test "reorder to same order is a no-op", %{conn: conn, url: url, sheet: sheet} do
      b1 = block_fixture(sheet, %{type: "text", config: %{"label" => "X", "placeholder" => ""}})
      b2 = block_fixture(sheet, %{type: "text", config: %{"label" => "Y", "placeholder" => ""}})

      {:ok, view, _html} = mount_sheet(conn, url)

      same_order = [to_string(b1.id), to_string(b2.id)]
      send_to_content_tab(view, "reorder", %{"ids" => same_order, "group" => "blocks"})

      ids = Sheets.list_blocks(sheet.id) |> Enum.map(& &1.id)
      assert ids == [b1.id, b2.id]
    end

    test "reorder with single block", %{conn: conn, url: url, sheet: sheet} do
      b1 = block_fixture(sheet, %{type: "text"})

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "reorder", %{"ids" => [to_string(b1.id)], "group" => "blocks"})

      ids = Sheets.list_blocks(sheet.id) |> Enum.map(& &1.id)
      assert ids == [b1.id]
    end
  end

  # ===========================================================================
  # Combined operations
  # ===========================================================================

  describe "combined block operations" do
    test "add, update, then delete a block", %{conn: conn, url: url, sheet: sheet} do
      {:ok, view, _html} = mount_sheet(conn, url)

      # Add
      send_to_content_tab(view, "show_block_menu")
      send_to_content_tab(view, "add_block", %{"type" => "text"})

      blocks = Sheets.list_blocks(sheet.id)
      assert length(blocks) == 1
      block = hd(blocks)

      # Update
      send_to_content_tab(view, "update_block_value", %{
        "id" => to_string(block.id),
        "value" => "Some content"
      })

      updated = Sheets.get_block!(block.id)
      assert updated.value["content"] == "Some content"

      # Delete
      send_to_content_tab(view, "delete_block", %{"id" => to_string(block.id)})
      assert Sheets.list_blocks(sheet.id) == []
    end

    test "add multiple blocks and reorder them", %{conn: conn, url: url, sheet: sheet} do
      {:ok, view, _html} = mount_sheet(conn, url)

      # Add three blocks
      send_to_content_tab(view, "show_block_menu")
      send_to_content_tab(view, "add_block", %{"type" => "text"})
      send_to_content_tab(view, "show_block_menu")
      send_to_content_tab(view, "add_block", %{"type" => "number"})
      send_to_content_tab(view, "show_block_menu")
      send_to_content_tab(view, "add_block", %{"type" => "boolean"})

      blocks = Sheets.list_blocks(sheet.id)
      assert length(blocks) == 3

      [first, second, third] = blocks

      # Reorder to reverse
      new_order = [to_string(third.id), to_string(second.id), to_string(first.id)]
      send_to_content_tab(view, "reorder", %{"ids" => new_order, "group" => "blocks"})

      reordered_ids = Sheets.list_blocks(sheet.id) |> Enum.map(& &1.id)
      assert reordered_ids == [third.id, second.id, first.id]
    end
  end
end

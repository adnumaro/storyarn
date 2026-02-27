defmodule StoryarnWeb.SheetLive.Handlers.BlockToolbarHandlersTest do
  @moduledoc """
  Integration tests for toolbar actions in the Sheet LiveView.

  Tests cover events delegated to BlockToolbarHandlers via the ContentTab component:
  - duplicate_block: duplicating blocks
  - toolbar_toggle_constant: toggling constant flag
  - move_block_up / move_block_down: reordering blocks
  - select_block / deselect_block: block selection state
  """

  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.{Repo, Sheets}

  # ===========================================================================
  # Setup
  # ===========================================================================

  setup :register_and_log_in_user

  setup %{user: user} do
    project = project_fixture(user) |> Repo.preload(:workspace)
    sheet = sheet_fixture(project, %{name: "Toolbar Test Sheet"})
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
    html = render_async(view, 500)
    {:ok, view, html}
  end

  defp send_to_content_tab(view, event, params \\ %{}) do
    view
    |> with_target("#content-tab")
    |> render_click(event, params)
  end

  # ===========================================================================
  # duplicate_block
  # ===========================================================================

  describe "duplicate_block" do
    test "creates a copy at position+1", %{conn: conn, url: url, sheet: sheet} do
      block = block_fixture(sheet, %{type: "text", config: %{"label" => "Name"}, position: 0})
      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "duplicate_block", %{"id" => to_string(block.id)})

      blocks = Sheets.list_blocks(sheet.id)
      assert length(blocks) == 2

      [original, copy] = blocks
      assert original.id == block.id
      assert original.position == 0
      assert copy.position == 1
      assert copy.type == "text"
      assert copy.config["label"] == "Name"
    end

    test "duplicate generates unique variable name", %{conn: conn, url: url, sheet: sheet} do
      block = block_fixture(sheet, %{type: "text", config: %{"label" => "Health"}, position: 0})
      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "duplicate_block", %{"id" => to_string(block.id)})

      blocks = Sheets.list_blocks(sheet.id)
      variable_names = Enum.map(blocks, & &1.variable_name)
      assert length(Enum.uniq(variable_names)) == 2
    end

    test "shifts subsequent block positions", %{conn: conn, url: url, sheet: sheet} do
      b1 = block_fixture(sheet, %{config: %{"label" => "A"}, position: 0})
      b2 = block_fixture(sheet, %{config: %{"label" => "B"}, position: 1})
      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "duplicate_block", %{"id" => to_string(b1.id)})

      blocks = Sheets.list_blocks(sheet.id)
      assert length(blocks) == 3

      b2_updated = Enum.find(blocks, &(&1.id == b2.id))
      assert b2_updated.position == 2
    end
  end

  # ===========================================================================
  # toolbar_toggle_constant
  # ===========================================================================

  describe "toolbar_toggle_constant" do
    test "toggles constant flag and reloads", %{conn: conn, url: url, sheet: sheet} do
      block =
        block_fixture(sheet, %{type: "number", config: %{"label" => "HP"}, is_constant: false})

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "toolbar_toggle_constant", %{"id" => to_string(block.id)})

      updated = Sheets.get_block!(block.id)
      assert updated.is_constant == true
    end

    test "can toggle back to variable", %{conn: conn, url: url, sheet: sheet} do
      block =
        block_fixture(sheet, %{type: "number", config: %{"label" => "HP"}, is_constant: true})

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "toolbar_toggle_constant", %{"id" => to_string(block.id)})

      updated = Sheets.get_block!(block.id)
      assert updated.is_constant == false
    end
  end

  # ===========================================================================
  # move_block_up / move_block_down
  # ===========================================================================

  describe "move_block_up" do
    test "swaps with previous block", %{conn: conn, url: url, sheet: sheet} do
      b1 = block_fixture(sheet, %{config: %{"label" => "A"}, position: 0})
      b2 = block_fixture(sheet, %{config: %{"label" => "B"}, position: 1})
      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "move_block_up", %{"id" => to_string(b2.id)})

      blocks = Sheets.list_blocks(sheet.id)
      ids = Enum.map(blocks, & &1.id)
      assert ids == [b2.id, b1.id]
    end

    test "does nothing for first block", %{conn: conn, url: url, sheet: sheet} do
      b1 = block_fixture(sheet, %{config: %{"label" => "A"}, position: 0})
      _b2 = block_fixture(sheet, %{config: %{"label" => "B"}, position: 1})
      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "move_block_up", %{"id" => to_string(b1.id)})

      blocks = Sheets.list_blocks(sheet.id)
      assert hd(blocks).id == b1.id
    end
  end

  describe "move_block_down" do
    test "swaps with next block", %{conn: conn, url: url, sheet: sheet} do
      b1 = block_fixture(sheet, %{config: %{"label" => "A"}, position: 0})
      b2 = block_fixture(sheet, %{config: %{"label" => "B"}, position: 1})
      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "move_block_down", %{"id" => to_string(b1.id)})

      blocks = Sheets.list_blocks(sheet.id)
      ids = Enum.map(blocks, & &1.id)
      assert ids == [b2.id, b1.id]
    end

    test "does nothing for last block", %{conn: conn, url: url, sheet: sheet} do
      _b1 = block_fixture(sheet, %{config: %{"label" => "A"}, position: 0})
      b2 = block_fixture(sheet, %{config: %{"label" => "B"}, position: 1})
      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "move_block_down", %{"id" => to_string(b2.id)})

      blocks = Sheets.list_blocks(sheet.id)
      assert List.last(blocks).id == b2.id
    end
  end

  # ===========================================================================
  # select_block / deselect_block
  # ===========================================================================

  describe "select_block" do
    test "sets selected_block_id", %{conn: conn, url: url, sheet: sheet} do
      block = block_fixture(sheet, %{config: %{"label" => "A"}})
      {:ok, view, _html} = mount_sheet(conn, url)

      html = send_to_content_tab(view, "select_block", %{"id" => to_string(block.id)})

      assert html =~ "ring-primary/30"
    end
  end

  describe "deselect_block" do
    test "clears selected_block_id", %{conn: conn, url: url, sheet: sheet} do
      block = block_fixture(sheet, %{config: %{"label" => "A"}})
      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "select_block", %{"id" => to_string(block.id)})
      html = send_to_content_tab(view, "deselect_block")

      refute html =~ "ring-primary/30"
    end
  end

  # ===========================================================================
  # delete_block via toolbar
  # ===========================================================================

  describe "delete_block via toolbar" do
    test "deletes block from overflow menu", %{conn: conn, url: url, sheet: sheet} do
      block = block_fixture(sheet, %{config: %{"label" => "A"}})
      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "delete_block", %{"id" => to_string(block.id)})

      assert Sheets.list_blocks(sheet.id) == []
    end
  end

  # ===========================================================================
  # Authorization
  # ===========================================================================

  describe "viewer cannot use toolbar actions" do
    setup %{user: _user, project: project, workspace: ws, sheet: sheet} do
      viewer = user_fixture()

      membership_fixture(project, viewer, "viewer")

      url =
        ~p"/workspaces/#{ws.slug}/projects/#{project.slug}/sheets/#{sheet.id}"

      %{viewer: viewer, viewer_url: url}
    end

    test "viewer cannot duplicate block", %{viewer: viewer, viewer_url: url, sheet: sheet} do
      block = block_fixture(sheet, %{config: %{"label" => "A"}})

      conn = log_in_user(build_conn(), viewer)
      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "duplicate_block", %{"id" => to_string(block.id)})

      # Block should NOT have been duplicated
      assert length(Sheets.list_blocks(sheet.id)) == 1
    end
  end
end

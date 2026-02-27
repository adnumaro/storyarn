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
  # save_config_field
  # ===========================================================================

  describe "save_config_field" do
    test "updates placeholder config field", %{conn: conn, url: url, sheet: sheet} do
      block =
        block_fixture(sheet, %{
          type: "text",
          config: %{"label" => "Name", "placeholder" => "old"},
          position: 0
        })

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "save_config_field", %{
        "block_id" => to_string(block.id),
        "field" => "placeholder",
        "value" => "new placeholder"
      })

      updated = Sheets.get_block!(block.id)
      assert updated.config["placeholder"] == "new placeholder"
    end

    test "updates max_length config field", %{conn: conn, url: url, sheet: sheet} do
      block =
        block_fixture(sheet, %{
          type: "text",
          config: %{"label" => "Name"},
          position: 0
        })

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "save_config_field", %{
        "block_id" => to_string(block.id),
        "field" => "max_length",
        "value" => "200"
      })

      updated = Sheets.get_block!(block.id)
      assert updated.config["max_length"] == 200
    end

    test "normalizes empty max_length to nil", %{conn: conn, url: url, sheet: sheet} do
      block =
        block_fixture(sheet, %{
          type: "text",
          config: %{"label" => "Name", "max_length" => 100},
          position: 0
        })

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "save_config_field", %{
        "block_id" => to_string(block.id),
        "field" => "max_length",
        "value" => ""
      })

      updated = Sheets.get_block!(block.id)
      assert updated.config["max_length"] == nil
    end

    test "updates min on number block", %{conn: conn, url: url, sheet: sheet} do
      block =
        block_fixture(sheet, %{
          type: "number",
          config: %{"label" => "HP"},
          position: 0
        })

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "save_config_field", %{
        "block_id" => to_string(block.id),
        "field" => "min",
        "value" => "0"
      })

      updated = Sheets.get_block!(block.id)
      assert updated.config["min"] == 0.0
    end

    test "updates max on number block", %{conn: conn, url: url, sheet: sheet} do
      block =
        block_fixture(sheet, %{
          type: "number",
          config: %{"label" => "HP"},
          position: 0
        })

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "save_config_field", %{
        "block_id" => to_string(block.id),
        "field" => "max",
        "value" => "100"
      })

      updated = Sheets.get_block!(block.id)
      assert updated.config["max"] == 100.0
    end

    test "normalizes empty min to nil", %{conn: conn, url: url, sheet: sheet} do
      block =
        block_fixture(sheet, %{
          type: "number",
          config: %{"label" => "HP", "min" => 0},
          position: 0
        })

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "save_config_field", %{
        "block_id" => to_string(block.id),
        "field" => "min",
        "value" => ""
      })

      updated = Sheets.get_block!(block.id)
      assert updated.config["min"] == nil
    end

    test "updates step as float", %{conn: conn, url: url, sheet: sheet} do
      block =
        block_fixture(sheet, %{
          type: "number",
          config: %{"label" => "HP"},
          position: 0
        })

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "save_config_field", %{
        "block_id" => to_string(block.id),
        "field" => "step",
        "value" => "0.5"
      })

      updated = Sheets.get_block!(block.id)
      assert updated.config["step"] == 0.5
    end

    test "updates mode on boolean block", %{conn: conn, url: url, sheet: sheet} do
      block =
        block_fixture(sheet, %{
          type: "boolean",
          config: %{"label" => "Is Alive", "mode" => "two_state"},
          position: 0
        })

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "save_config_field", %{
        "block_id" => to_string(block.id),
        "field" => "mode",
        "value" => "tri_state"
      })

      updated = Sheets.get_block!(block.id)
      assert updated.config["mode"] == "tri_state"
    end

    test "updates true_label on boolean block", %{conn: conn, url: url, sheet: sheet} do
      block =
        block_fixture(sheet, %{
          type: "boolean",
          config: %{"label" => "Is Alive"},
          position: 0
        })

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "save_config_field", %{
        "block_id" => to_string(block.id),
        "field" => "true_label",
        "value" => "Alive"
      })

      updated = Sheets.get_block!(block.id)
      assert updated.config["true_label"] == "Alive"
    end

    test "updates false_label on boolean block", %{conn: conn, url: url, sheet: sheet} do
      block =
        block_fixture(sheet, %{
          type: "boolean",
          config: %{"label" => "Is Alive"},
          position: 0
        })

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "save_config_field", %{
        "block_id" => to_string(block.id),
        "field" => "false_label",
        "value" => "Dead"
      })

      updated = Sheets.get_block!(block.id)
      assert updated.config["false_label"] == "Dead"
    end

    test "updates neutral_label on boolean block", %{conn: conn, url: url, sheet: sheet} do
      block =
        block_fixture(sheet, %{
          type: "boolean",
          config: %{"label" => "Is Alive", "mode" => "tri_state"},
          position: 0
        })

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "save_config_field", %{
        "block_id" => to_string(block.id),
        "field" => "neutral_label",
        "value" => "Unknown"
      })

      updated = Sheets.get_block!(block.id)
      assert updated.config["neutral_label"] == "Unknown"
    end
  end

  # ===========================================================================
  # Select option management
  # ===========================================================================

  describe "select option management" do
    test "add_select_option adds new option", %{conn: conn, url: url, sheet: sheet} do
      block =
        block_fixture(sheet, %{
          type: "select",
          config: %{"label" => "Class", "options" => [%{"key" => "a", "value" => "A"}]},
          position: 0
        })

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "add_select_option", %{
        "block_id" => to_string(block.id)
      })

      updated = Sheets.get_block!(block.id)
      assert length(updated.config["options"]) == 2
      assert List.last(updated.config["options"])["key"] == "option_2"
    end

    test "remove_select_option removes option at index", %{
      conn: conn,
      url: url,
      sheet: sheet
    } do
      block =
        block_fixture(sheet, %{
          type: "select",
          config: %{
            "label" => "Class",
            "options" => [
              %{"key" => "a", "value" => "A"},
              %{"key" => "b", "value" => "B"}
            ]
          },
          position: 0
        })

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "remove_select_option", %{
        "block_id" => to_string(block.id),
        "index" => "0"
      })

      updated = Sheets.get_block!(block.id)
      assert length(updated.config["options"]) == 1
      assert hd(updated.config["options"])["key"] == "b"
    end

    test "update_select_option updates key field", %{conn: conn, url: url, sheet: sheet} do
      block =
        block_fixture(sheet, %{
          type: "select",
          config: %{
            "label" => "Class",
            "options" => [%{"key" => "old_key", "value" => "Label"}]
          },
          position: 0
        })

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "update_select_option", %{
        "block_id" => to_string(block.id),
        "index" => "0",
        "key_field" => "key",
        "value" => "new_key"
      })

      updated = Sheets.get_block!(block.id)
      assert hd(updated.config["options"])["key"] == "new_key"
      assert hd(updated.config["options"])["value"] == "Label"
    end

    test "update_select_option updates value field", %{conn: conn, url: url, sheet: sheet} do
      block =
        block_fixture(sheet, %{
          type: "select",
          config: %{
            "label" => "Class",
            "options" => [%{"key" => "warrior", "value" => "Old Label"}]
          },
          position: 0
        })

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "update_select_option", %{
        "block_id" => to_string(block.id),
        "index" => "0",
        "key_field" => "value",
        "value" => "Warrior"
      })

      updated = Sheets.get_block!(block.id)
      assert hd(updated.config["options"])["value"] == "Warrior"
      assert hd(updated.config["options"])["key"] == "warrior"
    end

    test "save_config_field updates max_options on multi_select", %{
      conn: conn,
      url: url,
      sheet: sheet
    } do
      block =
        block_fixture(sheet, %{
          type: "multi_select",
          config: %{"label" => "Tags", "options" => []},
          position: 0
        })

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "save_config_field", %{
        "block_id" => to_string(block.id),
        "field" => "max_options",
        "value" => "3"
      })

      updated = Sheets.get_block!(block.id)
      assert updated.config["max_options"] == 3
    end

    test "normalizes empty max_options to nil", %{conn: conn, url: url, sheet: sheet} do
      block =
        block_fixture(sheet, %{
          type: "multi_select",
          config: %{"label" => "Tags", "options" => [], "max_options" => 3},
          position: 0
        })

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "save_config_field", %{
        "block_id" => to_string(block.id),
        "field" => "max_options",
        "value" => ""
      })

      updated = Sheets.get_block!(block.id)
      assert updated.config["max_options"] == nil
    end
  end

  # ===========================================================================
  # Date config fields
  # ===========================================================================

  describe "date config fields" do
    test "save_config_field updates min_date", %{conn: conn, url: url, sheet: sheet} do
      block =
        block_fixture(sheet, %{
          type: "date",
          config: %{"label" => "Birthday"},
          position: 0
        })

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "save_config_field", %{
        "block_id" => to_string(block.id),
        "field" => "min_date",
        "value" => "2000-01-01"
      })

      updated = Sheets.get_block!(block.id)
      assert updated.config["min_date"] == "2000-01-01"
    end

    test "save_config_field updates max_date", %{conn: conn, url: url, sheet: sheet} do
      block =
        block_fixture(sheet, %{
          type: "date",
          config: %{"label" => "Birthday"},
          position: 0
        })

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "save_config_field", %{
        "block_id" => to_string(block.id),
        "field" => "max_date",
        "value" => "2030-12-31"
      })

      updated = Sheets.get_block!(block.id)
      assert updated.config["max_date"] == "2030-12-31"
    end

    test "clearing min_date sets nil", %{conn: conn, url: url, sheet: sheet} do
      block =
        block_fixture(sheet, %{
          type: "date",
          config: %{"label" => "Birthday", "min_date" => "2000-01-01"},
          position: 0
        })

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "save_config_field", %{
        "block_id" => to_string(block.id),
        "field" => "min_date",
        "value" => ""
      })

      updated = Sheets.get_block!(block.id)
      assert updated.config["min_date"] == nil
    end
  end

  # ===========================================================================
  # Reference allowed types
  # ===========================================================================

  describe "toggle_allowed_type" do
    test "toggling sheet off removes from allowed_types", %{
      conn: conn,
      url: url,
      sheet: sheet
    } do
      block =
        block_fixture(sheet, %{
          type: "reference",
          config: %{"label" => "Link", "allowed_types" => ["sheet", "flow"]},
          position: 0
        })

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "toggle_allowed_type", %{
        "block_id" => to_string(block.id),
        "type" => "sheet"
      })

      updated = Sheets.get_block!(block.id)
      assert updated.config["allowed_types"] == ["flow"]
    end

    test "toggling flow back on adds to allowed_types", %{
      conn: conn,
      url: url,
      sheet: sheet
    } do
      block =
        block_fixture(sheet, %{
          type: "reference",
          config: %{"label" => "Link", "allowed_types" => ["sheet"]},
          position: 0
        })

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "toggle_allowed_type", %{
        "block_id" => to_string(block.id),
        "type" => "flow"
      })

      updated = Sheets.get_block!(block.id)
      assert "flow" in updated.config["allowed_types"]
      assert "sheet" in updated.config["allowed_types"]
    end

    test "cannot remove all types", %{conn: conn, url: url, sheet: sheet} do
      block =
        block_fixture(sheet, %{
          type: "reference",
          config: %{"label" => "Link", "allowed_types" => ["sheet"]},
          position: 0
        })

      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "toggle_allowed_type", %{
        "block_id" => to_string(block.id),
        "type" => "sheet"
      })

      updated = Sheets.get_block!(block.id)
      # Should still have at least the original type
      assert updated.config["allowed_types"] == ["sheet"]
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

  # ===========================================================================
  # Table-specific toolbar actions
  # ===========================================================================

  describe "duplicate_block — table" do
    test "duplicating a table block creates a new table with default structure",
         %{conn: conn, url: url, sheet: sheet} do
      table = table_block_fixture(sheet, %{label: "Inventory"})
      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "duplicate_block", %{"id" => to_string(table.id)})

      blocks = Sheets.list_blocks(sheet.id)
      assert length(blocks) == 2

      copy = Enum.find(blocks, &(&1.id != table.id))
      assert copy.type == "table"
      assert copy.config["label"] == "Inventory"
      assert copy.position == table.position + 1

      # New table should have default structure (1 column + 1 row)
      data = Sheets.batch_load_table_data([copy.id])
      assert length(data[copy.id].columns) == 1
      assert length(data[copy.id].rows) == 1
    end
  end

  describe "move_block_up — table" do
    test "moves a table block up", %{conn: conn, url: url, sheet: sheet} do
      _b1 = block_fixture(sheet, %{config: %{"label" => "Above"}, position: 0})
      table = table_block_fixture(sheet, %{label: "Table"})
      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "move_block_up", %{"id" => to_string(table.id)})

      blocks = Sheets.list_blocks(sheet.id)
      table_updated = Enum.find(blocks, &(&1.id == table.id))
      assert table_updated.position == 0
    end
  end

  describe "move_block_down — table" do
    test "moves a table block down", %{conn: conn, url: url, sheet: sheet} do
      table = table_block_fixture(sheet, %{label: "Table"})
      _b2 = block_fixture(sheet, %{config: %{"label" => "Below"}, position: 1})
      {:ok, view, _html} = mount_sheet(conn, url)

      send_to_content_tab(view, "move_block_down", %{"id" => to_string(table.id)})

      blocks = Sheets.list_blocks(sheet.id)
      table_updated = Enum.find(blocks, &(&1.id == table.id))
      assert table_updated.position == 1
    end
  end
end

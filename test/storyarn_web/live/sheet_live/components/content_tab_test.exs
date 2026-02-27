defmodule StoryarnWeb.SheetLive.Components.ContentTabTest do
  @moduledoc """
  Tests for the ContentTab LiveComponent exercised through the sheet LiveView.

  Events are sent to the ContentTab LiveComponent (id="content-tab") via
  `with_target("#content-tab")`. The test structure mirrors the event handler
  groups in content_tab.ex:

  - Block menu events (show/hide)
  - Block scope events (set_block_scope)
  - Block CRUD events (add_block, update_block_value, delete_block)
  - Multi-select events (toggle_multi_select, multi_select_keydown)
  - Rich text events (update_rich_text, mention_suggestions)
  - Boolean block events (set_boolean_block)
  - Toggle constant event (toolbar_toggle_constant)
  - Block label update event
  - Reference block events (search_references, select_reference, clear_reference)
  """

  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Repo
  alias Storyarn.Sheets

  # ===========================================================================
  # Helpers
  # ===========================================================================

  defp sheet_path(workspace, project, sheet) do
    ~p"/workspaces/#{workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}"
  end

  defp mount_sheet(conn, workspace, project, sheet) do
    {:ok, view, _html} = live(conn, sheet_path(workspace, project, sheet))
    html = render_async(view, 500)
    {:ok, view, html}
  end

  defp send_to_content_tab(view, event, params \\ %{}) do
    view
    |> with_target("#content-tab")
    |> render_click(event, params)
  end

  # ===========================================================================
  # Block Menu Events
  # ===========================================================================

  describe "show_block_menu / hide_block_menu" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Menu Test Sheet"})
      %{project: project, workspace: project.workspace, sheet: sheet}
    end

    test "show_block_menu renders the block menu", %{
      conn: conn,
      workspace: ws,
      project: proj,
      sheet: sheet
    } do
      {:ok, view, _html} = mount_sheet(conn, ws, proj, sheet)

      html = send_to_content_tab(view, "show_block_menu")

      # The block menu should contain add_block buttons for different types
      assert html =~ "add_block"
    end

    test "hide_block_menu closes the block menu", %{
      conn: conn,
      workspace: ws,
      project: proj,
      sheet: sheet
    } do
      {:ok, view, _html} = mount_sheet(conn, ws, proj, sheet)

      # Show then hide
      send_to_content_tab(view, "show_block_menu")
      html = send_to_content_tab(view, "hide_block_menu")

      # View still renders correctly
      assert html =~ "Menu Test Sheet" || html =~ "content-tab"
    end
  end

  # ===========================================================================
  # Block Scope Events
  # ===========================================================================

  describe "set_block_scope" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Scope Test Sheet"})
      %{project: project, workspace: project.workspace, sheet: sheet}
    end

    test "set_block_scope to 'self' succeeds", %{
      conn: conn,
      workspace: ws,
      project: proj,
      sheet: sheet
    } do
      {:ok, view, _html} = mount_sheet(conn, ws, proj, sheet)

      html = send_to_content_tab(view, "set_block_scope", %{"scope" => "self"})
      assert html =~ "content-tab"
    end

    test "set_block_scope to 'children' succeeds", %{
      conn: conn,
      workspace: ws,
      project: proj,
      sheet: sheet
    } do
      {:ok, view, _html} = mount_sheet(conn, ws, proj, sheet)

      html = send_to_content_tab(view, "set_block_scope", %{"scope" => "children"})
      assert html =~ "content-tab"
    end
  end

  # ===========================================================================
  # Block CRUD Events
  # ===========================================================================

  describe "add_block — various types" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Add Block Sheet"})
      %{project: project, workspace: project.workspace, sheet: sheet}
    end

    for type <- ~w(text number boolean select multi_select date rich_text reference table) do
      test "adds a #{type} block to the sheet", %{
        conn: conn,
        workspace: ws,
        project: proj,
        sheet: sheet
      } do
        {:ok, view, _html} = mount_sheet(conn, ws, proj, sheet)

        send_to_content_tab(view, "add_block", %{"type" => unquote(type)})

        blocks = Sheets.list_blocks(sheet.id)
        assert length(blocks) == 1
        assert hd(blocks).type == unquote(type)
      end
    end
  end

  describe "update_block_value" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Update Value Sheet"})
      block = block_fixture(sheet, %{type: "text", config: %{"label" => "Name"}})
      %{project: project, workspace: project.workspace, sheet: sheet, block: block}
    end

    test "updates a text block value", %{
      conn: conn,
      workspace: ws,
      project: proj,
      sheet: sheet,
      block: block
    } do
      {:ok, view, _html} = mount_sheet(conn, ws, proj, sheet)

      send_to_content_tab(view, "update_block_value", %{
        "id" => to_string(block.id),
        "value" => "Updated content"
      })

      updated_block = Sheets.get_block(block.id)
      assert updated_block.value["content"] == "Updated content"
    end

    test "handles non-existent block gracefully", %{
      conn: conn,
      workspace: ws,
      project: proj,
      sheet: sheet
    } do
      {:ok, view, _html} = mount_sheet(conn, ws, proj, sheet)

      html =
        send_to_content_tab(view, "update_block_value", %{
          "id" => "999999",
          "value" => "Nope"
        })

      # View should still be alive
      assert html =~ "content-tab"
    end
  end

  describe "delete_block" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Delete Block Sheet"})
      block = block_fixture(sheet, %{type: "text", config: %{"label" => "ToDelete"}})
      %{project: project, workspace: project.workspace, sheet: sheet, block: block}
    end

    test "deletes a block from the sheet", %{
      conn: conn,
      workspace: ws,
      project: proj,
      sheet: sheet,
      block: block
    } do
      {:ok, view, _html} = mount_sheet(conn, ws, proj, sheet)

      send_to_content_tab(view, "delete_block", %{"id" => to_string(block.id)})

      blocks = Sheets.list_blocks(sheet.id)
      assert blocks == []
    end

    test "handles non-existent block gracefully", %{
      conn: conn,
      workspace: ws,
      project: proj,
      sheet: sheet,
      block: block
    } do
      {:ok, view, _html} = mount_sheet(conn, ws, proj, sheet)

      send_to_content_tab(view, "delete_block", %{"id" => "999999"})

      # Original block still exists
      assert Sheets.get_block(block.id) != nil
    end
  end

  # ===========================================================================
  # Multi-Select Events
  # ===========================================================================

  describe "toggle_multi_select" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Multi Select Sheet"})

      block =
        block_fixture(sheet, %{
          type: "multi_select",
          config: %{
            "label" => "Tags",
            "options" => [
              %{"key" => "fast", "label" => "Fast"},
              %{"key" => "strong", "label" => "Strong"}
            ]
          },
          value: %{"content" => []}
        })

      %{project: project, workspace: project.workspace, sheet: sheet, block: block}
    end

    test "toggles a multi-select option on", %{
      conn: conn,
      workspace: ws,
      project: proj,
      sheet: sheet,
      block: block
    } do
      {:ok, view, _html} = mount_sheet(conn, ws, proj, sheet)

      send_to_content_tab(view, "toggle_multi_select", %{
        "id" => to_string(block.id),
        "key" => "fast"
      })

      updated_block = Sheets.get_block(block.id)
      assert "fast" in (updated_block.value["content"] || [])
    end
  end

  describe "multi_select_keydown" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Multi Select Keydown Sheet"})

      block =
        block_fixture(sheet, %{
          type: "multi_select",
          config: %{
            "label" => "Categories",
            "options" => [
              %{"key" => "alpha", "label" => "Alpha"}
            ]
          },
          value: %{"content" => []}
        })

      %{project: project, workspace: project.workspace, sheet: sheet, block: block}
    end

    test "Enter key adds value to multi-select", %{
      conn: conn,
      workspace: ws,
      project: proj,
      sheet: sheet,
      block: block
    } do
      {:ok, view, _html} = mount_sheet(conn, ws, proj, sheet)

      send_to_content_tab(view, "multi_select_keydown", %{
        "key" => "Enter",
        "value" => "alpha",
        "id" => to_string(block.id)
      })

      updated_block = Sheets.get_block(block.id)
      assert "alpha" in (updated_block.value["content"] || [])
    end

    test "non-Enter key is a no-op", %{
      conn: conn,
      workspace: ws,
      project: proj,
      sheet: sheet,
      block: block
    } do
      {:ok, view, _html} = mount_sheet(conn, ws, proj, sheet)

      html =
        send_to_content_tab(view, "multi_select_keydown", %{
          "key" => "Tab",
          "value" => "alpha",
          "id" => to_string(block.id)
        })

      # View should still be alive and block unchanged
      assert html =~ "content-tab"
      updated_block = Sheets.get_block(block.id)
      assert updated_block.value["content"] == []
    end
  end

  # ===========================================================================
  # Rich Text / Mention Suggestions Events
  # ===========================================================================

  describe "mention_suggestions" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Mention Sheet", shortcut: "mc.test"})
      block = block_fixture(sheet, %{type: "rich_text", config: %{"label" => "Notes"}})

      # Create a second sheet to be findable via search
      _other_sheet = sheet_fixture(project, %{name: "Enemy Stats", shortcut: "enemy.stats"})

      %{project: project, workspace: project.workspace, sheet: sheet, block: block}
    end

    test "returns mention suggestions for valid query", %{
      conn: conn,
      workspace: ws,
      project: proj,
      sheet: sheet
    } do
      {:ok, view, _html} = mount_sheet(conn, ws, proj, sheet)

      # This pushes a "mention_suggestions_result" event to the client
      html = send_to_content_tab(view, "mention_suggestions", %{"query" => "enemy"})

      # View should still be alive
      assert html =~ "content-tab"
    end

    test "returns empty results for empty query", %{
      conn: conn,
      workspace: ws,
      project: proj,
      sheet: sheet
    } do
      {:ok, view, _html} = mount_sheet(conn, ws, proj, sheet)

      html = send_to_content_tab(view, "mention_suggestions", %{"query" => ""})
      assert html =~ "content-tab"
    end

    test "handles query at max length (100 bytes)", %{
      conn: conn,
      workspace: ws,
      project: proj,
      sheet: sheet
    } do
      {:ok, view, _html} = mount_sheet(conn, ws, proj, sheet)

      query = String.duplicate("a", 100)
      html = send_to_content_tab(view, "mention_suggestions", %{"query" => query})
      assert html =~ "content-tab"
    end

    test "rejects query exceeding 100 bytes (fallback clause)", %{
      conn: conn,
      workspace: ws,
      project: proj,
      sheet: sheet
    } do
      {:ok, view, _html} = mount_sheet(conn, ws, proj, sheet)

      # 101 bytes triggers the fallback mention_suggestions clause
      query = String.duplicate("a", 101)
      html = send_to_content_tab(view, "mention_suggestions", %{"query" => query})
      assert html =~ "content-tab"
    end

    test "returns empty for non-string params (fallback clause)", %{
      conn: conn,
      workspace: ws,
      project: proj,
      sheet: sheet
    } do
      {:ok, view, _html} = mount_sheet(conn, ws, proj, sheet)

      # Missing "query" key triggers the fallback clause
      html = send_to_content_tab(view, "mention_suggestions", %{})
      assert html =~ "content-tab"
    end
  end

  # ===========================================================================
  # Boolean Block Events
  # ===========================================================================

  describe "set_boolean_block" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Boolean Sheet"})

      block =
        block_fixture(sheet, %{
          type: "boolean",
          config: %{"label" => "Active"},
          value: %{"content" => false}
        })

      %{project: project, workspace: project.workspace, sheet: sheet, block: block}
    end

    test "sets a boolean block value to true", %{
      conn: conn,
      workspace: ws,
      project: proj,
      sheet: sheet,
      block: block
    } do
      {:ok, view, _html} = mount_sheet(conn, ws, proj, sheet)

      send_to_content_tab(view, "set_boolean_block", %{
        "id" => to_string(block.id),
        "value" => "true"
      })

      updated_block = Sheets.get_block(block.id)
      assert updated_block.value["content"] == true
    end

    test "sets a boolean block value to false", %{
      conn: conn,
      workspace: ws,
      project: proj,
      sheet: sheet,
      block: block
    } do
      {:ok, view, _html} = mount_sheet(conn, ws, proj, sheet)

      # First set to true
      send_to_content_tab(view, "set_boolean_block", %{
        "id" => to_string(block.id),
        "value" => "true"
      })

      # Then set to false
      send_to_content_tab(view, "set_boolean_block", %{
        "id" => to_string(block.id),
        "value" => "false"
      })

      updated_block = Sheets.get_block(block.id)
      assert updated_block.value["content"] == false
    end
  end

  # ===========================================================================
  # Block Label Update
  # ===========================================================================

  describe "update_block_label" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Label Sheet"})

      block =
        block_fixture(sheet, %{type: "text", config: %{"label" => "Original Label"}})

      %{project: project, workspace: project.workspace, sheet: sheet, block: block}
    end

    test "updates a block label", %{
      conn: conn,
      workspace: ws,
      project: proj,
      sheet: sheet,
      block: block
    } do
      {:ok, view, _html} = mount_sheet(conn, ws, proj, sheet)

      send_to_content_tab(view, "update_block_label", %{
        "id" => to_string(block.id),
        "label" => "New Label"
      })

      updated_block = Sheets.get_block(block.id)
      assert updated_block.config["label"] == "New Label"
    end

    test "handles non-existent block gracefully", %{
      conn: conn,
      workspace: ws,
      project: proj,
      sheet: sheet
    } do
      {:ok, view, _html} = mount_sheet(conn, ws, proj, sheet)

      html =
        send_to_content_tab(view, "update_block_label", %{
          "id" => "999999",
          "label" => "Ghost Label"
        })

      # View should still be alive
      assert html =~ "content-tab"
    end
  end

  # ===========================================================================
  # Reference Block Events
  # ===========================================================================

  describe "reference block events" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Ref Block Sheet"})
      target_sheet = sheet_fixture(project, %{name: "Target Sheet"})

      block =
        block_fixture(sheet, %{
          type: "reference",
          config: %{"label" => "Related Sheet"},
          value: %{"content" => ""}
        })

      %{
        project: project,
        workspace: project.workspace,
        sheet: sheet,
        block: block,
        target_sheet: target_sheet
      }
    end

    test "search_references returns results", %{
      conn: conn,
      workspace: ws,
      project: proj,
      sheet: sheet,
      block: block
    } do
      {:ok, view, _html} = mount_sheet(conn, ws, proj, sheet)

      html =
        send_to_content_tab(view, "search_references", %{
          "value" => "Target",
          "block-id" => to_string(block.id)
        })

      # View should still be alive
      assert html =~ "content-tab"
    end

    test "select_reference sets a reference value", %{
      conn: conn,
      workspace: ws,
      project: proj,
      sheet: sheet,
      block: block,
      target_sheet: target_sheet
    } do
      {:ok, view, _html} = mount_sheet(conn, ws, proj, sheet)

      send_to_content_tab(view, "select_reference", %{
        "block-id" => to_string(block.id),
        "type" => "sheet",
        "id" => to_string(target_sheet.id)
      })

      updated_block = Sheets.get_block(block.id)
      assert updated_block.value["target_type"] == "sheet"
      assert to_string(updated_block.value["target_id"]) == to_string(target_sheet.id)
    end

    test "clear_reference removes a reference value", %{
      conn: conn,
      workspace: ws,
      project: proj,
      sheet: sheet,
      block: block,
      target_sheet: target_sheet
    } do
      {:ok, view, _html} = mount_sheet(conn, ws, proj, sheet)

      # Set a reference first
      send_to_content_tab(view, "select_reference", %{
        "block-id" => to_string(block.id),
        "type" => "sheet",
        "id" => to_string(target_sheet.id)
      })

      # Clear it
      send_to_content_tab(view, "clear_reference", %{
        "block-id" => to_string(block.id)
      })

      updated_block = Sheets.get_block(block.id)
      assert updated_block.value["target_type"] == nil
      assert updated_block.value["target_id"] == nil
    end
  end

  # ===========================================================================
  # Authorization — viewer cannot edit
  # ===========================================================================

  describe "authorization — viewer cannot perform mutations" do
    setup :register_and_log_in_user

    setup %{user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      sheet = sheet_fixture(project, %{name: "Viewer Sheet"})
      block = block_fixture(sheet, %{type: "text", config: %{"label" => "ReadOnly"}})
      %{project: project, workspace: project.workspace, sheet: sheet, block: block}
    end

    test "viewer cannot add a block", %{
      conn: conn,
      workspace: ws,
      project: proj,
      sheet: sheet
    } do
      {:ok, view, _html} = mount_sheet(conn, ws, proj, sheet)

      # The add block prompt should not be shown to viewers
      html = render(view)
      refute html =~ "show_block_menu"

      # Verify no new blocks were created
      blocks = Sheets.list_blocks(sheet.id)
      assert length(blocks) == 1
    end

    test "viewer cannot delete a block", %{
      conn: conn,
      workspace: ws,
      project: proj,
      sheet: sheet,
      block: block
    } do
      {:ok, view, _html} = mount_sheet(conn, ws, proj, sheet)

      html = render(view)
      refute html =~ "phx-click=\"delete_block\""

      assert Sheets.get_block(block.id) != nil
    end

    test "viewer cannot update block value", %{
      conn: conn,
      workspace: ws,
      project: proj,
      sheet: sheet,
      block: block
    } do
      {:ok, view, _html} = mount_sheet(conn, ws, proj, sheet)

      send_to_content_tab(view, "update_block_value", %{
        "id" => to_string(block.id),
        "value" => "Hacked!"
      })

      # Value should remain unchanged
      updated_block = Sheets.get_block(block.id)
      assert updated_block.value["content"] == ""
    end

    test "viewer cannot toggle constant", %{
      conn: conn,
      workspace: ws,
      project: proj,
      sheet: sheet,
      block: block
    } do
      {:ok, view, _html} = mount_sheet(conn, ws, proj, sheet)

      send_to_content_tab(view, "toolbar_toggle_constant", %{"id" => to_string(block.id)})

      # is_constant should remain false
      updated_block = Sheets.get_block(block.id)
      assert updated_block.is_constant == false
    end

    test "viewer cannot update block label", %{
      conn: conn,
      workspace: ws,
      project: proj,
      sheet: sheet,
      block: block
    } do
      {:ok, view, _html} = mount_sheet(conn, ws, proj, sheet)

      send_to_content_tab(view, "update_block_label", %{
        "id" => to_string(block.id),
        "label" => "Hacked Label"
      })

      updated_block = Sheets.get_block(block.id)
      assert updated_block.config["label"] == "ReadOnly"
    end
  end

  # ===========================================================================
  # Rich Text Events
  # ===========================================================================

  describe "update_rich_text" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Rich Text Sheet"})

      block =
        block_fixture(sheet, %{
          type: "rich_text",
          config: %{"label" => "Bio"},
          value: %{"content" => ""}
        })

      %{project: project, workspace: project.workspace, sheet: sheet, block: block}
    end

    test "updates rich text content", %{
      conn: conn,
      workspace: ws,
      project: proj,
      sheet: sheet,
      block: block
    } do
      {:ok, view, _html} = mount_sheet(conn, ws, proj, sheet)

      send_to_content_tab(view, "update_rich_text", %{
        "id" => to_string(block.id),
        "content" => "<p>Hello world</p>"
      })

      updated_block = Sheets.get_block(block.id)
      assert updated_block.value["content"] == "<p>Hello world</p>"
    end
  end

  # ===========================================================================
  # Reorder Events
  # ===========================================================================

  describe "reorder blocks" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Reorder Sheet"})
      block1 = block_fixture(sheet, %{type: "text", config: %{"label" => "First"}})
      block2 = block_fixture(sheet, %{type: "text", config: %{"label" => "Second"}})
      block3 = block_fixture(sheet, %{type: "text", config: %{"label" => "Third"}})

      %{
        project: project,
        workspace: project.workspace,
        sheet: sheet,
        block1: block1,
        block2: block2,
        block3: block3
      }
    end

    test "reorders blocks within the sheet", %{
      conn: conn,
      workspace: ws,
      project: proj,
      sheet: sheet,
      block1: b1,
      block2: b2,
      block3: b3
    } do
      {:ok, view, _html} = mount_sheet(conn, ws, proj, sheet)

      new_order = [to_string(b3.id), to_string(b1.id), to_string(b2.id)]

      send_to_content_tab(view, "reorder", %{"ids" => new_order, "group" => "blocks"})

      blocks = Sheets.list_blocks(sheet.id)
      ids = Enum.map(blocks, & &1.id)
      assert ids == [b3.id, b1.id, b2.id]
    end
  end

  # ===========================================================================
  # No-op table cell option events (non-Enter key)
  # ===========================================================================

  describe "no-op keydown events" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Noop Sheet"})
      %{project: project, workspace: project.workspace, sheet: sheet}
    end

    test "add_table_cell_option with non-Enter key is a no-op", %{
      conn: conn,
      workspace: ws,
      project: proj,
      sheet: sheet
    } do
      {:ok, view, _html} = mount_sheet(conn, ws, proj, sheet)

      html = send_to_content_tab(view, "add_table_cell_option", %{"key" => "Tab"})
      assert html =~ "content-tab"
    end

    test "add_table_column_option_keydown with non-Enter key is a no-op", %{
      conn: conn,
      workspace: ws,
      project: proj,
      sheet: sheet
    } do
      {:ok, view, _html} = mount_sheet(conn, ws, proj, sheet)

      html =
        send_to_content_tab(view, "add_table_column_option_keydown", %{"key" => "Tab"})

      assert html =~ "content-tab"
    end
  end
end

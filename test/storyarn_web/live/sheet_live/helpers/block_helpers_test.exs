defmodule StoryarnWeb.SheetLive.Helpers.BlockHelpersTest do
  use Storyarn.DataCase, async: true

  alias StoryarnWeb.SheetLive.Helpers.BlockHelpers

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp build_socket(user, project, sheet) do
    scope = user_scope_fixture(user)

    %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        flash: %{},
        current_scope: scope,
        project: project,
        sheet: sheet,
        blocks: [],
        show_block_menu: true,
        save_status: :idle,
        configuring_block: nil
      },
      private: %{live_temp: %{}}
    }
  end

  defp setup_context(_) do
    user = user_fixture()
    project = project_fixture(user)
    sheet = sheet_fixture(project)
    socket = build_socket(user, project, sheet)

    %{user: user, project: project, sheet: sheet, socket: socket}
  end

  # ---------------------------------------------------------------------------
  # add_block/2
  # ---------------------------------------------------------------------------

  describe "add_block/2" do
    setup :setup_context

    test "creates a text block and returns updated blocks", %{socket: socket} do
      assert {:noreply, socket} = BlockHelpers.add_block(socket, "text")
      assert length(socket.assigns.blocks) == 1
      assert hd(socket.assigns.blocks).type == "text"
      assert socket.assigns.show_block_menu == false
    end

    test "creates a number block", %{socket: socket} do
      assert {:noreply, socket} = BlockHelpers.add_block(socket, "number")
      assert hd(socket.assigns.blocks).type == "number"
    end

    test "creates a select block", %{socket: socket} do
      assert {:noreply, socket} = BlockHelpers.add_block(socket, "select")
      assert hd(socket.assigns.blocks).type == "select"
    end

    test "creates a multi_select block", %{socket: socket} do
      assert {:noreply, socket} = BlockHelpers.add_block(socket, "multi_select")
      assert hd(socket.assigns.blocks).type == "multi_select"
    end

    test "creates a boolean block", %{socket: socket} do
      assert {:noreply, socket} = BlockHelpers.add_block(socket, "boolean")
      assert hd(socket.assigns.blocks).type == "boolean"
    end

    test "creates a rich_text block", %{socket: socket} do
      assert {:noreply, socket} = BlockHelpers.add_block(socket, "rich_text")
      assert hd(socket.assigns.blocks).type == "rich_text"
    end

    test "creates a date block", %{socket: socket} do
      assert {:noreply, socket} = BlockHelpers.add_block(socket, "date")
      assert hd(socket.assigns.blocks).type == "date"
    end

    test "creates a divider block", %{socket: socket} do
      assert {:noreply, socket} = BlockHelpers.add_block(socket, "divider")
      assert hd(socket.assigns.blocks).type == "divider"
    end

    test "hides block menu after successful creation", %{socket: socket} do
      assert {:noreply, socket} = BlockHelpers.add_block(socket, "text")
      assert socket.assigns.show_block_menu == false
    end

    test "hides block menu on error", %{socket: socket} do
      # Invalid block type triggers changeset error
      assert {:noreply, socket} = BlockHelpers.add_block(socket, "nonexistent_type")
      assert socket.assigns.show_block_menu == false
    end

    test "sets flash on invalid block type", %{socket: socket} do
      assert {:noreply, socket} = BlockHelpers.add_block(socket, "nonexistent_type")
      assert socket.assigns.flash["error"] != nil
    end

    test "creates multiple blocks with incremental positions", %{socket: socket} do
      {:noreply, socket} = BlockHelpers.add_block(socket, "text")
      {:noreply, socket} = BlockHelpers.add_block(socket, "number")

      assert length(socket.assigns.blocks) == 2
      [first, second] = socket.assigns.blocks
      assert first.position < second.position
    end
  end

  # ---------------------------------------------------------------------------
  # update_block_value/3
  # ---------------------------------------------------------------------------

  describe "update_block_value/3" do
    setup :setup_context

    test "updates a text block value", %{socket: socket, sheet: sheet} do
      block = block_fixture(sheet, %{type: "text"})

      assert {:noreply, socket} =
               BlockHelpers.update_block_value(socket, block.id, "Hello world")

      assert socket.assigns.save_status == :saved
      updated = Enum.find(socket.assigns.blocks, &(&1.id == block.id))
      assert updated.value["content"] == "Hello world"
    end

    test "updates a number block value", %{socket: socket, sheet: sheet} do
      block = block_fixture(sheet, %{type: "number"})

      assert {:noreply, socket} = BlockHelpers.update_block_value(socket, block.id, 42)
      updated = Enum.find(socket.assigns.blocks, &(&1.id == block.id))
      assert updated.value["content"] == 42
    end

    test "updates with nil value", %{socket: socket, sheet: sheet} do
      block = block_fixture(sheet, %{type: "text"})

      assert {:noreply, socket} = BlockHelpers.update_block_value(socket, block.id, nil)
      updated = Enum.find(socket.assigns.blocks, &(&1.id == block.id))
      assert updated.value["content"] == nil
    end

    test "updates with empty string value", %{socket: socket, sheet: sheet} do
      block = block_fixture(sheet, %{type: "text"})

      assert {:noreply, _socket} = BlockHelpers.update_block_value(socket, block.id, "")
    end

    test "raises when block does not belong to project", %{socket: socket} do
      other_user = user_fixture()
      other_project = project_fixture(other_user)
      other_sheet = sheet_fixture(other_project)
      other_block = block_fixture(other_sheet)

      assert_raise Ecto.NoResultsError, fn ->
        BlockHelpers.update_block_value(socket, other_block.id, "val")
      end
    end
  end

  # ---------------------------------------------------------------------------
  # delete_block/2
  # ---------------------------------------------------------------------------

  describe "delete_block/2" do
    setup :setup_context

    test "soft-deletes a block", %{socket: socket, sheet: sheet} do
      block = block_fixture(sheet, %{type: "text"})

      assert {:noreply, socket} = BlockHelpers.delete_block(socket, block.id)
      assert socket.assigns.blocks == []
      assert socket.assigns.configuring_block == nil
    end

    test "clears configuring_block on successful delete", %{socket: socket, sheet: sheet} do
      block = block_fixture(sheet, %{type: "text"})

      socket = %{socket | assigns: Map.put(socket.assigns, :configuring_block, block)}

      assert {:noreply, socket} = BlockHelpers.delete_block(socket, block.id)
      assert socket.assigns.configuring_block == nil
    end

    test "raises when block does not belong to project", %{socket: socket} do
      other_user = user_fixture()
      other_project = project_fixture(other_user)
      other_sheet = sheet_fixture(other_project)
      other_block = block_fixture(other_sheet)

      assert_raise Ecto.NoResultsError, fn ->
        BlockHelpers.delete_block(socket, other_block.id)
      end
    end

    test "deleted block no longer appears in list", %{socket: socket, sheet: sheet} do
      block1 = block_fixture(sheet, %{type: "text"})
      block2 = block_fixture(sheet, %{type: "number"})

      assert {:noreply, socket} = BlockHelpers.delete_block(socket, block1.id)
      block_ids = Enum.map(socket.assigns.blocks, & &1.id)
      refute block1.id in block_ids
      assert block2.id in block_ids
    end
  end

  # ---------------------------------------------------------------------------
  # reorder_blocks/2
  # ---------------------------------------------------------------------------

  describe "reorder_blocks/2" do
    setup :setup_context

    test "reorders blocks by given id list", %{socket: socket, sheet: sheet} do
      b1 = block_fixture(sheet, %{type: "text"})
      b2 = block_fixture(sheet, %{type: "number"})
      b3 = block_fixture(sheet, %{type: "boolean"})

      # Reverse order
      ids = [b3.id, b1.id, b2.id]
      assert {:noreply, socket} = BlockHelpers.reorder_blocks(socket, ids)

      result_ids = Enum.map(socket.assigns.blocks, & &1.id)
      assert result_ids == [b3.id, b1.id, b2.id]
    end

    test "reorders single block (no-op)", %{socket: socket, sheet: sheet} do
      b1 = block_fixture(sheet, %{type: "text"})
      assert {:noreply, socket} = BlockHelpers.reorder_blocks(socket, [b1.id])
      assert length(socket.assigns.blocks) == 1
    end

    test "empty list reorder", %{socket: socket} do
      assert {:noreply, _socket} = BlockHelpers.reorder_blocks(socket, [])
    end
  end

  # ---------------------------------------------------------------------------
  # toggle_multi_select/3
  # ---------------------------------------------------------------------------

  describe "toggle_multi_select/3" do
    setup :setup_context

    test "selects an option key", %{socket: socket, sheet: sheet} do
      block =
        block_fixture(sheet, %{
          type: "multi_select",
          config: %{
            "label" => "Tags",
            "options" => [
              %{"key" => "red", "value" => "Red"},
              %{"key" => "blue", "value" => "Blue"}
            ]
          },
          value: %{"content" => []}
        })

      assert {:noreply, socket} = BlockHelpers.toggle_multi_select(socket, block.id, "red")
      updated = Enum.find(socket.assigns.blocks, &(&1.id == block.id))
      assert "red" in updated.value["content"]
    end

    test "deselects a previously selected option", %{socket: socket, sheet: sheet} do
      block =
        block_fixture(sheet, %{
          type: "multi_select",
          config: %{
            "label" => "Tags",
            "options" => [%{"key" => "red", "value" => "Red"}]
          },
          value: %{"content" => ["red"]}
        })

      assert {:noreply, socket} = BlockHelpers.toggle_multi_select(socket, block.id, "red")
      updated = Enum.find(socket.assigns.blocks, &(&1.id == block.id))
      refute "red" in updated.value["content"]
    end

    test "adds to existing selections", %{socket: socket, sheet: sheet} do
      block =
        block_fixture(sheet, %{
          type: "multi_select",
          config: %{
            "label" => "Tags",
            "options" => [
              %{"key" => "red", "value" => "Red"},
              %{"key" => "blue", "value" => "Blue"}
            ]
          },
          value: %{"content" => ["red"]}
        })

      assert {:noreply, socket} = BlockHelpers.toggle_multi_select(socket, block.id, "blue")
      updated = Enum.find(socket.assigns.blocks, &(&1.id == block.id))
      assert "blue" in updated.value["content"]
      assert "red" in updated.value["content"]
    end

    test "sets save_status to :saved", %{socket: socket, sheet: sheet} do
      block =
        block_fixture(sheet, %{
          type: "multi_select",
          config: %{"label" => "Tags", "options" => [%{"key" => "x", "value" => "X"}]},
          value: %{"content" => []}
        })

      assert {:noreply, socket} = BlockHelpers.toggle_multi_select(socket, block.id, "x")
      assert socket.assigns.save_status == :saved
    end
  end

  # ---------------------------------------------------------------------------
  # handle_multi_select_enter/3
  # ---------------------------------------------------------------------------

  describe "handle_multi_select_enter/3" do
    setup :setup_context

    test "ignores empty string", %{socket: socket} do
      assert {:noreply, socket} = BlockHelpers.handle_multi_select_enter(socket, 0, "")
      # Socket unchanged
      assert socket.assigns.blocks == []
    end

    test "ignores whitespace-only string", %{socket: socket} do
      assert {:noreply, socket} = BlockHelpers.handle_multi_select_enter(socket, 0, "   ")
      assert socket.assigns.blocks == []
    end

    test "adds a new option and selects it", %{socket: socket, sheet: sheet} do
      block =
        block_fixture(sheet, %{
          type: "multi_select",
          config: %{"label" => "Tags", "options" => []},
          value: %{"content" => []}
        })

      assert {:noreply, socket} =
               BlockHelpers.handle_multi_select_enter(socket, block.id, "NewTag")

      updated = Enum.find(socket.assigns.blocks, &(&1.id == block.id))
      assert "newtag" in updated.value["content"]

      # The option should also appear in config
      option_keys = Enum.map(updated.config["options"], & &1["key"])
      assert "newtag" in option_keys
    end

    test "trims whitespace before adding", %{socket: socket, sheet: sheet} do
      block =
        block_fixture(sheet, %{
          type: "multi_select",
          config: %{"label" => "Tags", "options" => []},
          value: %{"content" => []}
        })

      assert {:noreply, socket} =
               BlockHelpers.handle_multi_select_enter(socket, block.id, "  Padded  ")

      updated = Enum.find(socket.assigns.blocks, &(&1.id == block.id))
      assert "padded" in updated.value["content"]
    end

    test "selects existing option instead of creating duplicate", %{
      socket: socket,
      sheet: sheet
    } do
      block =
        block_fixture(sheet, %{
          type: "multi_select",
          config: %{
            "label" => "Tags",
            "options" => [%{"key" => "existing", "value" => "Existing"}]
          },
          value: %{"content" => []}
        })

      assert {:noreply, socket} =
               BlockHelpers.handle_multi_select_enter(socket, block.id, "Existing")

      updated = Enum.find(socket.assigns.blocks, &(&1.id == block.id))
      assert "existing" in updated.value["content"]
      # Should not duplicate options
      assert length(updated.config["options"]) == 1
    end
  end

  # ---------------------------------------------------------------------------
  # update_rich_text/3
  # ---------------------------------------------------------------------------

  describe "update_rich_text/3" do
    setup :setup_context

    test "updates rich text content", %{socket: socket, sheet: sheet} do
      block = block_fixture(sheet, %{type: "rich_text"})

      html = "<p>Hello <strong>world</strong></p>"
      assert {:noreply, socket} = BlockHelpers.update_rich_text(socket, block.id, html)
      assert socket.assigns.save_status == :saved
    end

    test "updates with empty string", %{socket: socket, sheet: sheet} do
      block = block_fixture(sheet, %{type: "rich_text"})

      assert {:noreply, socket} = BlockHelpers.update_rich_text(socket, block.id, "")
      assert socket.assigns.save_status == :saved
    end

    test "does not reload blocks (preserves editor state)", %{socket: socket, sheet: sheet} do
      block = block_fixture(sheet, %{type: "rich_text"})

      # Start with empty blocks in socket (not loaded)
      socket = %{socket | assigns: Map.put(socket.assigns, :blocks, [])}

      assert {:noreply, socket} = BlockHelpers.update_rich_text(socket, block.id, "content")
      # Blocks are NOT reloaded for rich_text updates
      assert socket.assigns.blocks == []
    end

    test "raises when block does not belong to project", %{socket: socket} do
      other_user = user_fixture()
      other_project = project_fixture(other_user)
      other_sheet = sheet_fixture(other_project)
      other_block = block_fixture(other_sheet, %{type: "rich_text"})

      assert_raise Ecto.NoResultsError, fn ->
        BlockHelpers.update_rich_text(socket, other_block.id, "hacked")
      end
    end
  end

  # ---------------------------------------------------------------------------
  # set_boolean_block/3
  # ---------------------------------------------------------------------------

  describe "set_boolean_block/3" do
    setup :setup_context

    test "sets boolean to true", %{socket: socket, sheet: sheet} do
      block = block_fixture(sheet, %{type: "boolean", value: %{"content" => nil}})

      assert {:noreply, socket} = BlockHelpers.set_boolean_block(socket, block.id, "true")
      updated = Enum.find(socket.assigns.blocks, &(&1.id == block.id))
      assert updated.value["content"] == true
    end

    test "sets boolean to false", %{socket: socket, sheet: sheet} do
      block = block_fixture(sheet, %{type: "boolean", value: %{"content" => nil}})

      assert {:noreply, socket} = BlockHelpers.set_boolean_block(socket, block.id, "false")
      updated = Enum.find(socket.assigns.blocks, &(&1.id == block.id))
      assert updated.value["content"] == false
    end

    test "sets boolean to nil with 'null' string", %{socket: socket, sheet: sheet} do
      block = block_fixture(sheet, %{type: "boolean", value: %{"content" => true}})

      assert {:noreply, socket} = BlockHelpers.set_boolean_block(socket, block.id, "null")
      updated = Enum.find(socket.assigns.blocks, &(&1.id == block.id))
      assert updated.value["content"] == nil
    end

    test "unknown value string maps to nil", %{socket: socket, sheet: sheet} do
      block = block_fixture(sheet, %{type: "boolean", value: %{"content" => true}})

      assert {:noreply, socket} = BlockHelpers.set_boolean_block(socket, block.id, "garbage")
      updated = Enum.find(socket.assigns.blocks, &(&1.id == block.id))
      assert updated.value["content"] == nil
    end

    test "sets save_status to :saved", %{socket: socket, sheet: sheet} do
      block = block_fixture(sheet, %{type: "boolean", value: %{"content" => nil}})

      assert {:noreply, socket} = BlockHelpers.set_boolean_block(socket, block.id, "true")
      assert socket.assigns.save_status == :saved
    end

    test "toggles from true to false", %{socket: socket, sheet: sheet} do
      block = block_fixture(sheet, %{type: "boolean", value: %{"content" => true}})

      assert {:noreply, socket} = BlockHelpers.set_boolean_block(socket, block.id, "false")
      updated = Enum.find(socket.assigns.blocks, &(&1.id == block.id))
      assert updated.value["content"] == false
    end
  end

  # ---------------------------------------------------------------------------
  # Delegated BlockValueHelpers functions
  # ---------------------------------------------------------------------------

  describe "toggle_multi_select_value/3 (delegated)" do
    setup :setup_context

    test "returns {:ok, blocks} on successful toggle", %{socket: socket, sheet: sheet} do
      block =
        block_fixture(sheet, %{
          type: "multi_select",
          config: %{
            "label" => "Tags",
            "options" => [%{"key" => "a", "value" => "A"}]
          },
          value: %{"content" => []}
        })

      assert {:ok, blocks} =
               BlockHelpers.toggle_multi_select_value(socket, block.id, "a")

      updated = Enum.find(blocks, &(&1.id == block.id))
      assert "a" in updated.value["content"]
    end

    test "deselects when already selected", %{socket: socket, sheet: sheet} do
      block =
        block_fixture(sheet, %{
          type: "multi_select",
          config: %{
            "label" => "Tags",
            "options" => [%{"key" => "a", "value" => "A"}]
          },
          value: %{"content" => ["a"]}
        })

      assert {:ok, blocks} =
               BlockHelpers.toggle_multi_select_value(socket, block.id, "a")

      updated = Enum.find(blocks, &(&1.id == block.id))
      refute "a" in updated.value["content"]
    end

    test "handles string block_id", %{socket: socket, sheet: sheet} do
      block =
        block_fixture(sheet, %{
          type: "multi_select",
          config: %{
            "label" => "Tags",
            "options" => [%{"key" => "a", "value" => "A"}]
          },
          value: %{"content" => []}
        })

      assert {:ok, _blocks} =
               BlockHelpers.toggle_multi_select_value(
                 socket,
                 Integer.to_string(block.id),
                 "a"
               )
    end
  end

  describe "handle_multi_select_enter_value/3 (delegated)" do
    setup :setup_context

    test "returns {:ok, blocks} for empty string (no-op)", %{socket: socket} do
      assert {:ok, _blocks} =
               BlockHelpers.handle_multi_select_enter_value(socket, 0, "")
    end

    test "creates and selects new option", %{socket: socket, sheet: sheet} do
      block =
        block_fixture(sheet, %{
          type: "multi_select",
          config: %{"label" => "Tags", "options" => []},
          value: %{"content" => []}
        })

      assert {:ok, blocks} =
               BlockHelpers.handle_multi_select_enter_value(socket, block.id, "Fresh")

      updated = Enum.find(blocks, &(&1.id == block.id))
      assert "fresh" in updated.value["content"]
    end
  end

  describe "update_rich_text_value/3 (delegated)" do
    setup :setup_context

    test "returns {:ok, blocks} on success", %{socket: socket, sheet: sheet} do
      block = block_fixture(sheet, %{type: "rich_text"})

      assert {:ok, blocks} =
               BlockHelpers.update_rich_text_value(socket, block.id, "<p>Hi</p>")

      updated = Enum.find(blocks, &(&1.id == block.id))
      assert updated.value["content"] == "<p>Hi</p>"
    end

    test "handles string block_id", %{socket: socket, sheet: sheet} do
      block = block_fixture(sheet, %{type: "rich_text"})

      assert {:ok, _blocks} =
               BlockHelpers.update_rich_text_value(
                 socket,
                 Integer.to_string(block.id),
                 "text"
               )
    end
  end

  describe "set_boolean_block_value/3 (delegated)" do
    setup :setup_context

    test "returns {:ok, blocks} with true value", %{socket: socket, sheet: sheet} do
      block = block_fixture(sheet, %{type: "boolean", value: %{"content" => nil}})

      assert {:ok, blocks} =
               BlockHelpers.set_boolean_block_value(socket, block.id, "true")

      updated = Enum.find(blocks, &(&1.id == block.id))
      assert updated.value["content"] == true
    end

    test "returns {:ok, blocks} with false value", %{socket: socket, sheet: sheet} do
      block = block_fixture(sheet, %{type: "boolean", value: %{"content" => nil}})

      assert {:ok, blocks} =
               BlockHelpers.set_boolean_block_value(socket, block.id, "false")

      updated = Enum.find(blocks, &(&1.id == block.id))
      assert updated.value["content"] == false
    end

    test "returns {:ok, blocks} with null value", %{socket: socket, sheet: sheet} do
      block = block_fixture(sheet, %{type: "boolean", value: %{"content" => true}})

      assert {:ok, blocks} =
               BlockHelpers.set_boolean_block_value(socket, block.id, "null")

      updated = Enum.find(blocks, &(&1.id == block.id))
      assert updated.value["content"] == nil
    end

    test "handles unknown value string as nil", %{socket: socket, sheet: sheet} do
      block = block_fixture(sheet, %{type: "boolean", value: %{"content" => true}})

      assert {:ok, blocks} =
               BlockHelpers.set_boolean_block_value(socket, block.id, "unknown")

      updated = Enum.find(blocks, &(&1.id == block.id))
      assert updated.value["content"] == nil
    end

    test "handles string block_id", %{socket: socket, sheet: sheet} do
      block = block_fixture(sheet, %{type: "boolean", value: %{"content" => nil}})

      assert {:ok, _blocks} =
               BlockHelpers.set_boolean_block_value(
                 socket,
                 Integer.to_string(block.id),
                 "true"
               )
    end
  end
end

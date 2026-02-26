defmodule StoryarnWeb.SheetLive.Helpers.BlockValueHelpersTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Sheets
  alias StoryarnWeb.SheetLive.Helpers.BlockValueHelpers

  # ===========================================================================
  # Test helpers
  # ===========================================================================

  defp build_socket(project, sheet) do
    %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        project: project,
        sheet: sheet
      }
    }
  end

  defp setup_project(_context) do
    user = user_fixture()
    project = project_fixture(user)
    sheet = sheet_fixture(project, %{name: "Test Sheet"})
    socket = build_socket(project, sheet)
    %{project: project, sheet: sheet, socket: socket}
  end

  # ===========================================================================
  # toggle_multi_select_value/3
  # ===========================================================================

  describe "toggle_multi_select_value/3" do
    setup :setup_project

    test "adds a key to empty multi_select content", %{socket: socket, sheet: sheet} do
      block =
        block_fixture(sheet, %{
          type: "multi_select",
          config: %{
            "label" => "Tags",
            "options" => [%{"key" => "fire", "value" => "Fire"}]
          },
          value: %{"content" => []}
        })

      assert {:ok, _blocks} =
               BlockValueHelpers.toggle_multi_select_value(socket, block.id, "fire")

      updated = Sheets.get_block(block.id)
      assert "fire" in updated.value["content"]
    end

    test "removes an existing key from multi_select content", %{socket: socket, sheet: sheet} do
      block =
        block_fixture(sheet, %{
          type: "multi_select",
          config: %{
            "label" => "Tags",
            "options" => [
              %{"key" => "fire", "value" => "Fire"},
              %{"key" => "ice", "value" => "Ice"}
            ]
          },
          value: %{"content" => ["fire", "ice"]}
        })

      assert {:ok, _blocks} =
               BlockValueHelpers.toggle_multi_select_value(socket, block.id, "fire")

      updated = Sheets.get_block(block.id)
      refute "fire" in updated.value["content"]
      assert "ice" in updated.value["content"]
    end

    test "adds a key to content that already has other keys", %{socket: socket, sheet: sheet} do
      block =
        block_fixture(sheet, %{
          type: "multi_select",
          config: %{
            "label" => "Tags",
            "options" => [
              %{"key" => "fire", "value" => "Fire"},
              %{"key" => "ice", "value" => "Ice"}
            ]
          },
          value: %{"content" => ["fire"]}
        })

      assert {:ok, _blocks} =
               BlockValueHelpers.toggle_multi_select_value(socket, block.id, "ice")

      updated = Sheets.get_block(block.id)
      assert "fire" in updated.value["content"]
      assert "ice" in updated.value["content"]
    end

    test "handles nil content gracefully (treats as empty list)", %{
      socket: socket,
      sheet: sheet
    } do
      block =
        block_fixture(sheet, %{
          type: "multi_select",
          config: %{
            "label" => "Tags",
            "options" => [%{"key" => "fire", "value" => "Fire"}]
          },
          value: %{}
        })

      assert {:ok, _blocks} =
               BlockValueHelpers.toggle_multi_select_value(socket, block.id, "fire")

      updated = Sheets.get_block(block.id)
      assert "fire" in updated.value["content"]
    end

    test "accepts string block_id", %{socket: socket, sheet: sheet} do
      block =
        block_fixture(sheet, %{
          type: "multi_select",
          config: %{
            "label" => "Tags",
            "options" => [%{"key" => "fire", "value" => "Fire"}]
          },
          value: %{"content" => []}
        })

      assert {:ok, _blocks} =
               BlockValueHelpers.toggle_multi_select_value(
                 socket,
                 to_string(block.id),
                 "fire"
               )

      updated = Sheets.get_block(block.id)
      assert "fire" in updated.value["content"]
    end

    test "returns {:ok, blocks} list on success", %{socket: socket, sheet: sheet} do
      block =
        block_fixture(sheet, %{
          type: "multi_select",
          config: %{
            "label" => "Tags",
            "options" => [%{"key" => "fire", "value" => "Fire"}]
          },
          value: %{"content" => []}
        })

      assert {:ok, blocks} =
               BlockValueHelpers.toggle_multi_select_value(socket, block.id, "fire")

      assert is_list(blocks)
      assert blocks != []
    end
  end

  # ===========================================================================
  # handle_multi_select_enter_value/3
  # ===========================================================================

  describe "handle_multi_select_enter_value/3" do
    setup :setup_project

    test "empty string returns current blocks without changes", %{
      socket: socket,
      sheet: sheet
    } do
      block =
        block_fixture(sheet, %{
          type: "multi_select",
          config: %{
            "label" => "Tags",
            "options" => [%{"key" => "fire", "value" => "Fire"}]
          },
          value: %{"content" => ["fire"]}
        })

      assert {:ok, blocks} =
               BlockValueHelpers.handle_multi_select_enter_value(socket, block.id, "")

      assert is_list(blocks)

      # Content should not have changed
      updated = Sheets.get_block(block.id)
      assert updated.value["content"] == ["fire"]
    end

    test "whitespace-only string returns current blocks without changes", %{
      socket: socket,
      sheet: sheet
    } do
      block =
        block_fixture(sheet, %{
          type: "multi_select",
          config: %{
            "label" => "Tags",
            "options" => [%{"key" => "fire", "value" => "Fire"}]
          },
          value: %{"content" => []}
        })

      assert {:ok, _blocks} =
               BlockValueHelpers.handle_multi_select_enter_value(socket, block.id, "   ")

      updated = Sheets.get_block(block.id)
      assert updated.value["content"] == []
    end

    test "adding existing option by exact name selects it", %{socket: socket, sheet: sheet} do
      block =
        block_fixture(sheet, %{
          type: "multi_select",
          config: %{
            "label" => "Tags",
            "options" => [%{"key" => "fire", "value" => "Fire"}]
          },
          value: %{"content" => []}
        })

      assert {:ok, _blocks} =
               BlockValueHelpers.handle_multi_select_enter_value(socket, block.id, "Fire")

      updated = Sheets.get_block(block.id)
      assert "fire" in updated.value["content"]
    end

    test "adding existing option case-insensitively selects it", %{
      socket: socket,
      sheet: sheet
    } do
      block =
        block_fixture(sheet, %{
          type: "multi_select",
          config: %{
            "label" => "Tags",
            "options" => [%{"key" => "fire", "value" => "Fire"}]
          },
          value: %{"content" => []}
        })

      assert {:ok, _blocks} =
               BlockValueHelpers.handle_multi_select_enter_value(socket, block.id, "fire")

      updated = Sheets.get_block(block.id)
      assert "fire" in updated.value["content"]
    end

    test "adding already-selected existing option does not duplicate it", %{
      socket: socket,
      sheet: sheet
    } do
      block =
        block_fixture(sheet, %{
          type: "multi_select",
          config: %{
            "label" => "Tags",
            "options" => [%{"key" => "fire", "value" => "Fire"}]
          },
          value: %{"content" => ["fire"]}
        })

      assert {:ok, _blocks} =
               BlockValueHelpers.handle_multi_select_enter_value(socket, block.id, "Fire")

      updated = Sheets.get_block(block.id)
      assert updated.value["content"] == ["fire"]
    end

    test "adding a brand-new option creates it and selects it", %{
      socket: socket,
      sheet: sheet
    } do
      block =
        block_fixture(sheet, %{
          type: "multi_select",
          config: %{
            "label" => "Tags",
            "options" => [%{"key" => "fire", "value" => "Fire"}]
          },
          value: %{"content" => []}
        })

      assert {:ok, _blocks} =
               BlockValueHelpers.handle_multi_select_enter_value(socket, block.id, "Water")

      updated = Sheets.get_block(block.id)

      # New option should be added to config
      option_keys = Enum.map(updated.config["options"], & &1["key"])
      assert "water" in option_keys

      # New option should be selected
      assert "water" in updated.value["content"]
    end

    test "new option with special characters generates clean key", %{
      socket: socket,
      sheet: sheet
    } do
      block =
        block_fixture(sheet, %{
          type: "multi_select",
          config: %{
            "label" => "Tags",
            "options" => []
          },
          value: %{"content" => []}
        })

      assert {:ok, _blocks} =
               BlockValueHelpers.handle_multi_select_enter_value(
                 socket,
                 block.id,
                 "Hello World!"
               )

      updated = Sheets.get_block(block.id)

      option_keys = Enum.map(updated.config["options"], & &1["key"])
      assert "hello-world" in option_keys
      assert "hello-world" in updated.value["content"]
    end

    test "trims leading/trailing whitespace from value", %{socket: socket, sheet: sheet} do
      block =
        block_fixture(sheet, %{
          type: "multi_select",
          config: %{
            "label" => "Tags",
            "options" => []
          },
          value: %{"content" => []}
        })

      assert {:ok, _blocks} =
               BlockValueHelpers.handle_multi_select_enter_value(
                 socket,
                 block.id,
                 "  Trimmed  "
               )

      updated = Sheets.get_block(block.id)

      option_values = Enum.map(updated.config["options"], & &1["value"])
      assert "Trimmed" in option_values
    end
  end

  # ===========================================================================
  # update_rich_text_value/3
  # ===========================================================================

  describe "update_rich_text_value/3" do
    setup :setup_project

    test "updates rich text content with HTML", %{socket: socket, sheet: sheet} do
      block =
        block_fixture(sheet, %{
          type: "rich_text",
          config: %{"label" => "Description"},
          value: %{"content" => ""}
        })

      html_content = "<p>Hello <strong>world</strong></p>"

      assert {:ok, _blocks} =
               BlockValueHelpers.update_rich_text_value(socket, block.id, html_content)

      updated = Sheets.get_block(block.id)
      assert updated.value["content"] == html_content
    end

    test "updates rich text content with empty string", %{socket: socket, sheet: sheet} do
      block =
        block_fixture(sheet, %{
          type: "rich_text",
          config: %{"label" => "Description"},
          value: %{"content" => "<p>Some text</p>"}
        })

      assert {:ok, _blocks} = BlockValueHelpers.update_rich_text_value(socket, block.id, "")

      updated = Sheets.get_block(block.id)
      assert updated.value["content"] == ""
    end

    test "updates rich text content with nil", %{socket: socket, sheet: sheet} do
      block =
        block_fixture(sheet, %{
          type: "rich_text",
          config: %{"label" => "Description"},
          value: %{"content" => "<p>Some text</p>"}
        })

      assert {:ok, _blocks} = BlockValueHelpers.update_rich_text_value(socket, block.id, nil)

      updated = Sheets.get_block(block.id)
      assert updated.value["content"] == nil
    end

    test "accepts string block_id", %{socket: socket, sheet: sheet} do
      block =
        block_fixture(sheet, %{
          type: "rich_text",
          config: %{"label" => "Description"},
          value: %{"content" => ""}
        })

      assert {:ok, _blocks} =
               BlockValueHelpers.update_rich_text_value(
                 socket,
                 to_string(block.id),
                 "<p>New content</p>"
               )

      updated = Sheets.get_block(block.id)
      assert updated.value["content"] == "<p>New content</p>"
    end

    test "returns {:ok, blocks} list on success", %{socket: socket, sheet: sheet} do
      block =
        block_fixture(sheet, %{
          type: "rich_text",
          config: %{"label" => "Description"},
          value: %{"content" => ""}
        })

      assert {:ok, blocks} =
               BlockValueHelpers.update_rich_text_value(socket, block.id, "<p>Test</p>")

      assert is_list(blocks)
    end

    test "replaces existing content with new content", %{socket: socket, sheet: sheet} do
      block =
        block_fixture(sheet, %{
          type: "rich_text",
          config: %{"label" => "Description"},
          value: %{"content" => "<p>Old content</p>"}
        })

      assert {:ok, _blocks} =
               BlockValueHelpers.update_rich_text_value(
                 socket,
                 block.id,
                 "<p>New content</p>"
               )

      updated = Sheets.get_block(block.id)
      assert updated.value["content"] == "<p>New content</p>"
    end
  end

  # ===========================================================================
  # set_boolean_block_value/3
  # ===========================================================================

  describe "set_boolean_block_value/3" do
    setup :setup_project

    test "sets boolean to true when value_string is \"true\"", %{
      socket: socket,
      sheet: sheet
    } do
      block =
        block_fixture(sheet, %{
          type: "boolean",
          config: %{"label" => "Active"},
          value: %{"content" => nil}
        })

      assert {:ok, _blocks} =
               BlockValueHelpers.set_boolean_block_value(socket, block.id, "true")

      updated = Sheets.get_block(block.id)
      assert updated.value["content"] == true
    end

    test "sets boolean to false when value_string is \"false\"", %{
      socket: socket,
      sheet: sheet
    } do
      block =
        block_fixture(sheet, %{
          type: "boolean",
          config: %{"label" => "Active"},
          value: %{"content" => true}
        })

      assert {:ok, _blocks} =
               BlockValueHelpers.set_boolean_block_value(socket, block.id, "false")

      updated = Sheets.get_block(block.id)
      assert updated.value["content"] == false
    end

    test "sets boolean to nil when value_string is \"null\"", %{
      socket: socket,
      sheet: sheet
    } do
      block =
        block_fixture(sheet, %{
          type: "boolean",
          config: %{"label" => "Active"},
          value: %{"content" => true}
        })

      assert {:ok, _blocks} =
               BlockValueHelpers.set_boolean_block_value(socket, block.id, "null")

      updated = Sheets.get_block(block.id)
      assert updated.value["content"] == nil
    end

    test "sets boolean to nil for unrecognized value_string", %{
      socket: socket,
      sheet: sheet
    } do
      block =
        block_fixture(sheet, %{
          type: "boolean",
          config: %{"label" => "Active"},
          value: %{"content" => true}
        })

      assert {:ok, _blocks} =
               BlockValueHelpers.set_boolean_block_value(socket, block.id, "garbage")

      updated = Sheets.get_block(block.id)
      assert updated.value["content"] == nil
    end

    test "sets boolean to nil for empty string value", %{socket: socket, sheet: sheet} do
      block =
        block_fixture(sheet, %{
          type: "boolean",
          config: %{"label" => "Active"},
          value: %{"content" => false}
        })

      assert {:ok, _blocks} =
               BlockValueHelpers.set_boolean_block_value(socket, block.id, "")

      updated = Sheets.get_block(block.id)
      assert updated.value["content"] == nil
    end

    test "accepts string block_id", %{socket: socket, sheet: sheet} do
      block =
        block_fixture(sheet, %{
          type: "boolean",
          config: %{"label" => "Active"},
          value: %{"content" => nil}
        })

      assert {:ok, _blocks} =
               BlockValueHelpers.set_boolean_block_value(
                 socket,
                 to_string(block.id),
                 "true"
               )

      updated = Sheets.get_block(block.id)
      assert updated.value["content"] == true
    end

    test "returns {:ok, blocks} list on success", %{socket: socket, sheet: sheet} do
      block =
        block_fixture(sheet, %{
          type: "boolean",
          config: %{"label" => "Active"},
          value: %{"content" => nil}
        })

      assert {:ok, blocks} =
               BlockValueHelpers.set_boolean_block_value(socket, block.id, "true")

      assert is_list(blocks)
    end

    test "toggles from true to false and back", %{socket: socket, sheet: sheet} do
      block =
        block_fixture(sheet, %{
          type: "boolean",
          config: %{"label" => "Active"},
          value: %{"content" => nil}
        })

      # nil -> true
      assert {:ok, _blocks} =
               BlockValueHelpers.set_boolean_block_value(socket, block.id, "true")

      updated = Sheets.get_block(block.id)
      assert updated.value["content"] == true

      # true -> false
      assert {:ok, _blocks} =
               BlockValueHelpers.set_boolean_block_value(socket, block.id, "false")

      updated = Sheets.get_block(block.id)
      assert updated.value["content"] == false

      # false -> null
      assert {:ok, _blocks} =
               BlockValueHelpers.set_boolean_block_value(socket, block.id, "null")

      updated = Sheets.get_block(block.id)
      assert updated.value["content"] == nil
    end
  end
end

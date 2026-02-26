defmodule StoryarnWeb.SheetLive.Helpers.ConfigHelpersTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Sheets
  alias StoryarnWeb.SheetLive.Helpers.ConfigHelpers

  # ===========================================================================
  # Test helpers
  # ===========================================================================

  defp build_socket(assigns_overrides) do
    assigns =
      Map.merge(
        %{__changed__: %{}, flash: %{}, configuring_block: nil, save_status: :idle},
        assigns_overrides
      )

    %Phoenix.LiveView.Socket{assigns: assigns}
  end

  defp setup_project_and_sheet(_context) do
    user = user_fixture()
    project = project_fixture(user)
    sheet = sheet_fixture(project, %{name: "Config Test Sheet"})
    %{user: user, project: project, sheet: sheet}
  end

  defp create_select_block(sheet, options) do
    opts =
      Enum.map(options, fn {key, value} ->
        %{"key" => key, "value" => value}
      end)

    block_fixture(sheet, %{
      type: "select",
      config: %{"label" => "Color", "options" => opts},
      value: %{"selected" => nil}
    })
  end

  defp socket_with_sheet_and_block(project, sheet, block) do
    build_socket(%{
      project: project,
      sheet: sheet,
      blocks: Sheets.list_blocks(sheet.id),
      configuring_block: block
    })
  end

  # ===========================================================================
  # configure_block/2
  # ===========================================================================

  describe "configure_block/2" do
    setup :setup_project_and_sheet

    test "opens config panel for an existing block", %{project: project, sheet: sheet} do
      block = block_fixture(sheet, %{type: "text", config: %{"label" => "Name"}})

      socket =
        build_socket(%{
          project: project,
          sheet: sheet,
          blocks: Sheets.list_blocks(sheet.id),
          configuring_block: nil
        })

      {:noreply, updated} = ConfigHelpers.configure_block(socket, block.id)

      assert updated.assigns.configuring_block.id == block.id
      assert updated.assigns.configuring_block.type == "text"
    end

    test "raises when block does not exist in project", %{project: project, sheet: sheet} do
      socket =
        build_socket(%{
          project: project,
          sheet: sheet,
          blocks: [],
          configuring_block: nil
        })

      assert_raise Ecto.NoResultsError, fn ->
        ConfigHelpers.configure_block(socket, -1)
      end
    end

    test "raises when block belongs to a different project", %{sheet: sheet} do
      other_user = user_fixture()
      other_project = project_fixture(other_user)
      block = block_fixture(sheet)

      socket =
        build_socket(%{
          project: other_project,
          sheet: sheet,
          blocks: [],
          configuring_block: nil
        })

      assert_raise Ecto.NoResultsError, fn ->
        ConfigHelpers.configure_block(socket, block.id)
      end
    end
  end

  # ===========================================================================
  # close_config_panel/1
  # ===========================================================================

  describe "close_config_panel/1" do
    setup :setup_project_and_sheet

    test "sets configuring_block to nil", %{project: project, sheet: sheet} do
      block = block_fixture(sheet)
      socket = socket_with_sheet_and_block(project, sheet, block)

      {:noreply, updated} = ConfigHelpers.close_config_panel(socket)

      assert updated.assigns.configuring_block == nil
    end

    test "is idempotent when already nil", %{project: project, sheet: sheet} do
      socket =
        build_socket(%{
          project: project,
          sheet: sheet,
          blocks: [],
          configuring_block: nil
        })

      {:noreply, updated} = ConfigHelpers.close_config_panel(socket)

      assert updated.assigns.configuring_block == nil
    end
  end

  # ===========================================================================
  # save_block_config/2
  # ===========================================================================

  describe "save_block_config/2" do
    setup :setup_project_and_sheet

    test "saves config and updates socket assigns", %{project: project, sheet: sheet} do
      block = block_fixture(sheet, %{type: "text", config: %{"label" => "Old Label"}})
      socket = socket_with_sheet_and_block(project, sheet, block)

      {:noreply, updated} =
        ConfigHelpers.save_block_config(socket, %{"label" => "New Label"})

      assert updated.assigns.configuring_block.config["label"] == "New Label"
      assert updated.assigns.save_status == :saved
    end

    test "normalizes options from indexed map to list", %{project: project, sheet: sheet} do
      block = create_select_block(sheet, [{"red", "Red"}, {"blue", "Blue"}])
      socket = socket_with_sheet_and_block(project, sheet, block)

      config_params = %{
        "label" => "Color",
        "options" => %{
          "0" => %{"key" => "green", "value" => "Green"},
          "1" => %{"key" => "yellow", "value" => "Yellow"}
        }
      }

      {:noreply, updated} = ConfigHelpers.save_block_config(socket, config_params)

      options = updated.assigns.configuring_block.config["options"]
      assert length(options) == 2
      assert Enum.at(options, 0)["key"] == "green"
      assert Enum.at(options, 1)["key"] == "yellow"
    end

    test "preserves options when already a list", %{project: project, sheet: sheet} do
      block = create_select_block(sheet, [{"a", "A"}])
      socket = socket_with_sheet_and_block(project, sheet, block)

      config_params = %{
        "label" => "Opts",
        "options" => [%{"key" => "x", "value" => "X"}]
      }

      {:noreply, updated} = ConfigHelpers.save_block_config(socket, config_params)

      options = updated.assigns.configuring_block.config["options"]
      assert length(options) == 1
      assert hd(options)["key"] == "x"
    end

    test "filters empty strings from allowed_types", %{project: project, sheet: sheet} do
      block =
        block_fixture(sheet, %{
          type: "reference",
          config: %{"label" => "Ref", "allowed_types" => ["sheet"]},
          value: %{}
        })

      socket = socket_with_sheet_and_block(project, sheet, block)

      config_params = %{
        "label" => "Ref",
        "allowed_types" => ["", "sheet", "flow", ""]
      }

      {:noreply, updated} = ConfigHelpers.save_block_config(socket, config_params)

      allowed = updated.assigns.configuring_block.config["allowed_types"]
      assert allowed == ["sheet", "flow"]
    end

    test "handles nil options gracefully", %{project: project, sheet: sheet} do
      block = block_fixture(sheet, %{type: "text", config: %{"label" => "Simple"}})
      socket = socket_with_sheet_and_block(project, sheet, block)

      {:noreply, updated} =
        ConfigHelpers.save_block_config(socket, %{"label" => "Updated"})

      assert updated.assigns.configuring_block.config["label"] == "Updated"
    end

    test "refreshes blocks list after save", %{project: project, sheet: sheet} do
      _other_block = block_fixture(sheet, %{type: "number", config: %{"label" => "HP"}})
      block = block_fixture(sheet, %{type: "text", config: %{"label" => "Name"}})
      socket = socket_with_sheet_and_block(project, sheet, block)

      {:noreply, updated} =
        ConfigHelpers.save_block_config(socket, %{"label" => "Full Name"})

      # Blocks list should contain both blocks
      assert length(updated.assigns.blocks) == 2
    end
  end

  # ===========================================================================
  # add_select_option/1
  # ===========================================================================

  describe "add_select_option/1" do
    setup :setup_project_and_sheet

    test "adds a new option to a select block", %{project: project, sheet: sheet} do
      block = create_select_block(sheet, [{"red", "Red"}])
      socket = socket_with_sheet_and_block(project, sheet, block)

      {:noreply, updated} = ConfigHelpers.add_select_option(socket)

      options = updated.assigns.configuring_block.config["options"]
      assert length(options) == 2
      assert Enum.at(options, 1)["key"] == "option-2"
      assert Enum.at(options, 1)["value"] == ""
    end

    test "adds first option to a block with no options", %{project: project, sheet: sheet} do
      block =
        block_fixture(sheet, %{
          type: "select",
          config: %{"label" => "Empty Select", "options" => []},
          value: %{"selected" => nil}
        })

      socket = socket_with_sheet_and_block(project, sheet, block)

      {:noreply, updated} = ConfigHelpers.add_select_option(socket)

      options = updated.assigns.configuring_block.config["options"]
      assert length(options) == 1
      assert hd(options)["key"] == "option-1"
    end

    test "adds option when config has nil options", %{project: project, sheet: sheet} do
      block =
        block_fixture(sheet, %{
          type: "select",
          config: %{"label" => "No Options"},
          value: %{"selected" => nil}
        })

      socket = socket_with_sheet_and_block(project, sheet, block)

      {:noreply, updated} = ConfigHelpers.add_select_option(socket)

      options = updated.assigns.configuring_block.config["options"]
      assert length(options) == 1
      assert hd(options)["key"] == "option-1"
    end

    test "updates blocks list after adding option", %{project: project, sheet: sheet} do
      block = create_select_block(sheet, [{"a", "A"}])
      socket = socket_with_sheet_and_block(project, sheet, block)

      {:noreply, updated} = ConfigHelpers.add_select_option(socket)

      assert is_list(updated.assigns.blocks)
    end
  end

  # ===========================================================================
  # remove_select_option/2
  # ===========================================================================

  describe "remove_select_option/2" do
    setup :setup_project_and_sheet

    test "removes option at given string index", %{project: project, sheet: sheet} do
      block = create_select_block(sheet, [{"a", "A"}, {"b", "B"}, {"c", "C"}])
      socket = socket_with_sheet_and_block(project, sheet, block)

      {:noreply, updated} = ConfigHelpers.remove_select_option(socket, "1")

      options = updated.assigns.configuring_block.config["options"]
      assert length(options) == 2
      keys = Enum.map(options, & &1["key"])
      assert keys == ["a", "c"]
    end

    test "removes option at given integer index", %{project: project, sheet: sheet} do
      block = create_select_block(sheet, [{"x", "X"}, {"y", "Y"}])
      socket = socket_with_sheet_and_block(project, sheet, block)

      {:noreply, updated} = ConfigHelpers.remove_select_option(socket, 0)

      options = updated.assigns.configuring_block.config["options"]
      assert length(options) == 1
      assert hd(options)["key"] == "y"
    end

    test "removes last option leaving empty list", %{project: project, sheet: sheet} do
      block = create_select_block(sheet, [{"only", "Only"}])
      socket = socket_with_sheet_and_block(project, sheet, block)

      {:noreply, updated} = ConfigHelpers.remove_select_option(socket, "0")

      options = updated.assigns.configuring_block.config["options"]
      assert options == []
    end

    test "returns socket unchanged for invalid string index", %{
      project: project,
      sheet: sheet
    } do
      block = create_select_block(sheet, [{"a", "A"}])
      socket = socket_with_sheet_and_block(project, sheet, block)

      {:noreply, updated} = ConfigHelpers.remove_select_option(socket, "abc")

      # Block should remain unchanged since parse_index returns :error
      assert updated.assigns.configuring_block.id == block.id
    end

    test "returns socket unchanged for nil index", %{project: project, sheet: sheet} do
      block = create_select_block(sheet, [{"a", "A"}])
      socket = socket_with_sheet_and_block(project, sheet, block)

      {:noreply, updated} = ConfigHelpers.remove_select_option(socket, nil)

      assert updated.assigns.configuring_block.id == block.id
    end

    test "handles out-of-bounds index gracefully", %{project: project, sheet: sheet} do
      block = create_select_block(sheet, [{"a", "A"}])
      socket = socket_with_sheet_and_block(project, sheet, block)

      {:noreply, updated} = ConfigHelpers.remove_select_option(socket, "99")

      # List.delete_at with out-of-bounds returns original list
      options = updated.assigns.configuring_block.config["options"]
      assert length(options) == 1
    end
  end

  # ===========================================================================
  # toggle_constant/1
  # ===========================================================================

  describe "toggle_constant/1" do
    setup :setup_project_and_sheet

    test "toggles is_constant from false to true", %{project: project, sheet: sheet} do
      block = block_fixture(sheet, %{type: "text", config: %{"label" => "Name"}})
      assert block.is_constant == false or is_nil(block.is_constant)

      socket = socket_with_sheet_and_block(project, sheet, block)

      {:noreply, updated} = ConfigHelpers.toggle_constant(socket)

      assert updated.assigns.configuring_block.is_constant == true
    end

    test "toggles is_constant from true to false", %{project: project, sheet: sheet} do
      block = block_fixture(sheet, %{type: "text", config: %{"label" => "Const"}})
      {:ok, block} = Sheets.update_block(block, %{is_constant: true})
      assert block.is_constant == true

      socket = socket_with_sheet_and_block(project, sheet, block)

      {:noreply, updated} = ConfigHelpers.toggle_constant(socket)

      assert updated.assigns.configuring_block.is_constant == false
    end

    test "updates blocks list after toggling", %{project: project, sheet: sheet} do
      block = block_fixture(sheet)
      socket = socket_with_sheet_and_block(project, sheet, block)

      {:noreply, updated} = ConfigHelpers.toggle_constant(socket)

      assert is_list(updated.assigns.blocks)
      assert length(updated.assigns.blocks) >= 1
    end
  end

  # ===========================================================================
  # update_select_option/4
  # ===========================================================================

  describe "update_select_option/4" do
    setup :setup_project_and_sheet

    test "updates option key and value at given index", %{project: project, sheet: sheet} do
      block = create_select_block(sheet, [{"old_key", "Old Value"}, {"keep", "Keep"}])
      socket = socket_with_sheet_and_block(project, sheet, block)

      {:noreply, updated} =
        ConfigHelpers.update_select_option(socket, "0", "new_key", "New Value")

      options = updated.assigns.configuring_block.config["options"]
      assert Enum.at(options, 0)["key"] == "new_key"
      assert Enum.at(options, 0)["value"] == "New Value"
      # Second option should be unchanged
      assert Enum.at(options, 1)["key"] == "keep"
    end

    test "updates option with integer index", %{project: project, sheet: sheet} do
      block = create_select_block(sheet, [{"a", "A"}, {"b", "B"}])
      socket = socket_with_sheet_and_block(project, sheet, block)

      {:noreply, updated} =
        ConfigHelpers.update_select_option(socket, 1, "c", "C")

      options = updated.assigns.configuring_block.config["options"]
      assert Enum.at(options, 1)["key"] == "c"
      assert Enum.at(options, 1)["value"] == "C"
    end

    test "returns socket unchanged for invalid index", %{project: project, sheet: sheet} do
      block = create_select_block(sheet, [{"a", "A"}])
      socket = socket_with_sheet_and_block(project, sheet, block)

      {:noreply, updated} =
        ConfigHelpers.update_select_option(socket, "not_a_number", "x", "X")

      # Should return unchanged socket
      assert updated.assigns.configuring_block.id == block.id
    end

    test "returns socket unchanged for nil index", %{project: project, sheet: sheet} do
      block = create_select_block(sheet, [{"a", "A"}])
      socket = socket_with_sheet_and_block(project, sheet, block)

      {:noreply, updated} =
        ConfigHelpers.update_select_option(socket, nil, "x", "X")

      assert updated.assigns.configuring_block.id == block.id
    end

    test "updates option with empty value", %{project: project, sheet: sheet} do
      block = create_select_block(sheet, [{"a", "A"}])
      socket = socket_with_sheet_and_block(project, sheet, block)

      {:noreply, updated} =
        ConfigHelpers.update_select_option(socket, "0", "blank", "")

      options = updated.assigns.configuring_block.config["options"]
      assert Enum.at(options, 0)["key"] == "blank"
      assert Enum.at(options, 0)["value"] == ""
    end
  end

  # ===========================================================================
  # Integration: options ordering from indexed map
  # ===========================================================================

  describe "save_block_config/2 option ordering" do
    setup :setup_project_and_sheet

    test "orders options by numeric index when map keys are out of order", %{
      project: project,
      sheet: sheet
    } do
      block = create_select_block(sheet, [])
      socket = socket_with_sheet_and_block(project, sheet, block)

      config_params = %{
        "label" => "Color",
        "options" => %{
          "2" => %{"key" => "blue", "value" => "Blue"},
          "0" => %{"key" => "red", "value" => "Red"},
          "1" => %{"key" => "green", "value" => "Green"}
        }
      }

      {:noreply, updated} = ConfigHelpers.save_block_config(socket, config_params)

      options = updated.assigns.configuring_block.config["options"]
      keys = Enum.map(options, & &1["key"])
      assert keys == ["red", "green", "blue"]
    end

    test "handles non-numeric map keys by defaulting index to 0", %{
      project: project,
      sheet: sheet
    } do
      block = create_select_block(sheet, [])
      socket = socket_with_sheet_and_block(project, sheet, block)

      config_params = %{
        "label" => "Test",
        "options" => %{
          "abc" => %{"key" => "fallback", "value" => "Fallback"}
        }
      }

      {:noreply, updated} = ConfigHelpers.save_block_config(socket, config_params)

      options = updated.assigns.configuring_block.config["options"]
      assert length(options) == 1
      assert hd(options)["key"] == "fallback"
    end
  end
end

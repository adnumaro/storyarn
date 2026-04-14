defmodule StoryarnWeb.SheetLive.Handlers.SelectOptionHandlersTest do
  @moduledoc """
  Covers the unified select-option events (`add_option` / `remove_option` /
  `update_option`) for both `scope: "block"` and `scope: "column"`.
  """

  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Repo
  alias Storyarn.Sheets

  defp sheet_path(workspace, project, sheet) do
    ~p"/workspaces/#{workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}"
  end

  defp mount_sheet(conn, workspace, project, sheet) do
    {:ok, view, _html} = live(conn, sheet_path(workspace, project, sheet))
    {:ok, view}
  end

  defp setup_base(%{user: user}) do
    project = project_fixture(user) |> Repo.preload(:workspace)
    sheet = sheet_fixture(project, %{name: "Options Test Sheet"})

    %{
      project: project,
      workspace: project.workspace,
      sheet: sheet
    }
  end

  # ===========================================================================
  # Block scope (select / multi_select blocks)
  # ===========================================================================

  describe "scope=block add_option" do
    setup [:register_and_log_in_user, :setup_base]

    test "creates a new empty option with auto-incremented key", ctx do
      block = block_fixture(ctx.sheet, %{type: "select"})
      {:ok, view} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)

      render_click(view, "add_option", %{"scope" => "block", "id" => block.id})

      updated = Sheets.get_block(block.id)
      options = updated.config["options"] || []
      assert length(options) == 1
      assert [%{"key" => "option_1", "value" => ""}] = options
    end

    test "appends without disturbing existing options", ctx do
      block =
        block_fixture(ctx.sheet, %{
          type: "select",
          config: %{
            "options" => [
              %{"key" => "red", "value" => "Red"},
              %{"key" => "green", "value" => "Green"}
            ]
          }
        })

      {:ok, view} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)
      render_click(view, "add_option", %{"scope" => "block", "id" => block.id})

      updated = Sheets.get_block(block.id)
      keys = Enum.map(updated.config["options"], & &1["key"])
      assert keys == ["red", "green", "option_3"]
    end
  end

  describe "scope=block remove_option" do
    setup [:register_and_log_in_user, :setup_base]

    test "removes an option by index", ctx do
      block =
        block_fixture(ctx.sheet, %{
          type: "select",
          config: %{
            "options" => [
              %{"key" => "a", "value" => "A"},
              %{"key" => "b", "value" => "B"},
              %{"key" => "c", "value" => "C"}
            ]
          }
        })

      {:ok, view} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)

      render_click(view, "remove_option", %{
        "scope" => "block",
        "id" => block.id,
        "index" => 1
      })

      updated = Sheets.get_block(block.id)
      keys = Enum.map(updated.config["options"], & &1["key"])
      assert keys == ["a", "c"]
    end
  end

  describe "scope=block update_option" do
    setup [:register_and_log_in_user, :setup_base]

    test "updates value without touching key", ctx do
      block =
        block_fixture(ctx.sheet, %{
          type: "multi_select",
          config: %{
            "options" => [%{"key" => "tier_1", "value" => "Bronze"}]
          }
        })

      {:ok, view} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)

      render_click(view, "update_option", %{
        "scope" => "block",
        "id" => block.id,
        "index" => 0,
        "field" => "value",
        "value" => "Gold"
      })

      updated = Sheets.get_block(block.id)
      assert [%{"key" => "tier_1", "value" => "Gold"}] = updated.config["options"]
    end

    test "updates key independently of value", ctx do
      block =
        block_fixture(ctx.sheet, %{
          type: "select",
          config: %{"options" => [%{"key" => "old_key", "value" => "Label"}]}
        })

      {:ok, view} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)

      render_click(view, "update_option", %{
        "scope" => "block",
        "id" => block.id,
        "index" => 0,
        "field" => "key",
        "value" => "new_key"
      })

      updated = Sheets.get_block(block.id)
      assert [%{"key" => "new_key", "value" => "Label"}] = updated.config["options"]
    end

    test "ignores updates with unknown field", ctx do
      block =
        block_fixture(ctx.sheet, %{
          type: "select",
          config: %{"options" => [%{"key" => "k", "value" => "v"}]}
        })

      {:ok, view} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)

      render_click(view, "update_option", %{
        "scope" => "block",
        "id" => block.id,
        "index" => 0,
        "field" => "bogus",
        "value" => "x"
      })

      updated = Sheets.get_block(block.id)
      assert [%{"key" => "k", "value" => "v"}] = updated.config["options"]
    end
  end

  # ===========================================================================
  # Column scope (table column options)
  # ===========================================================================

  describe "scope=column add_option" do
    setup [:register_and_log_in_user, :setup_base]

    setup ctx do
      table_block = table_block_fixture(ctx.sheet, %{label: "Table"})
      col = table_column_fixture(table_block, %{name: "Status", type: "select"})
      %{table_block: table_block, col: col}
    end

    test "creates a new empty option on a column", ctx do
      {:ok, view} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)

      render_click(view, "add_option", %{"scope" => "column", "id" => ctx.col.id})

      updated = Sheets.get_table_column!(ctx.col.block_id, ctx.col.id)
      options = updated.config["options"] || []
      assert [%{"key" => "option_1", "value" => ""}] = options
    end
  end

  describe "scope=column remove_option" do
    setup [:register_and_log_in_user, :setup_base]

    setup ctx do
      table_block = table_block_fixture(ctx.sheet, %{label: "Table"})

      col =
        table_column_fixture(table_block, %{name: "Status", type: "select"})

      Sheets.update_table_column(col, %{
        config: %{
          "options" => [
            %{"key" => "active", "value" => "Active"},
            %{"key" => "inactive", "value" => "Inactive"}
          ]
        }
      })

      col = Sheets.get_table_column!(col.block_id, col.id)
      %{col: col}
    end

    test "removes an option by index", ctx do
      {:ok, view} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)

      render_click(view, "remove_option", %{
        "scope" => "column",
        "id" => ctx.col.id,
        "index" => 0
      })

      updated = Sheets.get_table_column!(ctx.col.block_id, ctx.col.id)
      assert Enum.map(updated.config["options"], & &1["key"]) == ["inactive"]
    end
  end

  describe "scope=column update_option" do
    setup [:register_and_log_in_user, :setup_base]

    setup ctx do
      table_block = table_block_fixture(ctx.sheet, %{label: "Table"})
      col = table_column_fixture(table_block, %{name: "Tier", type: "select"})

      Sheets.update_table_column(col, %{
        config: %{
          "options" => [%{"key" => "bronze", "value" => "Bronze"}]
        }
      })

      col = Sheets.get_table_column!(col.block_id, col.id)
      %{col: col}
    end

    test "updates value without changing key", ctx do
      {:ok, view} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)

      render_click(view, "update_option", %{
        "scope" => "column",
        "id" => ctx.col.id,
        "index" => 0,
        "field" => "value",
        "value" => "Gold"
      })

      updated = Sheets.get_table_column!(ctx.col.block_id, ctx.col.id)
      assert [%{"key" => "bronze", "value" => "Gold"}] = updated.config["options"]
    end

    test "updates key independently", ctx do
      {:ok, view} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)

      render_click(view, "update_option", %{
        "scope" => "column",
        "id" => ctx.col.id,
        "index" => 0,
        "field" => "key",
        "value" => "tier_1"
      })

      updated = Sheets.get_table_column!(ctx.col.block_id, ctx.col.id)
      assert [%{"key" => "tier_1", "value" => "Bronze"}] = updated.config["options"]
    end
  end

  # ===========================================================================
  # Edge cases
  # ===========================================================================

  describe "invalid scope" do
    setup [:register_and_log_in_user, :setup_base]

    test "unknown scope is a no-op", ctx do
      block = block_fixture(ctx.sheet, %{type: "select"})
      {:ok, view} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)

      render_click(view, "add_option", %{"scope" => "other", "id" => block.id})

      updated = Sheets.get_block(block.id)
      assert (updated.config["options"] || []) == []
    end

    test "block from a different sheet is ignored", ctx do
      other_sheet = sheet_fixture(ctx.project, %{name: "Other"})
      other_block = block_fixture(other_sheet, %{type: "select"})
      {:ok, view} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)

      render_click(view, "add_option", %{"scope" => "block", "id" => other_block.id})

      updated = Sheets.get_block(other_block.id)
      assert (updated.config["options"] || []) == []
    end
  end
end

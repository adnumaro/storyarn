defmodule StoryarnWeb.Components.BlockComponents.ConfigPanelTest do
  @moduledoc """
  Tests for the ConfigPanel component which renders the block configuration
  sidebar in the sheet editor. Covers all block-type-specific rendering paths
  and field assignments.
  """

  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Repo
  alias StoryarnWeb.Components.BlockComponents.ConfigPanel

  # ===========================================================================
  # Helpers
  # ===========================================================================

  defp sheet_path(workspace, project, sheet) do
    ~p"/workspaces/#{workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}"
  end

  defp mount_sheet(conn, workspace, project, sheet) do
    live(conn, sheet_path(workspace, project, sheet))
  end

  defp send_to_content_tab(view, event, params \\ %{}) do
    view
    |> with_target("#content-tab")
    |> render_click(event, params)
  end

  defp open_config_panel(view, block) do
    send_to_content_tab(view, "configure_block", %{"id" => to_string(block.id)})
  end

  defp build_block(attrs \\ %{}) do
    defaults = %{
      id: 1,
      type: "text",
      config: %{"label" => "Test Label", "placeholder" => "Enter text..."},
      value: %{"content" => ""},
      is_constant: false,
      variable_name: "test_label",
      scope: "self",
      inherited_from_block_id: nil,
      detached: false,
      required: false,
      column_group_id: nil,
      column_index: 0
    }

    struct(Storyarn.Sheets.Block, Map.merge(defaults, attrs))
  end

  # ===========================================================================
  # Unit tests — render_component for ConfigPanel
  # ===========================================================================

  describe "config_panel/1 — header and common fields" do
    test "renders panel header with title and close button" do
      block = build_block()
      html = render_component(&ConfigPanel.config_panel/1, block: block)

      assert html =~ "Configure Block"
      assert html =~ "close_config_panel"
    end

    test "renders block type badge" do
      block = build_block(%{type: "number"})
      html = render_component(&ConfigPanel.config_panel/1, block: block)

      assert html =~ "number"
      assert html =~ "badge-neutral"
    end

    test "renders label field for non-divider blocks" do
      block = build_block(%{type: "text", config: %{"label" => "My Field"}})
      html = render_component(&ConfigPanel.config_panel/1, block: block)

      assert html =~ "Label"
      assert html =~ "config[label]"
      assert html =~ "My Field"
    end

    test "does not render label field for divider blocks" do
      block = build_block(%{type: "divider", config: %{}})
      html = render_component(&ConfigPanel.config_panel/1, block: block)

      refute html =~ "config[label]"
    end

    test "renders save_block_config form" do
      block = build_block()
      html = render_component(&ConfigPanel.config_panel/1, block: block)

      assert html =~ "save_block_config"
    end
  end

  describe "config_panel/1 — scope selector" do
    test "renders scope selector for non-inherited, non-divider blocks" do
      block = build_block(%{type: "text", scope: "self"})
      html = render_component(&ConfigPanel.config_panel/1, block: block)

      assert html =~ "Scope"
      assert html =~ "This sheet only"
      assert html =~ "This sheet and all children"
    end

    test "does not render scope selector for divider blocks" do
      block = build_block(%{type: "divider", config: %{}})
      html = render_component(&ConfigPanel.config_panel/1, block: block)

      refute html =~ "Scope"
    end

    test "does not render scope selector for inherited blocks" do
      block = build_block(%{inherited_from_block_id: 99})
      html = render_component(&ConfigPanel.config_panel/1, block: block)

      refute html =~ "Scope"
    end

    test "shows children scope hint text when scope is children" do
      block = build_block(%{scope: "children"})
      html = render_component(&ConfigPanel.config_panel/1, block: block)

      assert html =~ "Changes to this property"
      assert html =~ "will sync to all children"
    end

    test "does not show children scope hint text when scope is self" do
      block = build_block(%{scope: "self"})
      html = render_component(&ConfigPanel.config_panel/1, block: block)

      refute html =~ "will sync to all children"
    end
  end

  describe "config_panel/1 — required toggle" do
    test "renders required toggle when scope is children and block is not inherited" do
      block = build_block(%{scope: "children", required: false})
      html = render_component(&ConfigPanel.config_panel/1, block: block)

      assert html =~ "Required"
      assert html =~ "toggle_required"
      assert html =~ "Mark this property as required for children"
    end

    test "does not render required toggle when scope is self" do
      block = build_block(%{scope: "self"})
      html = render_component(&ConfigPanel.config_panel/1, block: block)

      refute html =~ "toggle_required"
    end

    test "does not render required toggle for inherited blocks with children scope" do
      block = build_block(%{scope: "children", inherited_from_block_id: 99})
      html = render_component(&ConfigPanel.config_panel/1, block: block)

      refute html =~ "toggle_required"
    end
  end

  describe "config_panel/1 — detached blocks" do
    test "shows inherited badge for inherited blocks" do
      block = build_block(%{inherited_from_block_id: 99})
      html = render_component(&ConfigPanel.config_panel/1, block: block)

      assert html =~ "Inherited"
    end

    test "shows detached badge for detached blocks" do
      block = build_block(%{detached: true, inherited_from_block_id: 99})
      html = render_component(&ConfigPanel.config_panel/1, block: block)

      assert html =~ "Detached"
    end

    test "shows re-attach button for detached blocks" do
      block = build_block(%{detached: true, inherited_from_block_id: 99})
      html = render_component(&ConfigPanel.config_panel/1, block: block)

      assert html =~ "Re-sync with source"
      assert html =~ "reattach_block"
      assert html =~ "Resets the property definition"
    end

    test "does not show re-attach button for non-detached blocks" do
      block = build_block()
      html = render_component(&ConfigPanel.config_panel/1, block: block)

      refute html =~ "Re-sync with source"
      refute html =~ "reattach_block"
    end
  end

  describe "config_panel/1 — constant toggle" do
    test "renders constant toggle for variable-capable types" do
      block = build_block(%{type: "text"})
      html = render_component(&ConfigPanel.config_panel/1, block: block)

      assert html =~ "Use as constant"
      assert html =~ "toggle_constant"
      assert html =~ "Constants are not accessible as variables"
    end

    test "does not render constant toggle for divider blocks" do
      block = build_block(%{type: "divider", config: %{}})
      html = render_component(&ConfigPanel.config_panel/1, block: block)

      refute html =~ "Use as constant"
      refute html =~ "toggle_constant"
    end

    test "does not render constant toggle for reference blocks" do
      block = build_block(%{type: "reference", config: %{"label" => "Ref"}})
      html = render_component(&ConfigPanel.config_panel/1, block: block)

      refute html =~ "Use as constant"
    end
  end

  describe "config_panel/1 — variable name" do
    test "renders variable name for variable-capable, non-constant blocks" do
      block = build_block(%{type: "text", is_constant: false, variable_name: "my_field"})
      html = render_component(&ConfigPanel.config_panel/1, block: block)

      assert html =~ "Variable Name"
      assert html =~ "my_field"
      assert html =~ "Use this name to reference the value in flows"
    end

    test "shows derived hint when variable_name is nil" do
      block = build_block(%{type: "number", is_constant: false, variable_name: nil})
      html = render_component(&ConfigPanel.config_panel/1, block: block)

      assert html =~ "(derived from label)"
    end

    test "does not render variable name when is_constant is true" do
      block = build_block(%{type: "text", is_constant: true, variable_name: "my_field"})
      html = render_component(&ConfigPanel.config_panel/1, block: block)

      refute html =~ "Variable Name"
    end

    test "does not render variable name for non-variable types" do
      block = build_block(%{type: "divider", config: %{}})
      html = render_component(&ConfigPanel.config_panel/1, block: block)

      refute html =~ "Variable Name"
    end
  end

  describe "config_panel/1 — text type fields" do
    test "renders placeholder field for text blocks" do
      block =
        build_block(%{type: "text", config: %{"label" => "Name", "placeholder" => "Enter name"}})

      html = render_component(&ConfigPanel.config_panel/1, block: block)

      assert html =~ "Placeholder"
      assert html =~ "config[placeholder]"
      assert html =~ "Enter name"
    end

    test "renders max length field for text blocks" do
      block = build_block(%{type: "text", config: %{"label" => "Name", "max_length" => 100}})
      html = render_component(&ConfigPanel.config_panel/1, block: block)

      assert html =~ "Max Length"
      assert html =~ "config[max_length]"
    end

    test "renders max length field for rich_text blocks" do
      block =
        build_block(%{
          type: "rich_text",
          config: %{"label" => "Description", "max_length" => 500}
        })

      html = render_component(&ConfigPanel.config_panel/1, block: block)

      assert html =~ "Max Length"
      assert html =~ "config[max_length]"
    end
  end

  describe "config_panel/1 — number type fields" do
    test "renders min/max fields for number blocks" do
      block =
        build_block(%{type: "number", config: %{"label" => "Health", "min" => 0, "max" => 100}})

      html = render_component(&ConfigPanel.config_panel/1, block: block)

      assert html =~ "Min"
      assert html =~ "Max"
      assert html =~ "config[min]"
      assert html =~ "config[max]"
    end

    test "renders step field for number blocks" do
      block = build_block(%{type: "number", config: %{"label" => "Health", "step" => 5}})
      html = render_component(&ConfigPanel.config_panel/1, block: block)

      assert html =~ "Step"
      assert html =~ "config[step]"
    end

    test "renders placeholder for number blocks" do
      block = build_block(%{type: "number", config: %{"label" => "Health", "placeholder" => "0"}})
      html = render_component(&ConfigPanel.config_panel/1, block: block)

      assert html =~ "Placeholder"
    end

    test "does not render min/max for non-number blocks" do
      block = build_block(%{type: "text", config: %{"label" => "Name"}})
      html = render_component(&ConfigPanel.config_panel/1, block: block)

      refute html =~ "config[min]"
      refute html =~ "config[max]"
      refute html =~ "config[step]"
    end
  end

  describe "config_panel/1 — date type fields" do
    test "renders min/max date fields for date blocks" do
      block =
        build_block(%{
          type: "date",
          config: %{"label" => "Birthday", "min_date" => "2000-01-01", "max_date" => "2025-12-31"}
        })

      html = render_component(&ConfigPanel.config_panel/1, block: block)

      assert html =~ "Min Date"
      assert html =~ "Max Date"
      assert html =~ "config[min_date]"
      assert html =~ "config[max_date]"
    end

    test "does not render date fields for non-date blocks" do
      block = build_block(%{type: "text", config: %{"label" => "Name"}})
      html = render_component(&ConfigPanel.config_panel/1, block: block)

      refute html =~ "Min Date"
      refute html =~ "Max Date"
    end
  end

  describe "config_panel/1 — select and multi_select type fields" do
    test "renders options section for select blocks" do
      block =
        build_block(%{
          type: "select",
          config: %{
            "label" => "Class",
            "placeholder" => "Choose...",
            "options" => [
              %{"key" => "warrior", "value" => "Warrior"},
              %{"key" => "mage", "value" => "Mage"}
            ]
          }
        })

      html = render_component(&ConfigPanel.config_panel/1, block: block)

      assert html =~ "Options"
      assert html =~ "warrior"
      assert html =~ "Warrior"
      assert html =~ "mage"
      assert html =~ "Mage"
      assert html =~ "Add option"
      assert html =~ "add_select_option"
      assert html =~ "remove_select_option"
      assert html =~ "update_select_option"
    end

    test "renders options section for multi_select blocks" do
      block =
        build_block(%{
          type: "multi_select",
          config: %{
            "label" => "Tags",
            "options" => [%{"key" => "tag1", "value" => "Tag 1"}]
          }
        })

      html = render_component(&ConfigPanel.config_panel/1, block: block)

      assert html =~ "Options"
      assert html =~ "tag1"
      assert html =~ "Tag 1"
      assert html =~ "Add option"
    end

    test "renders max selections field for multi_select blocks" do
      block =
        build_block(%{
          type: "multi_select",
          config: %{"label" => "Tags", "max_options" => 3}
        })

      html = render_component(&ConfigPanel.config_panel/1, block: block)

      assert html =~ "Max Selections"
      assert html =~ "config[max_options]"
    end

    test "renders placeholder for select blocks" do
      block =
        build_block(%{type: "select", config: %{"label" => "Class", "placeholder" => "Pick one"}})

      html = render_component(&ConfigPanel.config_panel/1, block: block)

      assert html =~ "Placeholder"
      assert html =~ "Pick one"
    end

    test "renders empty options list" do
      block = build_block(%{type: "select", config: %{"label" => "Class", "options" => []}})
      html = render_component(&ConfigPanel.config_panel/1, block: block)

      assert html =~ "Options"
      assert html =~ "Add option"
      # No option key/value inputs should be present
      refute html =~ "update_select_option"
    end

    test "does not render options for non-select blocks" do
      block = build_block(%{type: "text", config: %{"label" => "Name"}})
      html = render_component(&ConfigPanel.config_panel/1, block: block)

      refute html =~ "add_select_option"
      refute html =~ "remove_select_option"
    end
  end

  describe "config_panel/1 — boolean type fields" do
    test "renders mode selector for boolean blocks" do
      block =
        build_block(%{type: "boolean", config: %{"label" => "Is Active", "mode" => "two_state"}})

      html = render_component(&ConfigPanel.config_panel/1, block: block)

      assert html =~ "Mode"
      assert html =~ "config[mode]"
      assert html =~ "Two states (Yes/No)"
      assert html =~ "Three states (Yes/Neutral/No)"
      assert html =~ "Tri-state allows a neutral/unknown value"
    end

    test "renders custom labels for boolean blocks" do
      block =
        build_block(%{
          type: "boolean",
          config: %{
            "label" => "Alive",
            "true_label" => "Living",
            "false_label" => "Dead",
            "mode" => "two_state"
          }
        })

      html = render_component(&ConfigPanel.config_panel/1, block: block)

      assert html =~ "Custom Labels"
      assert html =~ "config[true_label]"
      assert html =~ "config[false_label]"
      assert html =~ "Living"
      assert html =~ "Dead"
      assert html =~ "Leave empty to use defaults"
    end

    test "renders neutral label only for tri_state mode" do
      block =
        build_block(%{
          type: "boolean",
          config: %{
            "label" => "Status",
            "mode" => "tri_state",
            "neutral_label" => "Unknown"
          }
        })

      html = render_component(&ConfigPanel.config_panel/1, block: block)

      assert html =~ "config[neutral_label]"
      assert html =~ "Unknown"
      assert html =~ "Neutral/Unknown"
    end

    test "does not render neutral label for two_state mode" do
      block =
        build_block(%{
          type: "boolean",
          config: %{"label" => "Active", "mode" => "two_state"}
        })

      html = render_component(&ConfigPanel.config_panel/1, block: block)

      refute html =~ "config[neutral_label]"
      refute html =~ "Neutral/Unknown"
    end

    test "does not render mode selector for non-boolean blocks" do
      block = build_block(%{type: "text", config: %{"label" => "Name"}})
      html = render_component(&ConfigPanel.config_panel/1, block: block)

      refute html =~ "config[mode]"
      refute html =~ "Two states"
    end
  end

  describe "config_panel/1 — reference type fields" do
    test "renders allowed types for reference blocks" do
      block =
        build_block(%{
          type: "reference",
          config: %{"label" => "Link", "allowed_types" => ["sheet", "flow"]}
        })

      html = render_component(&ConfigPanel.config_panel/1, block: block)

      assert html =~ "Allowed Types"
      assert html =~ "Sheets"
      assert html =~ "Flows"
      assert html =~ "Select which types can be referenced"
    end

    test "handles partial allowed_types" do
      block =
        build_block(%{
          type: "reference",
          config: %{"label" => "Link", "allowed_types" => ["sheet"]}
        })

      html = render_component(&ConfigPanel.config_panel/1, block: block)

      assert html =~ "Allowed Types"
    end

    test "does not render allowed types for non-reference blocks" do
      block = build_block(%{type: "text", config: %{"label" => "Name"}})
      html = render_component(&ConfigPanel.config_panel/1, block: block)

      refute html =~ "Allowed Types"
    end
  end

  describe "config_panel/1 — assign_config_fields defaults" do
    test "handles nil config gracefully" do
      block = build_block(%{config: nil, type: "text"})
      html = render_component(&ConfigPanel.config_panel/1, block: block)

      # Should render with empty defaults
      assert html =~ "Configure Block"
      assert html =~ "config[label]"
    end

    test "handles empty config map" do
      block = build_block(%{config: %{}, type: "text"})
      html = render_component(&ConfigPanel.config_panel/1, block: block)

      assert html =~ "Configure Block"
    end

    test "handles missing individual config keys" do
      block = build_block(%{config: %{"label" => "Test"}, type: "number"})
      html = render_component(&ConfigPanel.config_panel/1, block: block)

      # Min, max, step should render with empty/nil values
      assert html =~ "config[min]"
      assert html =~ "config[max]"
      assert html =~ "config[step]"
    end
  end

  # ===========================================================================
  # Integration tests — config panel through LiveView
  # ===========================================================================

  describe "config panel integration — text block" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Config Panel Sheet"})
      %{project: project, workspace: project.workspace, sheet: sheet}
    end

    test "opens config panel for text block", ctx do
      block = block_fixture(ctx.sheet, %{type: "text", config: %{"label" => "Character Name"}})

      {:ok, view, _html} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)
      html = open_config_panel(view, block)

      assert html =~ "Configure Block"
      assert html =~ "text"
      assert html =~ "Character Name"
      assert html =~ "Placeholder"
      assert html =~ "Max Length"
    end
  end

  describe "config panel integration — number block" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Number Config Sheet"})
      %{project: project, workspace: project.workspace, sheet: sheet}
    end

    test "opens config panel for number block with type-specific fields", ctx do
      block =
        block_fixture(ctx.sheet, %{
          type: "number",
          config: %{"label" => "Health", "min" => 0, "max" => 100, "step" => 5}
        })

      {:ok, view, _html} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)
      html = open_config_panel(view, block)

      assert html =~ "Configure Block"
      assert html =~ "number"
      assert html =~ "Min"
      assert html =~ "Max"
      assert html =~ "Step"
    end
  end

  describe "config panel integration — select block" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Select Config Sheet"})
      %{project: project, workspace: project.workspace, sheet: sheet}
    end

    test "opens config panel for select block with options", ctx do
      block =
        block_fixture(ctx.sheet, %{
          type: "select",
          config: %{
            "label" => "Class",
            "placeholder" => "Choose...",
            "options" => [
              %{"key" => "warrior", "value" => "Warrior"},
              %{"key" => "mage", "value" => "Mage"}
            ]
          }
        })

      {:ok, view, _html} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)
      html = open_config_panel(view, block)

      assert html =~ "Configure Block"
      assert html =~ "Options"
      assert html =~ "warrior"
      assert html =~ "Warrior"
      assert html =~ "mage"
      assert html =~ "Mage"
      assert html =~ "Add option"
    end
  end

  describe "config panel integration — boolean block" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Boolean Config Sheet"})
      %{project: project, workspace: project.workspace, sheet: sheet}
    end

    test "opens config panel for boolean block with mode selector", ctx do
      block =
        block_fixture(ctx.sheet, %{
          type: "boolean",
          config: %{"label" => "Is Alive", "mode" => "two_state"}
        })

      {:ok, view, _html} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)
      html = open_config_panel(view, block)

      assert html =~ "Configure Block"
      assert html =~ "boolean"
      assert html =~ "Mode"
      assert html =~ "Two states"
      assert html =~ "Custom Labels"
    end
  end

  describe "config panel integration — date block" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Date Config Sheet"})
      %{project: project, workspace: project.workspace, sheet: sheet}
    end

    test "opens config panel for date block with date range fields", ctx do
      block =
        block_fixture(ctx.sheet, %{
          type: "date",
          config: %{"label" => "Birth Date"}
        })

      {:ok, view, _html} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)
      html = open_config_panel(view, block)

      assert html =~ "Configure Block"
      assert html =~ "date"
      assert html =~ "Min Date"
      assert html =~ "Max Date"
    end
  end

  describe "config panel integration — reference block" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Reference Config Sheet"})
      %{project: project, workspace: project.workspace, sheet: sheet}
    end

    test "opens config panel for reference block with allowed types", ctx do
      block =
        block_fixture(ctx.sheet, %{
          type: "reference",
          config: %{"label" => "Related Entity", "allowed_types" => ["sheet", "flow"]}
        })

      {:ok, view, _html} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)
      html = open_config_panel(view, block)

      assert html =~ "Configure Block"
      assert html =~ "reference"
      assert html =~ "Allowed Types"
      assert html =~ "Sheets"
      assert html =~ "Flows"
    end
  end

  describe "config panel integration — divider block" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Divider Config Sheet"})
      %{project: project, workspace: project.workspace, sheet: sheet}
    end

    test "opens config panel for divider with no label or variable fields", ctx do
      block = block_fixture(ctx.sheet, %{type: "divider", config: %{}})

      {:ok, view, _html} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)
      html = open_config_panel(view, block)

      assert html =~ "Configure Block"
      assert html =~ "divider"
      # Divider should not have label, variable name, constant toggle, or scope
      refute html =~ "config[label]"
      refute html =~ "Variable Name"
      refute html =~ "Use as constant"
      refute html =~ "Scope"
    end
  end

  describe "config panel integration — multi_select block" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Multi Select Config Sheet"})
      %{project: project, workspace: project.workspace, sheet: sheet}
    end

    test "opens config panel for multi_select with max selections", ctx do
      block =
        block_fixture(ctx.sheet, %{
          type: "multi_select",
          config: %{
            "label" => "Tags",
            "max_options" => 5,
            "options" => [%{"key" => "a", "value" => "Alpha"}]
          },
          value: %{"content" => []}
        })

      {:ok, view, _html} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)
      html = open_config_panel(view, block)

      assert html =~ "Configure Block"
      assert html =~ "multi_select"
      assert html =~ "Max Selections"
      assert html =~ "Options"
      assert html =~ "Alpha"
    end
  end

  describe "config panel integration — rich_text block" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Rich Text Config Sheet"})
      %{project: project, workspace: project.workspace, sheet: sheet}
    end

    test "opens config panel for rich_text with max length and placeholder", ctx do
      block =
        block_fixture(ctx.sheet, %{
          type: "rich_text",
          config: %{"label" => "Bio"}
        })

      {:ok, view, _html} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)
      html = open_config_panel(view, block)

      assert html =~ "Configure Block"
      assert html =~ "rich_text"
      assert html =~ "Max Length"
      # rich_text has placeholder in the allowed types list
      assert html =~ "Placeholder"
    end
  end

  describe "config panel integration — close panel" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Close Config Sheet"})
      %{project: project, workspace: project.workspace, sheet: sheet}
    end

    test "closes config panel", ctx do
      block = block_fixture(ctx.sheet, %{type: "text", config: %{"label" => "Test"}})

      {:ok, view, _html} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)

      # Open
      open_config_panel(view, block)
      assert render(view) =~ "Configure Block"

      # Close
      send_to_content_tab(view, "close_config_panel")
      refute render(view) =~ "Configure Block"
    end
  end

  describe "config panel integration — scope and variable fields" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Scope Config Sheet"})
      %{project: project, workspace: project.workspace, sheet: sheet}
    end

    test "shows variable name and constant toggle for text block", ctx do
      block = block_fixture(ctx.sheet, %{type: "text", config: %{"label" => "Name"}})

      {:ok, view, _html} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)
      html = open_config_panel(view, block)

      assert html =~ "Variable Name"
      assert html =~ "Use as constant"
      assert html =~ "Scope"
    end

    test "toggles constant hides variable name", ctx do
      block = block_fixture(ctx.sheet, %{type: "text", config: %{"label" => "Name"}})

      {:ok, view, _html} = mount_sheet(ctx.conn, ctx.workspace, ctx.project, ctx.sheet)
      open_config_panel(view, block)

      # Toggle constant on
      send_to_content_tab(view, "toggle_constant")

      html = render(view)
      # When is_constant is true, variable name field should be hidden
      refute html =~ "Use this name to reference the value in flows"
    end
  end
end

defmodule StoryarnWeb.FlowLive.Helpers.VariableHelpersTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Sheets
  alias StoryarnWeb.FlowLive.Helpers.VariableHelpers

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.SheetsFixtures

  defp setup_project(_context \\ %{}) do
    user = user_fixture()
    project = project_fixture(user)
    %{project: project}
  end

  describe "build_variables/1 with no sheets" do
    test "returns empty map when project has no sheets" do
      %{project: project} = setup_project()

      assert VariableHelpers.build_variables(project.id) == %{}
    end
  end

  describe "build_variables/1 with text blocks" do
    test "builds variable for text block with content" do
      %{project: project} = setup_project()
      sheet = sheet_fixture(project, %{name: "Character"})

      _block =
        block_fixture(sheet, %{
          type: "text",
          config: %{"label" => "Name"},
          value: %{"content" => "Jaime"}
        })

      result = VariableHelpers.build_variables(project.id)

      key = "#{sheet.shortcut}.name"
      assert Map.has_key?(result, key)
      var = result[key]

      assert var.value == "Jaime"
      assert var.initial_value == "Jaime"
      assert var.previous_value == "Jaime"
      assert var.source == :initial
      assert var.block_type == "text"
      assert var.sheet_shortcut == sheet.shortcut
      assert var.variable_name == "name"
    end

    test "defaults to empty string for text block with no content" do
      %{project: project} = setup_project()
      sheet = sheet_fixture(project, %{name: "NPC"})

      _block =
        block_fixture(sheet, %{
          type: "text",
          config: %{"label" => "Greeting"},
          value: %{}
        })

      result = VariableHelpers.build_variables(project.id)
      key = "#{sheet.shortcut}.greeting"
      assert result[key].value == ""
    end

    test "defaults to empty string for text block with nil content" do
      %{project: project} = setup_project()
      sheet = sheet_fixture(project, %{name: "NPC2"})

      _block =
        block_fixture(sheet, %{
          type: "text",
          config: %{"label" => "Dialogue"},
          value: %{"content" => nil}
        })

      result = VariableHelpers.build_variables(project.id)
      key = "#{sheet.shortcut}.dialogue"
      # nil content means extract_initial_value falls to type_default
      assert result[key].value == ""
    end
  end

  describe "build_variables/1 with number blocks" do
    test "coerces integer string to integer" do
      %{project: project} = setup_project()
      sheet = sheet_fixture(project, %{name: "Stats"})

      _block =
        block_fixture(sheet, %{
          type: "number",
          config: %{"label" => "Health"},
          value: %{"content" => "42"}
        })

      result = VariableHelpers.build_variables(project.id)
      key = "#{sheet.shortcut}.health"

      assert result[key].value == 42
      assert is_integer(result[key].value)
    end

    test "coerces float string to float" do
      %{project: project} = setup_project()
      sheet = sheet_fixture(project, %{name: "Physics"})

      _block =
        block_fixture(sheet, %{
          type: "number",
          config: %{"label" => "Speed"},
          value: %{"content" => "3.14"}
        })

      result = VariableHelpers.build_variables(project.id)
      key = "#{sheet.shortcut}.speed"

      assert result[key].value == 3.14
      assert is_float(result[key].value)
    end

    test "returns type default for invalid number string" do
      %{project: project} = setup_project()
      sheet = sheet_fixture(project, %{name: "Broken"})

      _block =
        block_fixture(sheet, %{
          type: "number",
          config: %{"label" => "Armor"},
          value: %{"content" => "not_a_number"}
        })

      result = VariableHelpers.build_variables(project.id)
      key = "#{sheet.shortcut}.armor"

      assert result[key].value == 0
    end

    test "returns type default for partially valid number string" do
      %{project: project} = setup_project()
      sheet = sheet_fixture(project, %{name: "Partial"})

      _block =
        block_fixture(sheet, %{
          type: "number",
          config: %{"label" => "Power"},
          value: %{"content" => "42abc"}
        })

      result = VariableHelpers.build_variables(project.id)
      key = "#{sheet.shortcut}.power"

      # Float.parse("42abc") returns {42.0, "abc"} — not an exact match,
      # so it falls through to type_default
      assert result[key].value == 0
    end

    test "defaults to 0 when number block has no content" do
      %{project: project} = setup_project()
      sheet = sheet_fixture(project, %{name: "Empty"})

      _block =
        block_fixture(sheet, %{
          type: "number",
          config: %{"label" => "Score"},
          value: %{}
        })

      result = VariableHelpers.build_variables(project.id)
      key = "#{sheet.shortcut}.score"

      assert result[key].value == 0
    end

    test "coerces whole float to integer (e.g. '10.0' -> 10)" do
      %{project: project} = setup_project()
      sheet = sheet_fixture(project, %{name: "Whole"})

      _block =
        block_fixture(sheet, %{
          type: "number",
          config: %{"label" => "Level"},
          value: %{"content" => "10.0"}
        })

      result = VariableHelpers.build_variables(project.id)
      key = "#{sheet.shortcut}.level"

      assert result[key].value == 10
      assert is_integer(result[key].value)
    end
  end

  describe "build_variables/1 with boolean blocks" do
    test "defaults to false for boolean block with no content" do
      %{project: project} = setup_project()
      sheet = sheet_fixture(project, %{name: "Flags"})

      _block =
        block_fixture(sheet, %{
          type: "boolean",
          config: %{"label" => "Is Alive"},
          value: %{}
        })

      result = VariableHelpers.build_variables(project.id)
      key = "#{sheet.shortcut}.is_alive"

      assert result[key].value == false
      assert result[key].block_type == "boolean"
    end

    test "preserves boolean content value" do
      %{project: project} = setup_project()
      sheet = sheet_fixture(project, %{name: "Toggles"})

      _block =
        block_fixture(sheet, %{
          type: "boolean",
          config: %{"label" => "Active"},
          value: %{"content" => true}
        })

      result = VariableHelpers.build_variables(project.id)
      key = "#{sheet.shortcut}.active"

      assert result[key].value == true
    end
  end

  describe "build_variables/1 with rich_text blocks" do
    test "defaults to empty string for rich_text block" do
      %{project: project} = setup_project()
      sheet = sheet_fixture(project, %{name: "Notes"})

      _block =
        block_fixture(sheet, %{
          type: "rich_text",
          config: %{"label" => "Biography"},
          value: %{}
        })

      result = VariableHelpers.build_variables(project.id)
      key = "#{sheet.shortcut}.biography"

      assert result[key].value == ""
      assert result[key].block_type == "rich_text"
    end

    test "extracts content from rich_text block" do
      %{project: project} = setup_project()
      sheet = sheet_fixture(project, %{name: "Lore"})

      _block =
        block_fixture(sheet, %{
          type: "rich_text",
          config: %{"label" => "Backstory"},
          value: %{"content" => "<p>Once upon a time</p>"}
        })

      result = VariableHelpers.build_variables(project.id)
      key = "#{sheet.shortcut}.backstory"

      assert result[key].value == "<p>Once upon a time</p>"
    end
  end

  describe "build_variables/1 with date blocks" do
    test "defaults to nil for date block" do
      %{project: project} = setup_project()
      sheet = sheet_fixture(project, %{name: "Timeline"})

      _block =
        block_fixture(sheet, %{
          type: "date",
          config: %{"label" => "Birthday"},
          value: %{}
        })

      result = VariableHelpers.build_variables(project.id)
      key = "#{sheet.shortcut}.birthday"

      assert result[key].value == nil
      assert result[key].block_type == "date"
    end

    test "extracts content from date block" do
      %{project: project} = setup_project()
      sheet = sheet_fixture(project, %{name: "Events"})

      _block =
        block_fixture(sheet, %{
          type: "date",
          config: %{"label" => "Due Date"},
          value: %{"content" => "2025-03-15"}
        })

      result = VariableHelpers.build_variables(project.id)
      key = "#{sheet.shortcut}.due_date"

      assert result[key].value == "2025-03-15"
    end
  end

  describe "build_variables/1 with select blocks" do
    test "defaults to nil for select block with no content" do
      %{project: project} = setup_project()
      sheet = sheet_fixture(project, %{name: "Classes"})

      _block =
        block_fixture(sheet, %{
          type: "select",
          config: %{
            "label" => "Class",
            "options" => [%{"label" => "Warrior"}, %{"label" => "Mage"}]
          },
          value: %{}
        })

      result = VariableHelpers.build_variables(project.id)
      key = "#{sheet.shortcut}.class"

      # select falls through to type_default which is the catch-all nil
      assert result[key].value == nil
    end

    test "extracts content from select block" do
      %{project: project} = setup_project()
      sheet = sheet_fixture(project, %{name: "Races"})

      _block =
        block_fixture(sheet, %{
          type: "select",
          config: %{
            "label" => "Race",
            "options" => [%{"label" => "Elf"}, %{"label" => "Dwarf"}]
          },
          value: %{"content" => "Elf"}
        })

      result = VariableHelpers.build_variables(project.id)
      key = "#{sheet.shortcut}.race"

      assert result[key].value == "Elf"
    end
  end

  describe "build_variables/1 excludes non-variables" do
    test "excludes constant blocks" do
      %{project: project} = setup_project()
      sheet = sheet_fixture(project, %{name: "Constants"})

      _block =
        block_fixture(sheet, %{
          type: "text",
          config: %{"label" => "Title"},
          value: %{"content" => "Lord"},
          is_constant: true
        })

      result = VariableHelpers.build_variables(project.id)

      # Constant blocks should not appear
      assert result == %{}
    end

    test "excludes reference blocks" do
      %{project: project} = setup_project()
      sheet = sheet_fixture(project, %{name: "Layout"})

      # Reference blocks don't generate variable_name
      {:ok, _block} =
        Storyarn.Sheets.create_block(sheet, %{
          type: "reference",
          config: %{"label" => "Link", "allowed_types" => ["sheet"]}
        })

      result = VariableHelpers.build_variables(project.id)
      assert result == %{}
    end
  end

  describe "build_variables/1 with multiple sheets" do
    test "builds variables from multiple sheets" do
      %{project: project} = setup_project()

      sheet1 = sheet_fixture(project, %{name: "MC Jaime"})
      sheet2 = sheet_fixture(project, %{name: "NPC Guard"})

      _block1 =
        block_fixture(sheet1, %{
          type: "number",
          config: %{"label" => "Health"},
          value: %{"content" => "100"}
        })

      _block2 =
        block_fixture(sheet2, %{
          type: "text",
          config: %{"label" => "Name"},
          value: %{"content" => "Aldric"}
        })

      result = VariableHelpers.build_variables(project.id)

      assert map_size(result) == 2
      assert result["#{sheet1.shortcut}.health"].value == 100
      assert result["#{sheet2.shortcut}.name"].value == "Aldric"
    end
  end

  describe "build_variables/1 variable map structure" do
    test "includes all expected fields in variable entry" do
      %{project: project} = setup_project()
      sheet = sheet_fixture(project, %{name: "Hero"})

      block =
        block_fixture(sheet, %{
          type: "number",
          config: %{"label" => "Strength"},
          value: %{"content" => "15"}
        })

      result = VariableHelpers.build_variables(project.id)
      key = "#{sheet.shortcut}.strength"
      var = result[key]

      assert var.value == 15
      assert var.initial_value == 15
      assert var.previous_value == 15
      assert var.source == :initial
      assert var.block_type == "number"
      assert var.block_id == block.id
      assert var.sheet_shortcut == sheet.shortcut
      assert var.variable_name == "strength"
      assert Map.has_key?(var, :constraints)
      assert var.source_type == "sheet"
      assert var.source_id == nil
    end
  end

  describe "build_variables/1 with multi_select blocks" do
    test "defaults to nil for multi_select block with no content" do
      %{project: project} = setup_project()
      sheet = sheet_fixture(project, %{name: "Traits"})

      _block =
        block_fixture(sheet, %{
          type: "multi_select",
          config: %{
            "label" => "Skills",
            "options" => [%{"label" => "Stealth"}, %{"label" => "Combat"}]
          },
          value: %{}
        })

      result = VariableHelpers.build_variables(project.id)
      key = "#{sheet.shortcut}.skills"

      # multi_select falls through to the catch-all type_default => nil
      assert result[key].value == nil
      assert result[key].block_type == "multi_select"
    end

    test "extracts content list from multi_select block" do
      %{project: project} = setup_project()
      sheet = sheet_fixture(project, %{name: "Abilities"})

      _block =
        block_fixture(sheet, %{
          type: "multi_select",
          config: %{
            "label" => "Tags",
            "options" => [%{"label" => "Fast"}, %{"label" => "Strong"}]
          },
          value: %{"content" => ["Fast", "Strong"]}
        })

      result = VariableHelpers.build_variables(project.id)
      key = "#{sheet.shortcut}.tags"

      assert result[key].value == ["Fast", "Strong"]
    end
  end

  describe "build_variables/1 coerce_value passthrough" do
    test "non-number types pass through coerce_value unchanged" do
      %{project: project} = setup_project()
      sheet = sheet_fixture(project, %{name: "Passthrough"})

      _block =
        block_fixture(sheet, %{
          type: "boolean",
          config: %{"label" => "Flag"},
          value: %{"content" => true}
        })

      result = VariableHelpers.build_variables(project.id)
      key = "#{sheet.shortcut}.flag"

      # boolean content goes through coerce_value with non-"number" type
      # and is returned unchanged
      assert result[key].value == true
    end
  end

  describe "build_variables/1 with table blocks" do
    test "builds variables from table cells (cell_value path)" do
      %{project: project} = setup_project()
      sheet = sheet_fixture(project, %{name: "Inventory"})

      table_block = table_block_fixture(sheet, %{label: "Items"})

      # Table blocks auto-create a default column and row.
      # We need to create a non-constant number column with a cell value.
      col = table_column_fixture(table_block, %{name: "Quantity", type: "number"})
      row = table_row_fixture(table_block, %{name: "Potions"})

      # Set a cell value
      Storyarn.Sheets.update_table_cell(row, col.slug, "5")

      result = VariableHelpers.build_variables(project.id)

      # Table variables use composite key: sheet_shortcut.table_var.row_slug.col_slug
      matching =
        Enum.filter(result, fn {key, var} ->
          var.block_type == "number" and String.contains?(key, col.slug)
        end)

      # Should find at least one variable from the table with the cell value coerced
      assert matching != []

      {_key, var} = hd(matching)
      assert var.value == 5
    end
  end

  describe "build_variables/1 with formula columns" do
    test "attaches formula metadata and computes initial value" do
      %{project: project} = setup_project()
      sheet = sheet_fixture(project, %{name: "Stats"})
      table = table_block_fixture(sheet, %{label: "Attrs"})

      # Default column is "Value" (slug: "value", type: "number")
      [default_col] = table.table_columns
      modifier_col = table_column_fixture(table, %{name: "Modifier", type: "formula"})

      [default_row] = table.table_rows

      # Chain updates to avoid stale row.cells
      {:ok, row} = Sheets.update_table_cell(default_row, default_col.slug, "10")

      formula_cell = %{
        "expression" => "a - 3",
        "bindings" => %{
          "a" => %{"type" => "same_row", "column_slug" => default_col.slug}
        }
      }

      {:ok, _row} = Sheets.update_table_cell(row, modifier_col.slug, formula_cell)

      result = VariableHelpers.build_variables(project.id)

      # Find the formula variable
      formula_vars =
        Enum.filter(result, fn {_key, var} ->
          var.block_type == "formula"
        end)

      assert formula_vars != [], "Should have at least one formula variable"

      {_key, var} = hd(formula_vars)

      # Should have formula metadata
      assert is_map(var[:formula])
      assert var.formula.expression == "a - 3"
      assert is_map(var.formula.bindings)

      # Bindings should be translated to full variable refs
      binding_ref = var.formula.bindings["a"]
      assert is_binary(binding_ref)
      assert String.contains?(binding_ref, default_col.slug)

      # Value should be computed (10 - 3 = 7), not nil
      assert var.value == 7

      # Value column variable should exist and have value 10
      value_vars =
        Enum.filter(result, fn {_k, v} ->
          v.block_type == "number" and String.contains?(v.variable_name, default_col.slug)
        end)

      assert value_vars != []
      {_vk, vv} = hd(value_vars)
      assert vv.value == 10
    end

    test "formula referencing another formula computes in order" do
      %{project: project} = setup_project()
      sheet = sheet_fixture(project, %{name: "Combat"})
      table = table_block_fixture(sheet, %{label: "Calcs"})

      # Default column is "Value" (slug: "value", type: "number") — use as base
      [default_col] = table.table_columns
      mid_col = table_column_fixture(table, %{name: "Mid", type: "formula"})
      top_col = table_column_fixture(table, %{name: "Top", type: "formula"})

      [default_row] = table.table_rows

      # Chain updates to avoid stale row.cells
      {:ok, row} = Sheets.update_table_cell(default_row, default_col.slug, "5")

      # mid = base * 2
      {:ok, row} =
        Sheets.update_table_cell(row, mid_col.slug, %{
          "expression" => "a * 2",
          "bindings" => %{
            "a" => %{"type" => "same_row", "column_slug" => default_col.slug}
          }
        })

      # top = mid + 1
      {:ok, _row} =
        Sheets.update_table_cell(row, top_col.slug, %{
          "expression" => "a + 1",
          "bindings" => %{
            "a" => %{"type" => "same_row", "column_slug" => mid_col.slug}
          }
        })

      result = VariableHelpers.build_variables(project.id)

      mid_var =
        Enum.find_value(result, fn {_k, v} ->
          if v.block_type == "formula" and String.contains?(v.variable_name, mid_col.slug), do: v
        end)

      top_var =
        Enum.find_value(result, fn {_k, v} ->
          if v.block_type == "formula" and String.contains?(v.variable_name, top_col.slug), do: v
        end)

      assert mid_var.value == 10
      assert top_var.value == 11
    end

    test "non-formula variables have no formula key" do
      %{project: project} = setup_project()
      sheet = sheet_fixture(project, %{name: "Simple"})

      block_fixture(sheet, %{
        type: "number",
        config: %{"label" => "Health"},
        value: %{"content" => "50"}
      })

      result = VariableHelpers.build_variables(project.id)
      {_key, var} = hd(Enum.to_list(result))

      refute Map.has_key?(var, :formula)
    end
  end

  describe "build_variables/1 with pin/zone variables" do
    test "coerces pin boolean values and sets correct metadata" do
      %{project: project} = setup_project()
      scene = scene_fixture(project)

      _pin =
        pin_fixture(scene, %{
          "shortcut" => "guard.west",
          "label" => "West Guard",
          "hidden" => false,
          "is_playable" => true,
          "is_leader" => false
        })

      result = VariableHelpers.build_variables(project.id)

      # Verify coerced values (not raw %{"content" => ...})
      assert result["guard.west.hidden"].value == false
      assert result["guard.west.is_playable"].value == true
      assert result["guard.west.is_leader"].value == false

      # Verify source metadata is set
      assert result["guard.west.hidden"].source_type == "pin"
      assert result["guard.west.hidden"].source == :initial
      assert result["guard.west.hidden"].block_id == nil
    end

    test "coerces zone boolean values" do
      %{project: project} = setup_project()
      scene = scene_fixture(project)

      _zone =
        zone_fixture(scene, %{
          "shortcut" => "tavern.door",
          "name" => "Tavern Door",
          "hidden" => false,
          "is_walkable" => true
        })

      result = VariableHelpers.build_variables(project.id)

      assert result["tavern.door.hidden"].value == false
      assert result["tavern.door.is_walkable"].value == true
      assert result["tavern.door.hidden"].source_type == "zone"
    end

    test "sheet, pin, and zone variables coexist in the same map" do
      %{project: project} = setup_project()
      sheet = sheet_fixture(project, %{name: "Hero"})

      _block =
        block_fixture(sheet, %{
          type: "number",
          config: %{"label" => "Health"},
          value: %{"content" => "100"}
        })

      scene = scene_fixture(project)
      _pin = pin_fixture(scene, %{"shortcut" => "npc.guard", "label" => "Guard"})
      _zone = zone_fixture(scene, %{"shortcut" => "area.gate", "name" => "Gate"})

      result = VariableHelpers.build_variables(project.id)

      # Sheet variable
      assert result["#{sheet.shortcut}.health"].source_type == "sheet"
      assert result["#{sheet.shortcut}.health"].value == 100
      # Pin variable
      assert result["npc.guard.hidden"].source_type == "pin"
      # Zone variable
      assert result["area.gate.is_walkable"].source_type == "zone"
    end

    test "last source wins when shortcut collides between sheet and pin" do
      %{project: project} = setup_project()

      # Sheet with shortcut "guard" and variable "hidden"
      sheet = sheet_fixture(project, %{name: "Guard", shortcut: "guard"})

      _block =
        block_fixture(sheet, %{
          type: "boolean",
          config: %{"label" => "Hidden"},
          value: %{"content" => true}
        })

      # Pin also with shortcut "guard" — its "hidden" will collide
      scene = scene_fixture(project)

      _pin =
        pin_fixture(scene, %{
          "shortcut" => "guard",
          "label" => "Guard Pin",
          "hidden" => false
        })

      result = VariableHelpers.build_variables(project.id)

      # Pin variables are appended after sheet variables, so pin wins
      assert result["guard.hidden"].source_type == "pin"
      assert result["guard.hidden"].value == false
    end
  end
end

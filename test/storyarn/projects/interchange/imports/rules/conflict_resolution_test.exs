defmodule Storyarn.Projects.Imports.ConflictResolutionTest do
  use ExUnit.Case, async: true

  alias Storyarn.Projects.Imports.ConflictResolution

  describe "preflight/3" do
    test "rejects overwrite when an imported shortcut already exists" do
      imported = %{sheet: [entity("hero")], flow: [], scene: []}
      active = %{sheet: %{"hero" => 41}, flow: %{}, scene: %{}}

      assert {:error, :overwrite_conflict_requires_rename} =
               ConflictResolution.preflight(:overwrite, imported, active)
    end

    test "rejects overwrite and skip when one import contains an ambiguous shortcut" do
      imported = %{sheet: [], flow: [entity("shared"), entity("shared")], scene: []}
      active = %{sheet: %{}, flow: %{}, scene: %{}}

      assert {:error, :overwrite_conflict_requires_rename} =
               ConflictResolution.preflight(:overwrite, imported, active)

      assert {:error, :skip_conflict_ambiguous} =
               ConflictResolution.preflight(:skip, imported, active)
    end

    test "allows non-conflicting imports" do
      imported = %{sheet: [entity("hero")], flow: [entity("start")], scene: [entity("map")]}
      active = %{sheet: %{}, flow: %{"other" => 12}, scene: %{}}

      assert :ok = ConflictResolution.preflight(:overwrite, imported, active)
      assert :ok = ConflictResolution.preflight(:skip, imported, active)
      assert :ok = ConflictResolution.preflight(:rename, imported, active)
    end
  end

  describe "preflight_skip_variables/3" do
    test "accepts every variable declared by a skipped sheet when name and type match" do
      data = data_with_variables([{"gold", "number"}, {"display_name", "text"}])
      active_sheets = %{"yarn" => 17}

      active_contracts = %{
        {"yarn", "gold"} => "number",
        {"yarn", "display_name"} => "text"
      }

      assert :ok =
               ConflictResolution.preflight_skip_variables(data, active_sheets, active_contracts)
    end

    test "rejects a missing variable without exposing its name" do
      data = data_with_variables([{"gold", "number"}, {"private_name", "text"}])
      active_sheets = %{"yarn" => 17}
      active_contracts = %{{"yarn", "gold"} => "number"}

      assert {:error, :skip_variable_contract_mismatch} =
               ConflictResolution.preflight_skip_variables(data, active_sheets, active_contracts)
    end

    test "rejects an incompatible variable type" do
      data = data_with_variables([{"gold", "number"}])
      active_sheets = %{"yarn" => 17}
      active_contracts = %{{"yarn", "gold"} => "text"}

      assert {:error, :skip_variable_contract_mismatch} =
               ConflictResolution.preflight_skip_variables(data, active_sheets, active_contracts)
    end

    test "rejects an ambiguous active variable contract" do
      data = data_with_variables([{"gold", "number"}])
      active_sheets = %{"yarn" => 17}
      active_contracts = %{{"yarn", "gold"} => :ambiguous}

      assert {:error, :skip_variable_contract_mismatch} =
               ConflictResolution.preflight_skip_variables(data, active_sheets, active_contracts)
    end

    test "accepts table cells from a linear table, row, and typed-column contract" do
      data = data_with_table_cells()

      active_contracts = %{
        {:table, "yarn", "inventory"} => :present,
        {:table_row, "yarn", "inventory", "sword"} => :present,
        {:table_row, "yarn", "inventory", "shield"} => :present,
        {:table_column, "yarn", "inventory", "damage"} => "number"
      }

      assert :ok =
               ConflictResolution.preflight_skip_variables(
                 data,
                 %{"yarn" => 17},
                 active_contracts
               )
    end

    test "rejects a missing table row contract" do
      data = data_with_table_cells()

      active_contracts = %{
        {:table, "yarn", "inventory"} => :present,
        {:table_row, "yarn", "inventory", "sword"} => :present,
        {:table_column, "yarn", "inventory", "damage"} => "number"
      }

      assert {:error, :skip_variable_contract_mismatch} =
               ConflictResolution.preflight_skip_variables(
                 data,
                 %{"yarn" => 17},
                 active_contracts
               )
    end

    test "rejects a missing table column contract" do
      data =
        data_with_table_cells([%{"slug" => "sword"}], [
          %{"slug" => "damage", "type" => "number", "is_constant" => false},
          %{"slug" => "weight", "type" => "number", "is_constant" => false}
        ])

      active_contracts = %{
        {:table, "yarn", "inventory"} => :present,
        {:table_row, "yarn", "inventory", "sword"} => :present,
        {:table_column, "yarn", "inventory", "damage"} => "number"
      }

      assert {:error, :skip_variable_contract_mismatch} =
               ConflictResolution.preflight_skip_variables(
                 data,
                 %{"yarn" => 17},
                 active_contracts
               )
    end

    test "rejects a differently typed table column" do
      data = data_with_table_cells([%{"slug" => "sword"}])

      active_contracts = %{
        {:table, "yarn", "inventory"} => :present,
        {:table_row, "yarn", "inventory", "sword"} => :present,
        {:table_column, "yarn", "inventory", "damage"} => "text"
      }

      assert {:error, :skip_variable_contract_mismatch} =
               ConflictResolution.preflight_skip_variables(
                 data,
                 %{"yarn" => 17},
                 active_contracts
               )
    end

    test "treats an omitted constant flag like the materializer default" do
      data =
        data_with_table_cells([%{"slug" => "sword"}], [
          %{"slug" => "damage", "type" => "number"}
        ])

      active_contracts = %{
        {:table, "yarn", "inventory"} => :present,
        {:table_row, "yarn", "inventory", "sword"} => :present,
        {:table_column, "yarn", "inventory", "damage"} => "text"
      }

      assert {:error, :skip_variable_contract_mismatch} =
               ConflictResolution.preflight_skip_variables(
                 data,
                 %{"yarn" => 17},
                 active_contracts
               )
    end

    test "uses the same constant-column visibility policy as reference resolution" do
      data =
        data_with_table_cells([%{"slug" => "sword"}], [
          %{"slug" => "hidden", "type" => "number", "is_constant" => true},
          %{"slug" => "computed", "type" => "formula", "is_constant" => true}
        ])

      active_contracts = %{
        {:table, "yarn", "inventory"} => :present,
        {:table_row, "yarn", "inventory", "sword"} => :present,
        {:table_column, "yarn", "inventory", "computed"} => "formula"
      }

      assert :ok =
               ConflictResolution.preflight_skip_variables(
                 data,
                 %{"yarn" => 17},
                 active_contracts
               )
    end

    test "rejects an ambiguous active table identity" do
      data = data_with_table_cells([%{"slug" => "sword"}])

      active_contracts = %{
        {:table, "yarn", "inventory"} => :ambiguous,
        {:table_row, "yarn", "inventory", "sword"} => :present,
        {:table_column, "yarn", "inventory", "damage"} => "number"
      }

      assert {:error, :skip_variable_contract_mismatch} =
               ConflictResolution.preflight_skip_variables(
                 data,
                 %{"yarn" => 17},
                 active_contracts
               )
    end

    test "does not require a table contract when it declares no referenceable cells" do
      no_rows = data_with_table_cells([])

      no_referenceable_columns =
        data_with_table_cells([%{"slug" => "sword"}], [
          %{"slug" => "hidden", "type" => "number", "is_constant" => true}
        ])

      assert :ok =
               ConflictResolution.preflight_skip_variables(no_rows, %{"yarn" => 17}, %{})

      assert :ok =
               ConflictResolution.preflight_skip_variables(
                 no_referenceable_columns,
                 %{"yarn" => 17},
                 %{}
               )
    end

    test "ignores variables on sheets that will be created" do
      data = data_with_variables([{"gold", "number"}])

      assert :ok = ConflictResolution.preflight_skip_variables(data, %{}, %{})
    end

    test "ignores constants and non-variable block types on skipped sheets" do
      data = %{
        "sheets" => [
          %{
            "shortcut" => "yarn",
            "blocks" => [
              %{"variable_name" => "constant_gold", "type" => "number", "is_constant" => true},
              %{"variable_name" => "reference_label", "type" => "reference"}
            ]
          }
        ]
      }

      assert :ok =
               ConflictResolution.preflight_skip_variables(data, %{"yarn" => 17}, %{})
    end
  end

  describe "resolve/4" do
    test "skip maps a conflicting source identity to the active target" do
      used = MapSet.new(["hero"])

      assert {:ok, {:reuse, 73}} =
               ConflictResolution.resolve("hero", :skip, used, %{"hero" => 73})
    end

    test "skip fails closed when the target identity is unavailable" do
      assert {:error, :skip_conflict_target_missing} =
               ConflictResolution.resolve("hero", :skip, MapSet.new(["hero"]), %{})
    end

    test "rename creates a unique shortcut and overwrite fails closed" do
      used = MapSet.new(["hero", "hero-2"])

      assert {:ok, {:create, "hero-3"}} =
               ConflictResolution.resolve("hero", :rename, used, %{"hero" => 73})

      assert {:error, :overwrite_conflict_requires_rename} =
               ConflictResolution.resolve("hero", :overwrite, used, %{"hero" => 73})
    end
  end

  defp entity(shortcut), do: %{"shortcut" => shortcut}

  defp data_with_variables(variables) do
    %{
      "sheets" => [
        %{
          "shortcut" => "yarn",
          "blocks" =>
            Enum.map(variables, fn {variable_name, type} ->
              %{"variable_name" => variable_name, "type" => type}
            end)
        }
      ]
    }
  end

  defp data_with_table_cells(
         rows \\ [%{"slug" => "sword"}, %{"slug" => "shield"}],
         columns \\ [%{"slug" => "damage", "type" => "number", "is_constant" => false}]
       ) do
    %{
      "sheets" => [
        %{
          "shortcut" => "yarn",
          "blocks" => [
            %{
              "type" => "table",
              "variable_name" => "inventory",
              "table_data" => %{"columns" => columns, "rows" => rows}
            }
          ]
        }
      ]
    }
  end
end

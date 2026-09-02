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
end

defmodule Storyarn.Sheets.HealthCheckerTest do
  use ExUnit.Case, async: true

  alias Storyarn.Sheets.HealthChecker

  describe "severity contract" do
    test "treats missing runtime identity as errors and an empty leaf as info" do
      findings =
        check(
          sheet(shortcut: nil),
          [block(1, "number", variable_name: nil)]
        )

      assert error_codes(findings) == MapSet.new([:missing_sheet_shortcut, :missing_variable_name])
      refute :empty_leaf_sheet in info_codes(findings)

      empty_findings = check(sheet(shortcut: "empty"), [], has_children: false)
      assert info_codes(empty_findings) == MapSet.new([:empty_leaf_sheet])

      container_findings = check(sheet(shortcut: "container"), [], has_children: true)
      refute :empty_leaf_sheet in info_codes(container_findings)
    end

    test "reports valid variables with no tracked internal usage as info" do
      variable = block(1, "text", variable_name: "name")

      assert :no_internal_variable_usages in info_codes(check(sheet(), [variable]))

      findings = check(sheet(), [variable], referenced_block_ids: MapSet.new([1]))
      refute :no_internal_variable_usages in info_codes(findings)
    end

    test "reserves warnings for explicit incompleteness or constraint mismatches" do
      required_number =
        block(1, "number",
          required: true,
          value: %{"content" => nil},
          config: %{"label" => "Level", "min" => 10, "max" => 5}
        )

      constrained_text =
        block(2, "text",
          value: %{"content" => "Too long"},
          config: %{"label" => "Code", "max_length" => 3}
        )

      findings = check(sheet(), [required_number, constrained_text])

      assert :invalid_constraints in error_codes(findings)
      assert warning_codes(findings) == MapSet.new([:required_block_empty, :value_outside_constraints])
    end
  end

  describe "selectors and references" do
    test "detects invalid option definitions, stale values, and blank labels" do
      invalid_options =
        block(1, "select",
          config: %{
            "label" => "Class",
            "options" => [
              %{"key" => "mage", "value" => "Mage"},
              %{"key" => "mage", "value" => ""}
            ]
          },
          value: %{"content" => "warrior"}
        )

      empty_options =
        block(2, "multi_select",
          config: %{"label" => "Tags", "options" => []},
          value: %{"content" => []}
        )

      findings = check(sheet(), [invalid_options, empty_options])

      assert :invalid_select_option_keys in error_codes(findings)
      refute :stale_selected_option in error_codes(findings)
      assert warning_codes(findings) == MapSet.new([:blank_option_label, :empty_select_options])

      stale =
        block(3, "select",
          config: %{"label" => "Class", "options" => [%{"key" => "mage", "value" => "Mage"}]},
          value: %{"content" => "warrior"}
        )

      assert :stale_selected_option in error_codes(check(sheet(), [stale]))
    end

    test "detects missing and disallowed reference targets" do
      reference =
        block(1, "reference",
          config: %{"label" => "Owner", "allowed_types" => ["sheet"]},
          value: %{"target_type" => "flow", "target_id" => 99}
        )

      findings = check(sheet(), [reference], reference_targets: %{1 => nil})

      assert error_codes(findings) ==
               MapSet.new([:stale_reference_target, :disallowed_reference_target])
    end

    test "reports stale tracked inline and incoming variable references" do
      rich_text = block(1, "rich_text", variable_name: "bio")

      findings =
        check(sheet(), [rich_text],
          referenced_block_ids: MapSet.new([1]),
          stale_entity_reference_block_ids: MapSet.new([1]),
          stale_variable_reference_counts: %{1 => 2}
        )

      assert error_codes(findings) ==
               MapSet.new([:stale_inline_reference, :stale_incoming_variable_reference])
    end
  end

  describe "tables and formulas" do
    test "detects table structure, required cells, and selector configuration" do
      table_block = block(1, "table", variable_name: "stats")
      column = column(10, "role", "select", required: true, config: %{"options" => []})
      row = row(20, "hero", %{})

      findings =
        check(sheet(), [table_block], table_data: %{1 => %{columns: [column], rows: [row]}})

      assert :invalid_table_structure in error_codes(findings)

      assert warning_codes(findings) ==
               MapSet.new([:required_table_cell_empty, :empty_select_options])
    end

    test "detects invalid formula expressions, unbound symbols, and invalid bindings" do
      table_block = block(1, "table", variable_name: "stats")
      number = column(10, "base", "number")
      formula = column(11, "total", "formula")

      rows = [
        row(20, "invalid", %{
          "base" => 2,
          "total" => %{"expression" => "2 +", "bindings" => %{}}
        }),
        row(21, "unbound", %{
          "base" => 2,
          "total" => %{"expression" => "a + b", "bindings" => %{"a" => same_row("base")}}
        }),
        row(22, "stale", %{
          "base" => 2,
          "total" => %{
            "expression" => "a",
            "bindings" => %{"a" => %{"type" => "variable", "ref" => "missing.value"}}
          }
        })
      ]

      findings =
        check(sheet(), [table_block],
          table_data: %{1 => %{columns: [number, formula], rows: rows}},
          project_variable_types: %{}
        )

      assert error_codes(findings) ==
               MapSet.new([
                 :invalid_formula_expression,
                 :unbound_formula_symbol,
                 :invalid_formula_binding
               ])
    end

    test "detects same-row formula cycles and evaluation failures" do
      table_block = block(1, "table", variable_name: "stats")
      left = column(10, "left", "formula")
      right = column(11, "right", "formula")

      cycle_row =
        row(20, "cycle", %{
          "left" => %{"expression" => "a", "bindings" => %{"a" => same_row("right")}},
          "right" => %{"expression" => "b", "bindings" => %{"b" => same_row("left")}}
        })

      failure_row =
        row(21, "failure", %{
          "left" => %{
            "expression" => "a / b",
            "bindings" => %{"a" => same_row("right"), "b" => same_row("right")},
            "__resolved" => %{"a" => 1, "b" => 0}
          },
          "right" => nil
        })

      findings =
        check(sheet(), [table_block], table_data: %{1 => %{columns: [left, right], rows: [cycle_row, failure_row]}})

      assert :cyclic_formula_dependency in error_codes(findings)
      assert :formula_evaluation_failed in error_codes(findings)
    end
  end

  describe "layout" do
    test "detects invalid column groups" do
      orphan =
        block(1, "text",
          column_group_id: "group-a",
          column_index: 1,
          position: 0
        )

      assert :invalid_block_layout in error_codes(check(sheet(), [orphan]))
    end
  end

  describe "inheritance" do
    test "reports inherited integrity issues as errors at their closest location" do
      inherited = block(1, "text", [])

      findings =
        check(sheet(), [inherited],
          inheritance_issues: [
            %{reason: "stale_definition", block_id: 1, source_block_id: 50},
            %{reason: "missing_instance", block_id: nil, source_block_id: 51}
          ]
        )

      inheritance_findings = Enum.filter(findings, &(&1.code == :broken_inheritance))

      assert Enum.map(inheritance_findings, & &1.block_id) == [1, nil]
      assert Enum.all?(inheritance_findings, &(&1.severity == :error))
      assert Enum.map(inheritance_findings, & &1.details.reason) == ["stale_definition", "missing_instance"]
    end
  end

  defp check(sheet, blocks, overrides \\ []) do
    defaults = [
      has_children: false,
      referenced_block_ids: MapSet.new(),
      stale_variable_reference_counts: %{},
      stale_entity_reference_block_ids: MapSet.new(),
      reference_targets: %{},
      project_variable_types: %{},
      inheritance_issues: [],
      table_data: %{},
      gallery_data: %{}
    ]

    defaults
    |> Keyword.merge(overrides)
    |> Map.new()
    |> Map.merge(%{sheet: sheet, blocks: blocks})
    |> HealthChecker.check()
  end

  defp sheet(overrides \\ []) do
    defaults = %{id: 100, name: "Hero", shortcut: "hero"}
    struct_from_options(defaults, overrides)
  end

  defp block(id, type, overrides) do
    defaults = %{
      id: id,
      type: type,
      config: %{"label" => String.capitalize(type)},
      value: default_value(type),
      is_constant: type in ["reference", "gallery"],
      variable_name: if(type in ["reference", "gallery"], do: nil, else: type),
      required: false,
      column_group_id: nil,
      column_index: 0,
      position: id
    }

    struct_from_options(defaults, overrides)
  end

  defp column(id, slug, type, overrides \\ []) do
    defaults = %{
      id: id,
      name: String.capitalize(slug),
      slug: slug,
      type: type,
      required: false,
      config: %{}
    }

    struct_from_options(defaults, overrides)
  end

  defp row(id, slug, cells) do
    %{id: id, name: String.capitalize(slug), slug: slug, cells: cells}
  end

  defp same_row(slug), do: %{"type" => "same_row", "column_slug" => slug}

  defp default_value("reference"), do: %{"target_type" => nil, "target_id" => nil}
  defp default_value("multi_select"), do: %{"content" => []}
  defp default_value("table"), do: %{}
  defp default_value("gallery"), do: %{}
  defp default_value(_type), do: %{"content" => nil}

  defp struct_from_options(defaults, overrides), do: Map.merge(defaults, Map.new(overrides))

  defp error_codes(findings), do: severity_codes(findings, :error)
  defp warning_codes(findings), do: severity_codes(findings, :warning)
  defp info_codes(findings), do: severity_codes(findings, :info)

  defp severity_codes(findings, severity) do
    findings
    |> Enum.filter(&(&1.severity == severity))
    |> MapSet.new(& &1.code)
  end
end

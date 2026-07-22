defmodule Storyarn.Sheets.HealthChecker do
  @moduledoc """
  Produces structured authoring findings for a sheet snapshot.

  Errors identify state that cannot be interpreted reliably, warnings identify
  valid but incomplete or contradictory authoring, and info findings describe
  valid noteworthy states. The checker is intentionally pure: callers enrich
  the snapshot with reference and project-variable information before checking.
  """

  alias Storyarn.Shared.FormulaEngine
  alias Storyarn.Shared.HtmlUtils
  alias Storyarn.Sheets.Block

  @type severity :: :error | :warning | :info
  @type finding :: %{
          required(:severity) => severity(),
          required(:code) => atom(),
          required(:sheet_id) => integer() | nil,
          required(:block_id) => integer() | nil,
          required(:block_type) => String.t() | nil,
          required(:row_id) => integer() | nil,
          required(:column_id) => integer() | nil,
          required(:details) => map()
        }

  @numeric_types ~w(number formula)
  @select_types ~w(select multi_select)

  @severity_by_code %{
    broken_inheritance: :error,
    cyclic_formula_dependency: :error,
    disallowed_reference_target: :error,
    formula_evaluation_failed: :error,
    invalid_block_layout: :error,
    invalid_block_value: :error,
    invalid_constraints: :error,
    invalid_formula_binding: :error,
    invalid_formula_expression: :error,
    invalid_select_option_keys: :error,
    invalid_table_structure: :error,
    missing_sheet_shortcut: :error,
    missing_variable_name: :error,
    stale_incoming_variable_reference: :error,
    stale_inline_reference: :error,
    stale_reference_target: :error,
    stale_selected_option: :error,
    unbound_formula_symbol: :error,
    blank_option_label: :warning,
    empty_select_options: :warning,
    required_block_empty: :warning,
    required_table_cell_empty: :warning,
    unnamed_table_axis: :warning,
    value_outside_constraints: :warning,
    empty_leaf_sheet: :info,
    no_internal_variable_usages: :info
  }

  @doc "Returns the canonical severity for a sheet health finding code."
  @spec severity_for(atom()) :: severity()
  def severity_for(code), do: Map.fetch!(@severity_by_code, code)

  @doc "Builds a canonical finding for adapters that detect health in bulk."
  @spec finding(atom(), map()) :: finding()
  def finding(code, attrs \\ %{}) when is_atom(code) and is_map(attrs) do
    %{
      severity: severity_for(code),
      code: code,
      sheet_id: Map.get(attrs, :sheet_id),
      block_id: Map.get(attrs, :block_id),
      block_type: Map.get(attrs, :block_type),
      row_id: Map.get(attrs, :row_id),
      column_id: Map.get(attrs, :column_id),
      details: Map.get(attrs, :details, %{})
    }
  end

  @spec check(map()) :: [finding()]
  def check(%{sheet: sheet} = snapshot) when is_map(sheet) do
    blocks = Map.get(snapshot, :blocks, [])

    sheet_findings(sheet, blocks, snapshot) ++
      inheritance_findings(sheet, blocks, snapshot) ++
      layout_findings(sheet, blocks) ++
      Enum.flat_map(blocks, &block_findings(sheet, &1, snapshot))
  end

  def check(_snapshot), do: []

  defp inheritance_findings(sheet, blocks, snapshot) do
    blocks_by_id = Map.new(blocks, &{field(&1, :id), &1})

    snapshot
    |> Map.get(:inheritance_issues, [])
    |> Enum.map(fn issue ->
      block = Map.get(blocks_by_id, field(issue, :block_id))
      details = Map.drop(issue, [:block_id, "block_id"])

      if is_nil(block) do
        sheet_finding(sheet, :broken_inheritance, details)
      else
        block_finding(sheet, block, :broken_inheritance, details)
      end
    end)
  end

  defp sheet_findings(sheet, blocks, snapshot) do
    []
    |> maybe_add(blank?(field(sheet, :shortcut)), sheet_finding(sheet, :missing_sheet_shortcut))
    |> maybe_add(
      blocks == [] and Map.get(snapshot, :has_children, false) == false,
      sheet_finding(sheet, :empty_leaf_sheet)
    )
  end

  defp block_findings(sheet, block, snapshot) do
    block_identity_findings(sheet, block, snapshot) ++
      block_value_findings(sheet, block, snapshot) ++
      block_constraint_findings(sheet, block) ++
      block_reference_findings(sheet, block, snapshot) ++
      table_findings(sheet, block, snapshot)
  end

  defp block_identity_findings(sheet, block, snapshot) do
    variable? = Block.can_be_variable?(field(block, :type)) and field(block, :is_constant, false) == false
    referenced_ids = Map.get(snapshot, :referenced_block_ids, MapSet.new())
    stale_counts = Map.get(snapshot, :stale_variable_reference_counts, %{})

    []
    |> maybe_add(
      variable? and blank?(field(block, :variable_name)),
      block_finding(sheet, block, :missing_variable_name)
    )
    |> maybe_add(
      variable? and not blank?(field(block, :variable_name)) and
        not MapSet.member?(referenced_ids, field(block, :id)),
      block_finding(sheet, block, :no_internal_variable_usages)
    )
    |> maybe_add(
      Map.get(stale_counts, field(block, :id), 0) > 0,
      block_finding(sheet, block, :stale_incoming_variable_reference, %{
        count: Map.get(stale_counts, field(block, :id), 0)
      })
    )
  end

  defp block_value_findings(sheet, block, snapshot) do
    type = field(block, :type)
    value = field(block, :value, %{})
    invalid_value? = invalid_block_value?(type, value)

    []
    |> maybe_add(
      invalid_value?,
      block_finding(sheet, block, :invalid_block_value, %{expected: expected_value(type)})
    )
    |> maybe_add(
      not invalid_value? and field(block, :required, false) and type != "table" and
        required_block_empty?(block, snapshot),
      block_finding(sheet, block, :required_block_empty)
    )
    |> Kernel.++(select_findings(sheet, block, nil, nil, type, field(block, :config, %{}), content(value)))
  end

  defp block_constraint_findings(sheet, block) do
    constraint_findings(
      sheet,
      block,
      nil,
      nil,
      field(block, :type),
      field(block, :config, %{}),
      content(field(block, :value, %{}))
    )
  end

  defp block_reference_findings(sheet, block, snapshot) do
    type = field(block, :type)
    block_id = field(block, :id)
    stale_entity_ids = Map.get(snapshot, :stale_entity_reference_block_ids, MapSet.new())

    cond do
      type == "reference" ->
        reference_block_findings(sheet, block, snapshot, stale_entity_ids)

      type == "rich_text" and MapSet.member?(stale_entity_ids, block_id) ->
        [block_finding(sheet, block, :stale_inline_reference)]

      true ->
        []
    end
  end

  defp reference_block_findings(sheet, block, snapshot, stale_entity_ids) do
    value = field(block, :value, %{})
    target_type = field(value, :target_type)
    target_id = field(value, :target_id)
    complete? = target_type in ["sheet", "flow"] and not blank?(target_id)
    targets = Map.get(snapshot, :reference_targets, %{})
    stale? = complete? and is_nil(Map.get(targets, field(block, :id)))
    allowed_types = field(field(block, :config, %{}), :allowed_types, ["sheet", "flow"])

    []
    |> maybe_add(
      stale? or MapSet.member?(stale_entity_ids, field(block, :id)),
      block_finding(sheet, block, :stale_reference_target)
    )
    |> maybe_add(
      complete? and is_list(allowed_types) and target_type not in allowed_types,
      block_finding(sheet, block, :disallowed_reference_target, %{target_type: target_type})
    )
  end

  defp table_findings(_sheet, block, _snapshot) when not is_map(block), do: []

  defp table_findings(sheet, block, snapshot) do
    if field(block, :type) == "table" do
      table = snapshot |> Map.get(:table_data, %{}) |> Map.get(field(block, :id), %{columns: [], rows: []})
      columns = field(table, :columns, [])
      rows = field(table, :rows, [])

      table_structure_findings(sheet, block, columns, rows) ++
        table_column_findings(sheet, block, columns, rows, snapshot) ++
        table_formula_cycle_findings(sheet, block, columns, rows)
    else
      []
    end
  end

  defp table_structure_findings(sheet, block, columns, rows) do
    column_slugs = Enum.map(columns, &field(&1, :slug))
    expected_keys = MapSet.new(column_slugs)

    []
    |> maybe_add(
      columns == [],
      block_finding(sheet, block, :invalid_table_structure, %{reason: "missing_columns"})
    )
    |> maybe_add(
      rows == [],
      block_finding(sheet, block, :invalid_table_structure, %{reason: "missing_rows"})
    )
    |> maybe_add(
      Enum.any?(column_slugs, &blank?/1) or duplicate_values?(column_slugs),
      block_finding(sheet, block, :invalid_table_structure, %{reason: "invalid_column_slugs"})
    )
    |> Kernel.++(row_structure_findings(sheet, block, rows, expected_keys))
  end

  defp row_structure_findings(sheet, block, rows, expected_keys) do
    row_slugs = Enum.map(rows, &field(&1, :slug))

    base =
      if Enum.any?(row_slugs, &blank?/1) or duplicate_values?(row_slugs) do
        [block_finding(sheet, block, :invalid_table_structure, %{reason: "invalid_row_slugs"})]
      else
        []
      end

    base ++
      Enum.flat_map(rows, fn row ->
        actual_keys =
          row |> field(:cells, %{}) |> Map.keys() |> Enum.reject(&String.starts_with?(&1, "__")) |> MapSet.new()

        if actual_keys == expected_keys do
          []
        else
          [
            located_finding(sheet, block, row, nil, :invalid_table_structure, %{
              reason: "cell_schema_mismatch"
            })
          ]
        end
      end)
  end

  defp table_column_findings(sheet, block, columns, rows, snapshot) do
    Enum.flat_map(columns, fn column ->
      axis_findings =
        if blank?(field(column, :name)) do
          [located_finding(sheet, block, nil, column, :unnamed_table_axis, %{axis: "column"})]
        else
          []
        end

      cell_findings =
        Enum.flat_map(rows, &table_cell_findings(sheet, block, &1, column, columns, snapshot))

      axis_findings ++ cell_findings
    end) ++ table_row_name_findings(sheet, block, rows)
  end

  defp table_row_name_findings(sheet, block, rows) do
    Enum.flat_map(rows, fn row ->
      if blank?(field(row, :name)) do
        [located_finding(sheet, block, row, nil, :unnamed_table_axis, %{axis: "row"})]
      else
        []
      end
    end)
  end

  defp table_cell_findings(sheet, block, row, column, columns, snapshot) do
    type = field(column, :type)
    value = row |> field(:cells, %{}) |> Map.get(field(column, :slug))
    location = {row, column}

    []
    |> maybe_add(
      invalid_cell_value?(type, value),
      located_finding(sheet, block, row, column, :invalid_block_value, %{expected: expected_value(type)})
    )
    |> maybe_add(
      field(column, :required, false) and empty_cell?(value),
      located_finding(sheet, block, row, column, :required_table_cell_empty)
    )
    |> Kernel.++(
      select_findings(
        sheet,
        block,
        elem(location, 0),
        elem(location, 1),
        type,
        field(column, :config, %{}),
        value
      )
    )
    |> Kernel.++(
      constraint_findings(
        sheet,
        block,
        elem(location, 0),
        elem(location, 1),
        type,
        field(column, :config, %{}),
        value
      )
    )
    |> Kernel.++(formula_findings(sheet, block, row, column, columns, snapshot))
  end

  defp formula_findings(_sheet, _block, _row, column, _columns, _snapshot) when not is_map(column), do: []

  defp formula_findings(sheet, block, row, column, columns, snapshot) do
    if field(column, :type) == "formula" do
      value = row |> field(:cells, %{}) |> Map.get(field(column, :slug))
      do_formula_findings(sheet, block, row, column, columns, value, snapshot)
    else
      []
    end
  end

  defp do_formula_findings(_sheet, _block, _row, _column, _columns, nil, _snapshot), do: []

  defp do_formula_findings(sheet, block, row, column, columns, value, snapshot) when is_map(value) do
    expression = field(value, :expression)

    if blank?(expression) do
      []
    else
      case FormulaEngine.parse(expression) do
        {:error, reason} ->
          [located_finding(sheet, block, row, column, :invalid_formula_expression, %{reason: reason})]

        {:ok, ast} ->
          parsed_formula_findings(sheet, block, row, column, columns, value, ast, snapshot)
      end
    end
  end

  defp do_formula_findings(sheet, block, row, column, _columns, _value, _snapshot) do
    [located_finding(sheet, block, row, column, :invalid_formula_expression)]
  end

  defp parsed_formula_findings(sheet, block, row, column, columns, value, ast, snapshot) do
    symbols = FormulaEngine.extract_symbols(ast)
    bindings = field(value, :bindings, %{})
    bound_symbols = if is_map(bindings), do: Map.keys(bindings), else: []
    missing_symbols = symbols -- bound_symbols
    extra_symbols = bound_symbols -- symbols

    unbound =
      if missing_symbols == [] do
        []
      else
        [
          located_finding(sheet, block, row, column, :unbound_formula_symbol, %{
            symbols: missing_symbols
          })
        ]
      end

    binding_errors =
      if is_map(bindings) do
        invalid_formula_bindings(sheet, block, row, column, columns, bindings, extra_symbols, snapshot)
      else
        [located_finding(sheet, block, row, column, :invalid_formula_binding)]
      end

    evaluation =
      if unbound == [] and binding_errors == [] do
        formula_evaluation_findings(sheet, block, row, column, value, ast)
      else
        []
      end

    unbound ++ binding_errors ++ evaluation
  end

  defp invalid_formula_bindings(sheet, block, row, column, columns, bindings, extra_symbols, snapshot) do
    column_types = Map.new(columns, &{field(&1, :slug), field(&1, :type)})
    variable_types = Map.get(snapshot, :project_variable_types, %{})

    invalid =
      Enum.flat_map(bindings, fn {symbol, binding} ->
        if valid_formula_binding?(binding, column, column_types, variable_types) and symbol not in extra_symbols,
          do: [],
          else: [symbol]
      end)

    if invalid == [] do
      []
    else
      [
        located_finding(sheet, block, row, column, :invalid_formula_binding, %{
          symbols: Enum.sort(invalid)
        })
      ]
    end
  end

  defp valid_formula_binding?(binding, column, column_types, variable_types) when is_map(binding) do
    case field(binding, :type) do
      "same_row" ->
        slug = field(binding, :column_slug)
        not blank?(slug) and slug != field(column, :slug) and Map.get(column_types, slug) in @numeric_types

      "variable" ->
        ref = field(binding, :ref)
        not blank?(ref) and Map.get(variable_types, ref) in @numeric_types

      _ ->
        false
    end
  end

  defp valid_formula_binding?(_binding, _column, _column_types, _variable_types), do: false

  defp formula_evaluation_findings(sheet, block, row, column, value, ast) do
    resolved = field(value, :__resolved)

    if is_map(resolved) do
      case FormulaEngine.evaluate(ast, resolved) do
        {:ok, _result} ->
          []

        {:error, reason} ->
          [
            located_finding(sheet, block, row, column, :formula_evaluation_failed, %{
              reason: reason
            })
          ]
      end
    else
      []
    end
  end

  defp table_formula_cycle_findings(sheet, block, columns, rows) do
    formula_columns = Enum.filter(columns, &(field(&1, :type) == "formula"))
    formula_slugs = MapSet.new(formula_columns, &field(&1, :slug))
    columns_by_slug = Map.new(formula_columns, &{field(&1, :slug), &1})

    Enum.flat_map(rows, fn row ->
      graph = formula_dependency_graph(row, formula_slugs)

      graph
      |> cyclic_graph_nodes()
      |> Enum.map(fn slug ->
        located_finding(sheet, block, row, Map.get(columns_by_slug, slug), :cyclic_formula_dependency)
      end)
    end)
  end

  defp formula_dependency_graph(row, formula_slugs) do
    cells = field(row, :cells, %{})

    Map.new(formula_slugs, fn slug ->
      bindings = cells |> Map.get(slug, %{}) |> field(:bindings, %{})

      dependencies =
        if is_map(bindings) do
          bindings
          |> Map.values()
          |> Enum.filter(&(field(&1, :type) == "same_row"))
          |> Enum.map(&field(&1, :column_slug))
          |> Enum.filter(&MapSet.member?(formula_slugs, &1))
        else
          []
        end

      {slug, dependencies}
    end)
  end

  defp cyclic_graph_nodes(graph) do
    graph
    |> Map.keys()
    |> Enum.filter(&reaches_node?(graph, &1, &1, MapSet.new()))
  end

  defp reaches_node?(graph, current, target, visited) do
    Enum.any?(Map.get(graph, current, []), fn dependency ->
      dependency == target or
        (not MapSet.member?(visited, dependency) and
           reaches_node?(graph, dependency, target, MapSet.put(visited, dependency)))
    end)
  end

  defp select_findings(_sheet, _block, _row, _column, type, _config, _value) when type not in @select_types, do: []

  defp select_findings(sheet, block, row, column, _type, config, value) do
    options = field(config, :options, [])

    if is_list(options) do
      option_keys = Enum.map(options, &field(&1, :key))
      valid_keys? = Enum.all?(option_keys, &(is_binary(&1) and not blank?(&1))) and not duplicate_values?(option_keys)

      []
      |> maybe_add(
        not valid_keys?,
        located_finding(sheet, block, row, column, :invalid_select_option_keys)
      )
      |> maybe_add(
        valid_keys? and stale_selection?(value, option_keys),
        located_finding(sheet, block, row, column, :stale_selected_option)
      )
      |> maybe_add(
        options == [],
        located_finding(sheet, block, row, column, :empty_select_options)
      )
      |> maybe_add(
        Enum.any?(options, &blank?(field(&1, :value))),
        located_finding(sheet, block, row, column, :blank_option_label)
      )
    else
      [located_finding(sheet, block, row, column, :invalid_select_option_keys)]
    end
  end

  defp constraint_findings(sheet, block, row, column, type, config, value) do
    invalid? = invalid_constraints?(type, config)

    []
    |> maybe_add(
      invalid?,
      located_finding(sheet, block, row, column, :invalid_constraints)
    )
    |> maybe_add(
      not invalid? and value_outside_constraints?(type, value, config),
      located_finding(sheet, block, row, column, :value_outside_constraints)
    )
  end

  defp invalid_constraints?("number", config) do
    min = parsed_number(field(config, :min))
    max = parsed_number(field(config, :max))
    step = parsed_number(field(config, :step))

    invalid_number?(min) or invalid_number?(max) or invalid_number?(step) or
      positive_constraint_invalid?(step) or inverted_range?(min, max)
  end

  defp invalid_constraints?(type, config) when type in ["text", "rich_text"] do
    invalid_non_negative_constraint?(parsed_number(field(config, :max_length)))
  end

  defp invalid_constraints?("multi_select", config) do
    invalid_positive_constraint?(parsed_number(field(config, :max_options)))
  end

  defp invalid_constraints?("date", config) do
    min = parsed_date(field(config, :min_date))
    max = parsed_date(field(config, :max_date))
    invalid_date?(min) or invalid_date?(max) or inverted_date_range?(min, max)
  end

  defp invalid_constraints?("boolean", config) do
    field(config, :mode) not in [nil, "two_state", "tri_state"]
  end

  defp invalid_constraints?(_type, _config), do: false

  defp value_outside_constraints?("number", value, config) when is_number(value) do
    outside_numeric_range?(value, parsed_number(field(config, :min)), parsed_number(field(config, :max)))
  end

  defp value_outside_constraints?(type, value, config) when type in ["text", "rich_text"] and is_binary(value) do
    case parsed_number(field(config, :max_length)) do
      {:ok, max} when is_number(max) and max >= 0 -> String.length(visible_text(type, value)) > trunc(max)
      _ -> false
    end
  end

  defp value_outside_constraints?("multi_select", value, config) when is_list(value) do
    case parsed_number(field(config, :max_options)) do
      {:ok, max} when is_number(max) and max > 0 -> length(value) > trunc(max)
      _ -> false
    end
  end

  defp value_outside_constraints?("date", value, config) when is_binary(value) and value != "" do
    outside_date_range?(value, parsed_date(field(config, :min_date)), parsed_date(field(config, :max_date)))
  end

  defp value_outside_constraints?(_type, _value, _config), do: false

  defp layout_findings(sheet, blocks) do
    blocks
    |> Enum.reject(&is_nil(field(&1, :column_group_id)))
    |> Enum.group_by(&field(&1, :column_group_id))
    |> Enum.flat_map(fn {group_id, group_blocks} ->
      indices = group_blocks |> Enum.map(&field(&1, :column_index, 0)) |> Enum.sort()
      positions = group_blocks |> Enum.map(&field(&1, :position, 0)) |> Enum.sort()
      expected_indices = Enum.to_list(0..(length(group_blocks) - 1))
      expected_positions = Enum.to_list(hd(positions)..List.last(positions))

      if length(group_blocks) in 2..3 and indices == expected_indices and positions == expected_positions do
        []
      else
        [
          block_finding(sheet, hd(group_blocks), :invalid_block_layout, %{
            group_id: group_id
          })
        ]
      end
    end)
  end

  defp invalid_block_value?(_type, value) when not is_map(value), do: true
  defp invalid_block_value?(type, value), do: invalid_cell_value?(type, content_or_reference(type, value))

  defp invalid_cell_value?(type, value) when type in ["text", "rich_text"], do: not (is_nil(value) or is_binary(value))
  defp invalid_cell_value?("number", value), do: not (is_nil(value) or is_number(value))
  defp invalid_cell_value?("select", value), do: not (is_nil(value) or is_binary(value))

  defp invalid_cell_value?("multi_select", value) do
    not (is_nil(value) or
           (is_list(value) and Enum.all?(value, &is_binary/1) and length(value) == length(Enum.uniq(value))))
  end

  defp invalid_cell_value?("boolean", value), do: not (is_nil(value) or is_boolean(value))

  defp invalid_cell_value?("date", value) do
    not (is_nil(value) or value == "" or valid_iso_date?(value))
  end

  defp invalid_cell_value?("reference", value) when is_map(value) do
    target_type = field(value, :target_type)
    target_id = field(value, :target_id)
    not ((blank?(target_type) and blank?(target_id)) or (target_type in ["sheet", "flow"] and not blank?(target_id)))
  end

  defp invalid_cell_value?("reference", value), do: not (is_nil(value) or is_binary(value) or is_list(value))
  defp invalid_cell_value?("formula", value), do: not (is_nil(value) or is_map(value))
  defp invalid_cell_value?(type, value) when type in ["table", "gallery"], do: not is_map(value)
  defp invalid_cell_value?(_type, _value), do: false

  defp required_block_empty?(block, snapshot) do
    type = field(block, :type)
    value = field(block, :value, %{})

    case type do
      "text" -> blank?(content(value))
      "rich_text" -> value |> content() |> HtmlUtils.strip_html() |> String.trim() == ""
      "multi_select" -> content(value) in [nil, []]
      "reference" -> blank?(field(value, :target_type)) or blank?(field(value, :target_id))
      "gallery" -> snapshot |> Map.get(:gallery_data, %{}) |> Map.get(field(block, :id), []) |> Enum.empty?()
      _ -> content(value) in [nil, ""]
    end
  end

  defp content_or_reference(type, value) when type in ["reference", "table", "gallery"], do: value
  defp content_or_reference(_type, value), do: content(value)

  defp content(value) when is_map(value), do: field(value, :content)
  defp content(_value), do: nil

  defp stale_selection?(nil, _keys), do: false
  defp stale_selection?("", _keys), do: false
  defp stale_selection?(value, keys) when is_binary(value), do: value not in keys
  defp stale_selection?(values, keys) when is_list(values), do: Enum.any?(values, &(&1 not in keys))
  defp stale_selection?(_value, _keys), do: false

  defp empty_cell?(value) when is_binary(value), do: String.trim(value) == ""
  defp empty_cell?(value), do: value in [nil, []]

  defp duplicate_values?(values), do: length(values) != length(Enum.uniq(values))

  defp parsed_number(value) when value in [nil, ""], do: {:ok, nil}
  defp parsed_number(value) when is_number(value), do: {:ok, value}

  defp parsed_number(value) when is_binary(value) do
    case Float.parse(value) do
      {number, ""} -> {:ok, number}
      _ -> :error
    end
  end

  defp parsed_number(_value), do: :error

  defp parsed_date(value) when value in [nil, ""], do: {:ok, nil}

  defp parsed_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, date}
      {:error, _reason} -> :error
    end
  end

  defp parsed_date(_value), do: :error

  defp invalid_number?(:error), do: true
  defp invalid_number?(_value), do: false

  defp invalid_date?(:error), do: true
  defp invalid_date?(_value), do: false

  defp positive_constraint_invalid?({:ok, nil}), do: false
  defp positive_constraint_invalid?({:ok, value}), do: value <= 0
  defp positive_constraint_invalid?(:error), do: false

  defp invalid_positive_constraint?({:ok, nil}), do: false
  defp invalid_positive_constraint?({:ok, value}), do: value < 1
  defp invalid_positive_constraint?(:error), do: true

  defp invalid_non_negative_constraint?({:ok, nil}), do: false
  defp invalid_non_negative_constraint?({:ok, value}), do: value < 0
  defp invalid_non_negative_constraint?(:error), do: true

  defp inverted_range?({:ok, min}, {:ok, max}) when is_number(min) and is_number(max), do: min > max
  defp inverted_range?(_min, _max), do: false

  defp inverted_date_range?({:ok, %Date{} = min}, {:ok, %Date{} = max}), do: Date.after?(min, max)
  defp inverted_date_range?(_min, _max), do: false

  defp outside_numeric_range?(value, {:ok, min}, {:ok, max}) do
    (is_number(min) and value < min) or (is_number(max) and value > max)
  end

  defp outside_numeric_range?(_value, _min, _max), do: false

  defp outside_date_range?(value, {:ok, min}, {:ok, max}) do
    case Date.from_iso8601(value) do
      {:ok, date} ->
        (match?(%Date{}, min) and Date.before?(date, min)) or
          (match?(%Date{}, max) and Date.after?(date, max))

      {:error, _reason} ->
        false
    end
  end

  defp outside_date_range?(_value, _min, _max), do: false

  defp valid_iso_date?(value) when is_binary(value), do: match?({:ok, _date}, Date.from_iso8601(value))
  defp valid_iso_date?(_value), do: false

  defp visible_text("rich_text", value), do: HtmlUtils.strip_html(value)
  defp visible_text(_type, value), do: value

  defp expected_value("number"), do: "number"
  defp expected_value("boolean"), do: "boolean"
  defp expected_value("multi_select"), do: "list_of_option_keys"
  defp expected_value("date"), do: "iso_date"
  defp expected_value("reference"), do: "reference_target"
  defp expected_value("formula"), do: "formula"
  defp expected_value(type) when type in ["table", "gallery"], do: "map"
  defp expected_value(_type), do: "string"

  defp sheet_finding(sheet, code, details \\ %{}) do
    finding(code, %{sheet_id: field(sheet, :id), details: details})
  end

  defp block_finding(sheet, block, code, details \\ %{}) do
    located_finding(sheet, block, nil, nil, code, details)
  end

  defp located_finding(sheet, block, row, column, code, details \\ %{}) do
    finding(code, %{
      sheet_id: field(sheet, :id),
      block_id: field(block, :id),
      block_type: field(block, :type),
      row_id: field(row, :id),
      column_id: field(column, :id),
      details: details
    })
  end

  defp maybe_add(findings, true, finding), do: findings ++ [finding]
  defp maybe_add(findings, false, _finding), do: findings

  defp field(data, key, default \\ nil)
  defp field(nil, _key, default), do: default

  defp field(map, key, default) when is_map(map) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end

  defp field(_other, _key, default), do: default

  defp blank?(value), do: is_nil(value) or (is_binary(value) and String.trim(value) == "")
end

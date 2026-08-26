defmodule Storyarn.Sheets.Logic.Queries.VariableValues do
  @moduledoc """
  Logic-owned query service for variable metadata and current authored values.

  The queries read small, local projections of the shared tables. This keeps
  formula evaluation independent from editor entities and their write model.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Platform.Shared.MapUtils
  alias Storyarn.Repo
  alias Storyarn.Sheets.FormulaEngine
  alias Storyarn.Sheets.Logic.Data.BlockRecord, as: Block
  alias Storyarn.Sheets.Logic.Data.SheetRecord, as: Sheet
  alias Storyarn.Sheets.Logic.Data.TableColumnRecord, as: TableColumn
  alias Storyarn.Sheets.Logic.Data.TableRowRecord, as: TableRow
  alias Storyarn.Sheets.Logic.Queries.VariableNamespaces
  alias Storyarn.Sheets.Logic.Rules.Constraints.Boolean, as: BooleanConstraints
  alias Storyarn.Sheets.Logic.Rules.Constraints.Date, as: DateConstraints
  alias Storyarn.Sheets.Logic.Rules.Constraints.Number, as: NumberConstraints
  alias Storyarn.Sheets.Logic.Rules.Constraints.Selector, as: SelectorConstraints
  alias Storyarn.Sheets.Logic.Rules.Constraints.String, as: StringConstraints

  require VariableNamespaces

  @doc "Lists all regular and table variables authored in a project."
  @spec list_project_variables(integer()) :: [map()]
  def list_project_variables(project_id) do
    list_block_variables(project_id) ++ list_table_variables(project_id)
  end

  defp list_block_variables(project_id) do
    variable_types = ~w(text rich_text number select multi_select boolean date)

    from(block in Block,
      join: sheet in Sheet,
      on: block.sheet_id == sheet.id,
      where:
        sheet.project_id == ^project_id and
          is_nil(sheet.deleted_at) and
          is_nil(block.deleted_at) and
          block.type in ^variable_types and
          block.is_constant == false and
          not is_nil(block.variable_name) and
          block.variable_name != "" and
          VariableNamespaces.authoritative_namespace_owner?(sheet),
      select: %{
        sheet_id: sheet.id,
        sheet_name: sheet.name,
        sheet_shortcut: coalesce(sheet.shortcut, fragment("CAST(? AS TEXT)", sheet.id)),
        block_id: block.id,
        variable_name: block.variable_name,
        block_type: block.type,
        config: block.config,
        value: block.value
      },
      order_by: [asc: sheet.name, asc: block.position]
    )
    |> Repo.all()
    |> Enum.map(&extract_variable_constraints/1)
    |> Enum.map(&extract_variable_options/1)
    |> Enum.map(&Map.merge(&1, %{table_name: nil, row_name: nil, column_name: nil}))
  end

  defp list_table_variables(project_id) do
    variable_column_types = ~w(number text boolean select multi_select date reference formula)

    raw_variables =
      Repo.all(
        from(column in TableColumn,
          join: block in Block,
          on: column.block_id == block.id,
          join: sheet in Sheet,
          on: block.sheet_id == sheet.id,
          join: row in TableRow,
          on: row.block_id == block.id,
          where: sheet.project_id == ^project_id,
          where: is_nil(sheet.deleted_at) and is_nil(block.deleted_at),
          where: block.type == "table",
          where: column.type in ^variable_column_types,
          where: column.is_constant == false or column.type == "formula",
          where: VariableNamespaces.authoritative_namespace_owner?(sheet),
          select: %{
            sheet_id: sheet.id,
            sheet_name: sheet.name,
            sheet_shortcut: coalesce(sheet.shortcut, fragment("CAST(? AS TEXT)", sheet.id)),
            block_id: block.id,
            variable_name: fragment("? || '.' || ? || '.' || ?", block.variable_name, row.slug, column.slug),
            block_type: column.type,
            config: column.config,
            cell_value: fragment("?->?", row.cells, column.slug),
            table_name: block.variable_name,
            row_name: row.slug,
            column_name: column.slug
          },
          order_by: [asc: sheet.name, asc: block.position, asc: row.position, asc: column.position]
        )
      )

    sheet_options =
      if Enum.any?(raw_variables, &(&1.block_type == "reference")) do
        list_sheet_options(project_id)
      else
        []
      end

    raw_variables
    |> Enum.map(&remap_reference_type(&1, sheet_options))
    |> Enum.map(&extract_variable_constraints/1)
    |> Enum.map(&extract_variable_options/1)
  end

  defp remap_reference_type(%{block_type: "reference", config: config} = variable, sheet_options) do
    effective_type = if config["multiple"], do: "multi_select", else: "select"
    updated_config = Map.put(config || %{}, "options", sheet_options)
    %{variable | block_type: effective_type, config: updated_config}
  end

  defp remap_reference_type(variable, _sheet_options), do: variable

  defp extract_variable_constraints(%{block_type: "number", config: config} = variable) when is_map(config),
    do: Map.put(variable, :constraints, NumberConstraints.extract(config))

  defp extract_variable_constraints(%{block_type: type, config: config} = variable)
       when type in ["text", "rich_text"] and is_map(config),
       do: Map.put(variable, :constraints, StringConstraints.extract(config))

  defp extract_variable_constraints(%{block_type: type, config: config} = variable)
       when type in ["select", "multi_select"] and is_map(config),
       do: Map.put(variable, :constraints, SelectorConstraints.extract(config))

  defp extract_variable_constraints(%{block_type: "date", config: config} = variable) when is_map(config),
    do: Map.put(variable, :constraints, DateConstraints.extract(config))

  defp extract_variable_constraints(%{block_type: "boolean", config: config} = variable) when is_map(config),
    do: Map.put(variable, :constraints, BooleanConstraints.extract(config))

  defp extract_variable_constraints(variable), do: Map.put(variable, :constraints, nil)

  defp extract_variable_options(variable) do
    variable
    |> Map.put(:options, extract_options_from_config(variable.block_type, variable.config))
    |> Map.delete(:config)
  end

  defp extract_options_from_config(type, config) when type in ["select", "multi_select"], do: config["options"] || []

  defp extract_options_from_config(_type, _config), do: nil

  @doc "Returns active project Sheets as options for reference columns."
  @spec list_reference_options(integer()) :: [map()]
  def list_reference_options(project_id), do: list_sheet_options(project_id)

  defp list_sheet_options(project_id) do
    from(sheet in Sheet,
      where: sheet.project_id == ^project_id,
      where: is_nil(sheet.deleted_at),
      where: not is_nil(sheet.shortcut) and sheet.shortcut != "",
      order_by: [asc: sheet.name],
      select: %{name: sheet.name, shortcut: sheet.shortcut}
    )
    |> Repo.all()
    |> Enum.map(fn sheet -> %{"key" => sheet.shortcut, "value" => sheet.name} end)
  end

  @doc """
  Resolves current authored values for simple and table qualified references.

  The returned map contains only references that still resolve in the active
  project state.
  """
  @spec resolve_variable_values(integer(), [String.t()]) :: map()
  def resolve_variable_values(project_id, references) when is_list(references) do
    {simple_references, table_references} = classify_references(references)

    Map.merge(
      resolve_simple_values(project_id, simple_references),
      resolve_table_values(project_id, table_references)
    )
  end

  defp classify_references(references) do
    Enum.split_with(references, fn reference ->
      reference |> String.split(".") |> length() == 2
    end)
  end

  defp resolve_simple_values(_project_id, []), do: %{}

  defp resolve_simple_values(project_id, references) do
    pairs = references |> Enum.map(&parse_simple_reference/1) |> Enum.reject(&is_nil/1)
    do_resolve_simple(project_id, pairs)
  end

  defp parse_simple_reference(reference) do
    case String.split(reference, ".", parts: 2) do
      [namespace, variable_name] -> {namespace, variable_name}
      _invalid -> nil
    end
  end

  defp do_resolve_simple(_project_id, []), do: %{}

  defp do_resolve_simple(project_id, pairs) do
    namespaces = pairs |> Enum.map(&elem(&1, 0)) |> Enum.uniq()
    namespace_ids = VariableNamespaces.resolve_sheet_ids(project_id, namespaces)
    namespace_by_id = Map.new(namespace_ids, fn {namespace, id} -> {id, namespace} end)
    pair_set = MapSet.new(pairs)

    project_id
    |> query_simple_blocks(Map.keys(namespace_by_id))
    |> Repo.all()
    |> build_simple_results(pair_set, namespace_by_id)
  end

  defp query_simple_blocks(project_id, sheet_ids) do
    from(block in Block,
      join: sheet in Sheet,
      on: block.sheet_id == sheet.id,
      where:
        sheet.project_id == ^project_id and
          is_nil(sheet.deleted_at) and
          is_nil(block.deleted_at) and
          not is_nil(block.variable_name) and
          block.variable_name != "" and
          sheet.id in ^sheet_ids,
      select: %{sheet_id: sheet.id, variable_name: block.variable_name, value: block.value}
    )
  end

  defp build_simple_results(rows, pair_set, namespace_by_id) do
    Enum.reduce(rows, %{}, fn row, results ->
      namespace = Map.fetch!(namespace_by_id, row.sheet_id)

      if MapSet.member?(pair_set, {namespace, row.variable_name}) do
        Map.put(results, "#{namespace}.#{row.variable_name}", extract_block_value(row.value))
      else
        results
      end
    end)
  end

  defp resolve_table_values(_project_id, []), do: %{}

  defp resolve_table_values(project_id, references) do
    parsed = references |> Enum.map(&parse_table_reference/1) |> Enum.reject(&is_nil/1)
    do_resolve_table(project_id, parsed)
  end

  defp parse_table_reference(reference) do
    case String.split(reference, ".") do
      [namespace, table_name, row_slug, column_slug] ->
        %{
          namespace: namespace,
          table_name: table_name,
          row_slug: row_slug,
          column_slug: column_slug,
          reference: reference
        }

      _invalid ->
        nil
    end
  end

  defp do_resolve_table(_project_id, []), do: %{}

  defp do_resolve_table(project_id, parsed) do
    namespaces = parsed |> Enum.map(& &1.namespace) |> Enum.uniq()
    namespace_ids = VariableNamespaces.resolve_sheet_ids(project_id, namespaces)
    namespace_by_id = Map.new(namespace_ids, fn {namespace, id} -> {id, namespace} end)
    rows = project_id |> query_table_rows(Map.keys(namespace_by_id)) |> Repo.all()

    Enum.reduce(parsed, %{}, fn entry, results ->
      case find_matching_row(rows, entry, namespace_by_id) do
        nil -> results
        row -> Map.put(results, entry.reference, resolve_cell_value(row.cells, entry.column_slug))
      end
    end)
  end

  defp query_table_rows(project_id, sheet_ids) do
    from(row in TableRow,
      join: block in Block,
      on: row.block_id == block.id,
      join: sheet in Sheet,
      on: block.sheet_id == sheet.id,
      where:
        sheet.project_id == ^project_id and
          is_nil(sheet.deleted_at) and
          is_nil(block.deleted_at) and
          block.type == "table" and
          sheet.id in ^sheet_ids,
      select: %{
        sheet_id: sheet.id,
        table_name: block.variable_name,
        row_slug: row.slug,
        cells: row.cells
      }
    )
  end

  defp find_matching_row(rows, entry, namespace_by_id) do
    Enum.find(rows, fn row ->
      Map.fetch!(namespace_by_id, row.sheet_id) == entry.namespace and
        row.table_name == entry.table_name and row.row_slug == entry.row_slug
    end)
  end

  defp resolve_cell_value(cells, column_slug) do
    case cells[column_slug] do
      %{"expression" => expression, "bindings" => bindings} when is_binary(expression) and expression != "" ->
        compute_formula_cell(expression, bindings, cells)

      other ->
        other
    end
  end

  defp compute_formula_cell(expression, bindings, row_cells) do
    values =
      Map.new(bindings || %{}, fn {symbol, binding} ->
        value =
          case binding do
            %{"type" => "same_row", "column_slug" => slug} -> MapUtils.parse_to_number(row_cells[slug])
            %{"type" => "variable", "ref" => _reference} -> 0.0
            _invalid -> 0.0
          end

        {symbol, value}
      end)

    case FormulaEngine.compute(expression, values) do
      {:ok, result} -> MapUtils.format_number_result(result)
      {:error, _reason} -> nil
    end
  end

  defp extract_block_value(%{"content" => content}), do: content
  defp extract_block_value(_value), do: nil
end

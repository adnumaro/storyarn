defmodule Storyarn.Sheets.VariableCatalog do
  @moduledoc """
  Bounded, content-free read model for variable lookup surfaces.

  The editor's variable APIs intentionally return values, constraints and
  formula payloads. Command-palette lookup must not expose any of that authored
  content, so this module selects only identity and navigation metadata.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Repo
  alias Storyarn.Shared.SearchHelpers
  alias Storyarn.Sheets.Block
  alias Storyarn.Sheets.Sheet
  alias Storyarn.Sheets.TableColumn
  alias Storyarn.Sheets.TableRow

  @default_limit 25
  @max_limit 50
  @variable_types ~w(text rich_text number select multi_select boolean date)
  @variable_column_types ~w(number text boolean select multi_select date reference formula)

  @type page(item) :: %{items: [item], truncated: boolean()}

  @doc """
  Lists lightweight variable definitions in one project.

  Supported filters are private domain vocabulary, deliberately expressed as
  tagged data rather than SQL fragments:

    * `:all`
    * `{:contains, query}`
    * `{:qualified, qualified_ref}`
    * `{:qualified_block, qualified_ref, block_id}`
    * `{:sheet, shortcut}`
    * `{:variable, name}`
    * `{:variable_contains, term}`
  """
  @spec list_definitions(integer(), term(), keyword()) :: page(map())
  def list_definitions(project_id, filter \\ :all, opts \\ []) do
    limit = bounded_limit(opts)
    fetch_limit = limit + 1

    items =
      regular_definitions(project_id, filter, fetch_limit) ++
        table_definitions(project_id, filter, fetch_limit)

    items =
      Enum.sort_by(
        items,
        &{String.downcase(&1.qualified_ref), &1.block_id, Map.get(&1, :row_id, 0), Map.get(&1, :column_id, 0)}
      )

    %{items: Enum.take(items, limit), truncated: length(items) > limit}
  end

  @doc """
  Resolves one client-selected definition against the active project state.
  """
  @spec get_definition(integer(), integer(), String.t()) :: map() | nil
  def get_definition(project_id, block_id, qualified_ref) when is_integer(block_id) and is_binary(qualified_ref) do
    project_id
    |> list_definitions({:qualified_block, qualified_ref, block_id}, limit: 1)
    |> Map.fetch!(:items)
    |> Enum.find(&(&1.block_id == block_id and &1.qualified_ref == qualified_ref))
  end

  def get_definition(_project_id, _block_id, _qualified_ref), do: nil

  @doc """
  Lists formula cells whose bindings read the exact qualified reference.

  Only formula-cell navigation metadata is selected. The expression, bindings
  object and evaluated cell value never cross this boundary.
  """
  @spec list_formula_usages(integer(), String.t(), keyword()) :: page(map())
  def list_formula_usages(project_id, qualified_ref, opts \\ [])

  def list_formula_usages(project_id, qualified_ref, opts) when is_binary(qualified_ref) do
    limit = bounded_limit(opts)

    items =
      Repo.all(
        from(row in TableRow,
          join: block in Block,
          on: block.id == row.block_id,
          join: sheet in Sheet,
          on: sheet.id == block.sheet_id,
          join: column in TableColumn,
          on: column.block_id == block.id and column.type == "formula",
          where:
            sheet.project_id == ^project_id and is_nil(sheet.deleted_at) and is_nil(block.deleted_at) and
              block.type == "table",
          where:
            fragment(
              """
              jsonb_path_exists(
                COALESCE(? -> ? -> 'bindings', '{}'::jsonb),
                '$.* \\? (@.type == "variable" && @.ref == $reference)',
                jsonb_build_object('reference', to_jsonb(?::text))
              )
              """,
              row.cells,
              column.slug,
              ^qualified_ref
            ),
          order_by: [
            asc: sheet.name,
            asc: block.position,
            asc: row.position,
            asc: column.position,
            asc: row.id,
            asc: column.id
          ],
          limit: ^(limit + 1),
          select: %{
            sheet_id: sheet.id,
            sheet_name: sheet.name,
            sheet_shortcut: coalesce(sheet.shortcut, fragment("CAST(? AS TEXT)", sheet.id)),
            block_id: block.id,
            table_name: block.variable_name,
            row_id: row.id,
            row_name: row.name,
            row_slug: row.slug,
            column_id: column.id,
            column_name: column.name,
            column_slug: column.slug
          }
        )
      )

    %{items: Enum.take(items, limit), truncated: length(items) > limit}
  end

  def list_formula_usages(_project_id, _qualified_ref, _opts), do: %{items: [], truncated: false}

  defp regular_definitions(project_id, filter, limit) do
    from(block in Block,
      join: sheet in Sheet,
      on: block.sheet_id == sheet.id,
      where:
        sheet.project_id == ^project_id and is_nil(sheet.deleted_at) and
          is_nil(block.deleted_at) and block.type in ^@variable_types and
          block.is_constant == false and not is_nil(block.variable_name) and
          block.variable_name != "",
      order_by: [asc: sheet.name, asc: block.position, asc: block.id],
      limit: ^limit,
      select: %{
        sheet_id: sheet.id,
        sheet_name: sheet.name,
        sheet_shortcut: coalesce(sheet.shortcut, fragment("CAST(? AS TEXT)", sheet.id)),
        block_id: block.id,
        block_type: block.type,
        variable_name: block.variable_name,
        qualified_ref:
          fragment(
            "COALESCE(?, CAST(? AS TEXT)) || '.' || ?",
            sheet.shortcut,
            sheet.id,
            block.variable_name
          ),
        table_name: nil,
        row_id: nil,
        row_name: nil,
        row_slug: nil,
        column_id: nil,
        column_name: nil,
        column_slug: nil
      }
    )
    |> filter_regular(filter)
    |> Repo.all()
  end

  defp table_definitions(project_id, filter, limit) do
    from(column in TableColumn,
      join: block in Block,
      on: column.block_id == block.id,
      join: sheet in Sheet,
      on: block.sheet_id == sheet.id,
      join: row in TableRow,
      on: row.block_id == block.id,
      where:
        sheet.project_id == ^project_id and is_nil(sheet.deleted_at) and
          is_nil(block.deleted_at) and block.type == "table" and
          column.type in ^@variable_column_types and
          (column.is_constant == false or column.type == "formula") and
          not is_nil(block.variable_name) and block.variable_name != "",
      order_by: [
        asc: sheet.name,
        asc: block.position,
        asc: row.position,
        asc: column.position,
        asc: row.id,
        asc: column.id
      ],
      limit: ^limit,
      select: %{
        sheet_id: sheet.id,
        sheet_name: sheet.name,
        sheet_shortcut: coalesce(sheet.shortcut, fragment("CAST(? AS TEXT)", sheet.id)),
        block_id: block.id,
        block_type: column.type,
        variable_name: fragment("? || '.' || ? || '.' || ?", block.variable_name, row.slug, column.slug),
        qualified_ref:
          fragment(
            "COALESCE(?, CAST(? AS TEXT)) || '.' || ? || '.' || ? || '.' || ?",
            sheet.shortcut,
            sheet.id,
            block.variable_name,
            row.slug,
            column.slug
          ),
        table_name: block.variable_name,
        row_id: row.id,
        row_name: row.name,
        row_slug: row.slug,
        column_id: column.id,
        column_name: column.name,
        column_slug: column.slug
      }
    )
    |> filter_table(filter)
    |> Repo.all()
  end

  defp filter_regular(query, :all), do: query

  defp filter_regular(query, {:contains, value}) do
    term = contains_term(value)

    from([block, sheet] in query,
      where:
        ilike(
          fragment("COALESCE(?, CAST(? AS TEXT)) || '.' || ?", sheet.shortcut, sheet.id, block.variable_name),
          ^term
        ) or ilike(sheet.name, ^term)
    )
  end

  defp filter_regular(query, {:qualified, value}) do
    from([block, sheet] in query,
      where:
        fragment("COALESCE(?, CAST(? AS TEXT)) || '.' || ?", sheet.shortcut, sheet.id, block.variable_name) ==
          ^value
    )
  end

  defp filter_regular(query, {:qualified_block, value, block_id}) do
    query
    |> filter_regular({:qualified, value})
    |> where([block, _sheet], block.id == ^block_id)
  end

  defp filter_regular(query, {:sheet, value}), do: from([_block, sheet] in query, where: sheet.shortcut == ^value)
  defp filter_regular(query, {:variable, value}), do: from([block, _sheet] in query, where: block.variable_name == ^value)

  defp filter_regular(query, {:variable_contains, value}) do
    from([block, _sheet] in query, where: ilike(block.variable_name, ^contains_term(value)))
  end

  defp filter_table(query, :all), do: query

  defp filter_table(query, {:contains, value}) do
    term = contains_term(value)

    from([column, block, sheet, row] in query,
      where:
        ilike(
          fragment(
            "COALESCE(?, CAST(? AS TEXT)) || '.' || ? || '.' || ? || '.' || ?",
            sheet.shortcut,
            sheet.id,
            block.variable_name,
            row.slug,
            column.slug
          ),
          ^term
        ) or ilike(sheet.name, ^term)
    )
  end

  defp filter_table(query, {:qualified, value}) do
    from([column, block, sheet, row] in query,
      where:
        fragment(
          "COALESCE(?, CAST(? AS TEXT)) || '.' || ? || '.' || ? || '.' || ?",
          sheet.shortcut,
          sheet.id,
          block.variable_name,
          row.slug,
          column.slug
        ) == ^value
    )
  end

  defp filter_table(query, {:qualified_block, value, block_id}) do
    query
    |> filter_table({:qualified, value})
    |> where([_column, block, _sheet, _row], block.id == ^block_id)
  end

  defp filter_table(query, {:sheet, value}),
    do: from([_column, _block, sheet, _row] in query, where: sheet.shortcut == ^value)

  defp filter_table(query, {:variable, value}),
    do: from([column, _block, _sheet, _row] in query, where: column.slug == ^value)

  defp filter_table(query, {:variable_contains, value}) do
    from([column, _block, _sheet, _row] in query, where: ilike(column.slug, ^contains_term(value)))
  end

  defp contains_term(value), do: "%#{SearchHelpers.sanitize_like_query(to_string(value))}%"

  defp bounded_limit(opts) do
    opts
    |> Keyword.get(:limit, @default_limit)
    |> max(1)
    |> min(@max_limit)
  end
end

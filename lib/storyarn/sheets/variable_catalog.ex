defmodule Storyarn.Sheets.VariableCatalog do
  @moduledoc """
  Bounded read model for variable-search surfaces.

  Queries select identity, navigation metadata, type and the authored initial
  value required for typed predicates. They deliberately do not expose block
  configuration, formula expressions, bindings, or unrelated JSON payloads.
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
  @constant_variable_column_types ~w(formula)

  @type page(item) :: %{items: [item], truncated: boolean()}

  @doc "Returns the canonical regular Block types exposed as variables."
  @spec regular_variable_types() :: [String.t()]
  def regular_variable_types, do: @variable_types

  @doc "Returns the canonical table-column types exposed as variables."
  @spec table_variable_types() :: [String.t()]
  def table_variable_types, do: @variable_column_types

  @doc "Returns table-column types that remain variables when marked constant."
  @spec constant_table_variable_types() :: [String.t()]
  def constant_table_variable_types, do: @constant_variable_column_types

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
    list_definition_page(project_id, filter, limit)
  end

  @doc """
  Lists authored initial values matching one typed predicate.

  The predicate is applied in PostgreSQL before the result bound, so a matching
  definition cannot disappear behind an arbitrary autocomplete candidate page.
  """
  @spec list_initial_value_matches(integer(), term(), atom(), String.t(), keyword()) :: page(map())
  def list_initial_value_matches(project_id, filter, operator, literal, opts \\ []) do
    limit = bounded_limit(opts)
    fetch_limit = limit + 1

    items =
      regular_initial_value_matches(project_id, filter, operator, literal, fetch_limit) ++
        table_initial_value_matches(project_id, filter, operator, literal, fetch_limit)

    definition_page(items, limit)
  end

  defp list_definition_page(project_id, filter, limit) do
    fetch_limit = limit + 1

    items =
      regular_definitions(project_id, filter, fetch_limit) ++
        table_definitions(project_id, filter, fetch_limit)

    definition_page(items, limit)
  end

  defp definition_page(items, limit) do
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
  Returns normalized string aliases for one predicate literal and operator.

  Select fields resolve matching visible option labels and stored keys without
  returning the field configuration to the caller. Other field types simply
  return the normalized literal.
  """
  @spec predicate_string_aliases(integer(), map(), atom(), String.t()) :: [String.t()]
  def predicate_string_aliases(project_id, definition, operator, literal)
      when is_integer(project_id) and is_map(definition) and is_atom(operator) and is_binary(literal) do
    normalized = normalized_literal(literal)

    if definition.block_type == "select" and normalized != "" do
      project_id
      |> definition_config(definition)
      |> matching_option_aliases(operator, normalized)
      |> MapSet.put(normalized)
      |> MapSet.to_list()
    else
      if normalized == "", do: [], else: [normalized]
    end
  end

  def predicate_string_aliases(_project_id, _definition, _operator, _literal), do: []

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

  defp definition_config(project_id, %{column_id: nil, block_id: block_id}) do
    Repo.one(
      from(block in Block,
        join: sheet in Sheet,
        on: sheet.id == block.sheet_id,
        where:
          block.id == ^block_id and sheet.project_id == ^project_id and
            is_nil(block.deleted_at) and is_nil(sheet.deleted_at),
        select: block.config
      )
    )
  end

  defp definition_config(project_id, %{block_id: block_id, column_id: column_id}) do
    Repo.one(
      from(column in TableColumn,
        join: block in Block,
        on: block.id == column.block_id,
        join: sheet in Sheet,
        on: sheet.id == block.sheet_id,
        where:
          column.id == ^column_id and block.id == ^block_id and
            sheet.project_id == ^project_id and is_nil(block.deleted_at) and
            is_nil(sheet.deleted_at),
        select: column.config
      )
    )
  end

  defp definition_config(_project_id, _definition), do: nil

  defp matching_option_aliases(config, operator, normalized) when is_map(config) do
    case Map.get(config, "options", []) do
      options when is_list(options) -> reduce_option_aliases(options, operator, normalized)
      _invalid_options -> MapSet.new()
    end
  end

  defp matching_option_aliases(_config, _operator, _normalized), do: MapSet.new()

  defp reduce_option_aliases(options, operator, normalized) do
    Enum.reduce(options, MapSet.new(), fn
      option, aliases when is_map(option) ->
        key = option |> Map.get("key", "") |> normalize_option_value()
        label = option |> option_label() |> normalize_option_value()

        if option_alias_matches?(operator, normalized, key, label) do
          aliases
          |> maybe_put_alias(key)
          |> maybe_put_alias(label)
        else
          aliases
        end

      _invalid_option, aliases ->
        aliases
    end)
  end

  defp option_alias_matches?(operator, normalized, key, label) when operator in [:contains, :not_contains] do
    String.contains?(key, normalized) or String.contains?(label, normalized)
  end

  defp option_alias_matches?(_operator, normalized, key, label), do: normalized in [key, label]

  defp option_label(option), do: Map.get(option, "value") || Map.get(option, "label") || ""

  defp normalize_option_value(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.normalize(:nfc)
    |> String.downcase()
  end

  defp normalize_option_value(_value), do: ""

  defp maybe_put_alias(aliases, ""), do: aliases
  defp maybe_put_alias(aliases, value), do: MapSet.put(aliases, value)

  defp regular_definitions(project_id, filter, limit) do
    project_id
    |> regular_definition_query(limit)
    |> filter_regular(filter)
    |> Repo.all()
  end

  defp regular_initial_value_matches(project_id, filter, operator, literal, limit) do
    project_id
    |> regular_definition_query(limit)
    |> filter_regular(filter)
    |> filter_regular_initial_value(operator, literal)
    |> Repo.all()
  end

  defp regular_definition_query(project_id, limit) do
    from(block in Block,
      join: sheet in Sheet,
      on: block.sheet_id == sheet.id,
      where:
        sheet.project_id == ^project_id and is_nil(sheet.deleted_at) and
          is_nil(block.deleted_at) and block.type in ^@variable_types and
          block.is_constant == false and not is_nil(block.variable_name) and
          block.variable_name != "",
      order_by: [
        asc:
          fragment(
            "LOWER(COALESCE(?, CAST(? AS TEXT)) || '.' || ?) COLLATE \"C\"",
            sheet.shortcut,
            sheet.id,
            block.variable_name
          ),
        asc: block.id
      ],
      limit: ^limit,
      select: %{
        sheet_id: sheet.id,
        sheet_name: sheet.name,
        sheet_shortcut: coalesce(sheet.shortcut, fragment("CAST(? AS TEXT)", sheet.id)),
        block_id: block.id,
        block_type: block.type,
        initial_value: fragment("?->'content'", block.value),
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
  end

  defp table_definitions(project_id, filter, limit) do
    project_id
    |> table_definition_query(limit)
    |> filter_table(filter)
    |> Repo.all()
  end

  defp table_initial_value_matches(project_id, filter, operator, literal, limit) do
    project_id
    |> table_definition_query(limit)
    |> filter_table(filter)
    |> filter_table_initial_value(operator, literal)
    |> Repo.all()
  end

  defp table_definition_query(project_id, limit) do
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
          (column.is_constant == false or
             column.type in ^@constant_variable_column_types) and
          not is_nil(block.variable_name) and block.variable_name != "",
      order_by: [
        asc:
          fragment(
            "LOWER(COALESCE(?, CAST(? AS TEXT)) || '.' || ? || '.' || ? || '.' || ?) COLLATE \"C\"",
            sheet.shortcut,
            sheet.id,
            block.variable_name,
            row.slug,
            column.slug
          ),
        asc: block.id,
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
        initial_value: fragment("?->?", row.cells, column.slug),
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
        fragment(
          "LOWER(COALESCE(?, CAST(? AS TEXT)) || '.' || ?)",
          sheet.shortcut,
          sheet.id,
          block.variable_name
        ) == ^String.downcase(value)
    )
  end

  defp filter_regular(query, {:qualified_block, value, block_id}) do
    query
    |> filter_regular({:qualified, value})
    |> where([block, _sheet], block.id == ^block_id)
  end

  defp filter_regular(query, {:sheet, value}), do: from([_block, sheet] in query, where: sheet.shortcut == ^value)

  defp filter_regular(query, {:variable, value}),
    do: from([block, _sheet] in query, where: fragment("LOWER(?)", block.variable_name) == ^String.downcase(value))

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
          "LOWER(COALESCE(?, CAST(? AS TEXT)) || '.' || ? || '.' || ? || '.' || ?)",
          sheet.shortcut,
          sheet.id,
          block.variable_name,
          row.slug,
          column.slug
        ) == ^String.downcase(value)
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
    do: from([column, _block, _sheet, _row] in query, where: fragment("LOWER(?)", column.slug) == ^String.downcase(value))

  defp filter_table(query, {:variable_contains, value}) do
    from([column, _block, _sheet, _row] in query, where: ilike(column.slug, ^contains_term(value)))
  end

  defp filter_regular_initial_value(query, operator, literal) do
    literal = normalized_literal(literal)

    predicate =
      [
        regular_string_predicate(operator, literal),
        regular_number_predicate(operator, parse_number(literal)),
        regular_boolean_predicate(operator, parse_boolean(literal)),
        regular_date_predicate(operator, parse_date(literal))
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.reduce(dynamic([_block, _sheet], false), fn item, combined ->
        dynamic([block, sheet], ^combined or ^item)
      end)

    from([_block, _sheet] in query, where: ^predicate)
  end

  defp filter_table_initial_value(query, operator, literal) do
    literal = normalized_literal(literal)

    predicate =
      [
        table_string_predicate(operator, literal),
        table_number_predicate(operator, parse_number(literal)),
        table_boolean_predicate(operator, parse_boolean(literal)),
        table_date_predicate(operator, parse_date(literal))
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.reduce(dynamic([_column, _block, _sheet, _row], false), fn item, combined ->
        dynamic([column, block, sheet, row], ^combined or ^item)
      end)

    from([_column, _block, _sheet, _row] in query, where: ^predicate)
  end

  defp regular_string_predicate(:equal, expected) do
    dynamic(
      [block, _sheet],
      (block.type in ["text", "rich_text"] and
         fragment(
           "jsonb_typeof(?->'content') = 'string' AND LOWER(BTRIM(?->>'content')) = ?",
           block.value,
           block.value,
           ^expected
         )) or
        (block.type == "select" and
           fragment(
             """
             (
               (
                 jsonb_typeof(?->'content') = 'string'
                 AND LOWER(BTRIM(?->>'content')) = ?
               )
               OR EXISTS (
                 SELECT 1
                 FROM jsonb_array_elements(
                   CASE
                     WHEN jsonb_typeof(?->'options') = 'array' THEN ?->'options'
                     ELSE '[]'::jsonb
                   END
                 ) AS option(item)
                 WHERE option.item->>'key' = ?->>'content'
                   AND LOWER(BTRIM(COALESCE(option.item->>'value', option.item->>'label', ''))) = ?
               )
             )
             """,
             block.value,
             block.value,
             ^expected,
             block.config,
             block.config,
             block.value,
             ^expected
           ))
    )
  end

  defp regular_string_predicate(:not_equal, expected) do
    dynamic(
      [block, _sheet],
      block.type in ["text", "rich_text", "select"] and
        fragment("jsonb_typeof(?->'content') = 'string'", block.value) and
        not fragment(
          """
          (
            LOWER(BTRIM(?->>'content')) = ?
            OR (
              ? = 'select'
              AND EXISTS (
                SELECT 1
                FROM jsonb_array_elements(
                  CASE
                    WHEN jsonb_typeof(?->'options') = 'array' THEN ?->'options'
                    ELSE '[]'::jsonb
                  END
                ) AS option(item)
                WHERE option.item->>'key' = ?->>'content'
                  AND LOWER(BTRIM(COALESCE(option.item->>'value', option.item->>'label', ''))) = ?
              )
            )
          )
          """,
          block.value,
          ^expected,
          block.type,
          block.config,
          block.config,
          block.value,
          ^expected
        )
    )
  end

  defp regular_string_predicate(operator, "") when operator in [:contains, :not_contains], do: nil

  defp regular_string_predicate(:contains, expected), do: regular_string_contains_predicate(expected)

  defp regular_string_predicate(:not_contains, expected) do
    contains_predicate = regular_string_contains_predicate(expected)

    dynamic(
      [block, _sheet],
      block.type in ["text", "rich_text", "select"] and
        fragment("jsonb_typeof(?->'content') = 'string'", block.value) and
        not (^contains_predicate)
    )
  end

  defp regular_string_predicate(_operator, _expected), do: nil

  defp regular_string_contains_predicate(expected) do
    pattern = contains_term(expected)

    dynamic(
      [block, _sheet],
      (block.type in ["text", "rich_text"] and
         fragment(
           "jsonb_typeof(?->'content') = 'string' AND LOWER(BTRIM(?->>'content')) LIKE ?",
           block.value,
           block.value,
           ^pattern
         )) or
        (block.type == "select" and
           fragment(
             """
             (
               (
                 jsonb_typeof(?->'content') = 'string'
                 AND LOWER(BTRIM(?->>'content')) LIKE ?
               )
               OR EXISTS (
                 SELECT 1
                 FROM jsonb_array_elements(
                   CASE
                     WHEN jsonb_typeof(?->'options') = 'array' THEN ?->'options'
                     ELSE '[]'::jsonb
                   END
                 ) AS option(item)
                 WHERE option.item->>'key' = ?->>'content'
                   AND LOWER(BTRIM(COALESCE(option.item->>'value', option.item->>'label', ''))) LIKE ?
               )
             )
             """,
             block.value,
             block.value,
             ^pattern,
             block.config,
             block.config,
             block.value,
             ^pattern
           ))
    )
  end

  defp table_string_predicate(:equal, expected) do
    dynamic(
      [column, _block, _sheet, row],
      (column.type == "text" and
         fragment(
           "jsonb_typeof(?->?) = 'string' AND LOWER(BTRIM(?->>?)) = ?",
           row.cells,
           column.slug,
           row.cells,
           column.slug,
           ^expected
         )) or
        (column.type == "select" and
           fragment(
             """
             (
               (
                 jsonb_typeof(?->?) = 'string'
                 AND LOWER(BTRIM(?->>?)) = ?
               )
               OR EXISTS (
                 SELECT 1
                 FROM jsonb_array_elements(
                   CASE
                     WHEN jsonb_typeof(?->'options') = 'array' THEN ?->'options'
                     ELSE '[]'::jsonb
                   END
                 ) AS option(item)
                 WHERE option.item->>'key' = ?->>?
                   AND LOWER(BTRIM(COALESCE(option.item->>'value', option.item->>'label', ''))) = ?
               )
             )
             """,
             row.cells,
             column.slug,
             row.cells,
             column.slug,
             ^expected,
             column.config,
             column.config,
             row.cells,
             column.slug,
             ^expected
           ))
    )
  end

  defp table_string_predicate(:not_equal, expected) do
    dynamic(
      [column, _block, _sheet, row],
      column.type in ["text", "select"] and
        fragment("jsonb_typeof(?->?) = 'string'", row.cells, column.slug) and
        not fragment(
          """
          (
            LOWER(BTRIM(?->>?)) = ?
            OR (
              ? = 'select'
              AND EXISTS (
                SELECT 1
                FROM jsonb_array_elements(
                  CASE
                    WHEN jsonb_typeof(?->'options') = 'array' THEN ?->'options'
                    ELSE '[]'::jsonb
                  END
                ) AS option(item)
                WHERE option.item->>'key' = ?->>?
                  AND LOWER(BTRIM(COALESCE(option.item->>'value', option.item->>'label', ''))) = ?
              )
            )
          )
          """,
          row.cells,
          column.slug,
          ^expected,
          column.type,
          column.config,
          column.config,
          row.cells,
          column.slug,
          ^expected
        )
    )
  end

  defp table_string_predicate(operator, "") when operator in [:contains, :not_contains], do: nil

  defp table_string_predicate(:contains, expected), do: table_string_contains_predicate(expected)

  defp table_string_predicate(:not_contains, expected) do
    contains_predicate = table_string_contains_predicate(expected)

    dynamic(
      [column, _block, _sheet, row],
      column.type in ["text", "select"] and
        fragment("jsonb_typeof(?->?) = 'string'", row.cells, column.slug) and
        not (^contains_predicate)
    )
  end

  defp table_string_predicate(_operator, _expected), do: nil

  defp table_string_contains_predicate(expected) do
    pattern = contains_term(expected)

    dynamic(
      [column, _block, _sheet, row],
      (column.type == "text" and
         fragment(
           "jsonb_typeof(?->?) = 'string' AND LOWER(BTRIM(?->>?)) LIKE ?",
           row.cells,
           column.slug,
           row.cells,
           column.slug,
           ^pattern
         )) or
        (column.type == "select" and
           fragment(
             """
             (
               (
                 jsonb_typeof(?->?) = 'string'
                 AND LOWER(BTRIM(?->>?)) LIKE ?
               )
               OR EXISTS (
                 SELECT 1
                 FROM jsonb_array_elements(
                   CASE
                     WHEN jsonb_typeof(?->'options') = 'array' THEN ?->'options'
                     ELSE '[]'::jsonb
                   END
                 ) AS option(item)
                 WHERE option.item->>'key' = ?->>?
                   AND LOWER(BTRIM(COALESCE(option.item->>'value', option.item->>'label', ''))) LIKE ?
               )
             )
             """,
             row.cells,
             column.slug,
             row.cells,
             column.slug,
             ^pattern,
             column.config,
             column.config,
             row.cells,
             column.slug,
             ^pattern
           ))
    )
  end

  for {name, sql_operator} <- [
        equal: "=",
        not_equal: "<>",
        greater_than: ">",
        greater_than_or_equal: ">=",
        less_than: "<",
        less_than_or_equal: "<="
      ] do
    defp regular_number_predicate(unquote(name), {:ok, expected}) do
      dynamic(
        [block, _sheet],
        block.type == "number" and
          fragment(
            unquote(
              "CASE WHEN jsonb_typeof(?->'content') = 'number' THEN (?->>'content')::double precision #{sql_operator} ? ELSE FALSE END"
            ),
            block.value,
            block.value,
            ^expected
          )
      )
    end

    defp table_number_predicate(unquote(name), {:ok, expected}) do
      dynamic(
        [column, _block, _sheet, row],
        column.type == "number" and
          fragment(
            unquote(
              "CASE WHEN jsonb_typeof(?->?) = 'number' THEN (?->>?)::double precision #{sql_operator} ? ELSE FALSE END"
            ),
            row.cells,
            column.slug,
            row.cells,
            column.slug,
            ^expected
          )
      )
    end

    defp regular_date_predicate(unquote(name), {:ok, expected}) do
      dynamic(
        [block, _sheet],
        block.type == "date" and
          fragment(
            unquote(
              "CASE WHEN jsonb_typeof(?->'content') = 'string' AND (?->>'content') ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' THEN (?->>'content') #{sql_operator} ? ELSE FALSE END"
            ),
            block.value,
            block.value,
            block.value,
            ^expected
          )
      )
    end

    defp table_date_predicate(unquote(name), {:ok, expected}) do
      dynamic(
        [column, _block, _sheet, row],
        column.type == "date" and
          fragment(
            unquote(
              "CASE WHEN jsonb_typeof(?->?) = 'string' AND (?->>?) ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' THEN (?->>?) #{sql_operator} ? ELSE FALSE END"
            ),
            row.cells,
            column.slug,
            row.cells,
            column.slug,
            row.cells,
            column.slug,
            ^expected
          )
      )
    end
  end

  defp regular_number_predicate(_operator, _expected), do: nil
  defp table_number_predicate(_operator, _expected), do: nil
  defp regular_date_predicate(_operator, _expected), do: nil
  defp table_date_predicate(_operator, _expected), do: nil

  for {name, sql_operator} <- [equal: "=", not_equal: "<>"] do
    defp regular_boolean_predicate(unquote(name), {:ok, expected}) do
      dynamic(
        [block, _sheet],
        block.type == "boolean" and
          fragment(
            unquote(
              "CASE WHEN jsonb_typeof(?->'content') = 'boolean' THEN (?->>'content')::boolean #{sql_operator} ? ELSE FALSE END"
            ),
            block.value,
            block.value,
            ^expected
          )
      )
    end

    defp table_boolean_predicate(unquote(name), {:ok, expected}) do
      dynamic(
        [column, _block, _sheet, row],
        column.type == "boolean" and
          fragment(
            unquote("CASE WHEN jsonb_typeof(?->?) = 'boolean' THEN (?->>?)::boolean #{sql_operator} ? ELSE FALSE END"),
            row.cells,
            column.slug,
            row.cells,
            column.slug,
            ^expected
          )
      )
    end
  end

  defp regular_boolean_predicate(_operator, _expected), do: nil

  defp table_boolean_predicate(_operator, _expected), do: nil

  defp normalized_literal(literal) do
    literal
    |> unquote_literal()
    |> String.trim()
    |> String.normalize(:nfc)
    |> String.downcase()
  end

  defp unquote_literal(<<"\"", rest::binary>>) do
    if String.ends_with?(rest, "\"") do
      binary_part(rest, 0, byte_size(rest) - 1)
    else
      "\"" <> rest
    end
  end

  defp unquote_literal(literal), do: literal

  defp parse_number(literal) do
    case Float.parse(literal) do
      {value, ""} -> {:ok, value}
      _invalid -> :error
    end
  end

  defp parse_boolean("true"), do: {:ok, true}
  defp parse_boolean("false"), do: {:ok, false}
  defp parse_boolean(_literal), do: :error

  defp parse_date(literal) do
    case Date.from_iso8601(literal) do
      {:ok, date} -> {:ok, Date.to_iso8601(date)}
      _invalid -> :error
    end
  end

  defp contains_term(value), do: "%#{SearchHelpers.sanitize_like_query(to_string(value))}%"

  defp bounded_limit(opts) do
    opts
    |> Keyword.get(:limit, @default_limit)
    |> max(1)
    |> min(@max_limit)
  end
end

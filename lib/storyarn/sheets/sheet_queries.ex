defmodule Storyarn.Sheets.SheetQueries do
  @moduledoc """
  Read-only query functions for sheets.

  Provides all sheet retrieval, listing, search, and tree traversal operations.
  Mutation operations remain in `SheetCrud`.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Repo
  alias Storyarn.Shared.FormulaEngine
  alias Storyarn.Shared.MapUtils
  alias Storyarn.Shared.SearchHelpers
  alias Storyarn.Shared.TreeOperations, as: SharedTree
  alias Storyarn.Sheets.Block
  alias Storyarn.Sheets.BlockGalleryImage
  alias Storyarn.Sheets.Persistence.FlowNodeRecord
  alias Storyarn.Sheets.Persistence.FlowRecord
  alias Storyarn.Sheets.Persistence.VariableReferenceRecord
  alias Storyarn.Sheets.Sheet
  alias Storyarn.Sheets.TableColumn
  alias Storyarn.Sheets.TableRow
  alias Storyarn.Sheets.VariableCatalog
  alias Storyarn.Sheets.VariableNamespaceResolver

  require VariableNamespaceResolver

  # =============================================================================
  # Tree Operations
  # =============================================================================

  @doc """
  Lists root-level sheets for a project as a recursive tree.
  Each sheet has `:children` populated with nested descendants.
  """
  @spec list_sheets_tree(integer()) :: [Sheet.t()]
  def list_sheets_tree(project_id) do
    # Single query for all non-deleted sheets, then build tree in memory
    all_sheets =
      Repo.all(
        from(s in Sheet,
          where: s.project_id == ^project_id and is_nil(s.deleted_at),
          order_by: [asc: s.position, asc: s.name],
          preload: [avatars: :asset]
        )
      )

    SharedTree.build_tree_from_flat_list(all_sheets)
  end

  @doc """
  Gets a sheet with blocks and assets preloaded. Returns nil if not found.
  """
  @spec get_sheet(integer(), integer()) :: Sheet.t() | nil
  def get_sheet(project_id, sheet_id) do
    Sheet
    |> where(project_id: ^project_id, id: ^sheet_id)
    |> where([s], is_nil(s.deleted_at))
    |> preload([:blocks, :banner_asset, avatars: :asset])
    |> Repo.one()
  end

  @doc """
  Gets a sheet with blocks and assets preloaded. Raises if not found.
  """
  @spec get_sheet!(integer(), integer()) :: Sheet.t()
  def get_sheet!(project_id, sheet_id) do
    Sheet
    |> where(project_id: ^project_id, id: ^sheet_id)
    |> where([s], is_nil(s.deleted_at))
    |> preload([:blocks, :banner_asset, avatars: :asset])
    |> Repo.one!()
  end

  @doc """
  Gets a sheet with all associations preloaded (blocks, assets, current_version).
  Returns nil if not found.
  """
  @spec get_sheet_full(integer(), integer()) :: Sheet.t() | nil
  def get_sheet_full(project_id, sheet_id) do
    Sheet
    |> where(project_id: ^project_id, id: ^sheet_id)
    |> where([s], is_nil(s.deleted_at))
    |> preload([:blocks, :banner_asset, :current_version, avatars: :asset])
    |> Repo.one()
  end

  @doc """
  Gets a sheet with all associations preloaded (blocks, assets, current_version).
  Raises if not found.
  """
  @spec get_sheet_full!(integer(), integer()) :: Sheet.t()
  def get_sheet_full!(project_id, sheet_id) do
    Sheet
    |> where(project_id: ^project_id, id: ^sheet_id)
    |> where([s], is_nil(s.deleted_at))
    |> preload([:blocks, :banner_asset, :current_version, avatars: :asset])
    |> Repo.one!()
  end

  @doc """
  Returns the sheet with its full ancestor chain (root-first).
  Returns nil if the sheet doesn't exist.
  """
  @spec get_sheet_with_ancestors(integer(), integer()) :: [Sheet.t()] | nil
  def get_sheet_with_ancestors(project_id, sheet_id) do
    case get_sheet(project_id, sheet_id) do
      nil -> nil
      sheet -> Enum.reverse(list_ancestors(sheet.id), [sheet])
    end
  end

  @doc """
  Gets a sheet with all descendants recursively loaded into `:children`.
  """
  @spec get_sheet_with_descendants(integer(), integer()) :: Sheet.t() | nil
  def get_sheet_with_descendants(project_id, sheet_id) do
    case get_sheet(project_id, sheet_id) do
      nil ->
        nil

      sheet ->
        # Load all non-deleted sheets in the project and build subtree from this sheet
        all_sheets =
          Repo.all(
            from(s in Sheet,
              where: s.project_id == ^project_id and is_nil(s.deleted_at),
              order_by: [asc: s.position, asc: s.name],
              preload: [avatars: :asset]
            )
          )

        children = SharedTree.build_tree_from_flat_list(all_sheets, sheet.id)
        %{sheet | children: children}
    end
  end

  @doc """
  Lists direct children of a sheet, ordered by position then name.
  """
  @spec get_children(integer()) :: [Sheet.t()]
  def get_children(sheet_id) do
    Repo.all(
      from(s in Sheet,
        where: s.parent_id == ^sheet_id and is_nil(s.deleted_at),
        order_by: [asc: s.position, asc: s.name],
        preload: [avatars: :asset]
      )
    )
  end

  @doc "Returns whether a sheet has at least one active direct child."
  @spec has_children?(integer()) :: boolean()
  def has_children?(sheet_id) do
    Repo.exists?(from(s in Sheet, where: s.parent_id == ^sheet_id and is_nil(s.deleted_at)))
  end

  @doc """
  Lists sheets by a list of IDs within a project, with avatar and banner preloaded.
  Used by the version viewer to build speaker data for dialogue nodes.
  """
  @spec list_sheets_by_ids(integer(), [integer()]) :: [Sheet.t()]
  def list_sheets_by_ids(_project_id, []), do: []

  def list_sheets_by_ids(project_id, ids) do
    Repo.all(
      from(s in Sheet,
        where: s.project_id == ^project_id and s.id in ^ids and is_nil(s.deleted_at),
        preload: [:banner_asset, avatars: :asset]
      )
    )
  end

  @doc """
  Lists all non-deleted sheets for a project (flat, no tree structure).
  """
  @spec list_all_sheets(integer()) :: [Sheet.t()]
  def list_all_sheets(project_id) do
    Repo.all(
      from(s in Sheet,
        where: s.project_id == ^project_id and is_nil(s.deleted_at),
        order_by: [asc: s.position, asc: s.name],
        preload: [:banner_asset, avatars: :asset]
      )
    )
  end

  @doc """
  Lists sheets that have no children (leaf nodes in the tree).
  """
  @spec list_leaf_sheets(integer()) :: [Sheet.t()]
  def list_leaf_sheets(project_id) do
    Repo.all(
      from(s in Sheet,
        where:
          s.project_id == ^project_id and
            s.id not in subquery(parent_ids_subquery(project_id)) and is_nil(s.deleted_at),
        order_by: [asc: s.position, asc: s.name],
        preload: [avatars: :asset]
      )
    )
  end

  @doc false
  @spec parent_ids_subquery(integer()) :: Ecto.Query.t()
  def parent_ids_subquery(project_id) do
    from(s in Sheet,
      where: s.project_id == ^project_id and not is_nil(s.parent_id) and is_nil(s.deleted_at),
      select: s.parent_id
    )
  end

  # =============================================================================
  # Search
  # =============================================================================

  @default_search_limit 20
  @max_deep_search_limit 50
  @max_deep_search_offset 10_000

  @doc """
  Searches sheets by name or shortcut across a pre-authorized set of projects.

  Callers OWN the authorization of `project_ids` (see `Storyarn.GlobalSearch`);
  this function never widens the set. Empty queries list the most recently
  updated sheets, mirroring `search_sheets/3` — pickers browse before typing.
  """
  @spec search_sheets_in_projects([integer()], String.t(), keyword()) :: [Sheet.t()]
  def search_sheets_in_projects(project_ids, query, opts \\ []) when is_list(project_ids) and is_binary(query) do
    limit = Keyword.get(opts, :limit, @default_search_limit)
    query_str = String.trim(query)

    cond do
      project_ids == [] ->
        []

      query_str == "" ->
        Repo.all(
          from(s in Sheet,
            where: s.project_id in ^project_ids and is_nil(s.deleted_at),
            order_by: [desc: s.updated_at, desc: s.id],
            limit: ^limit
          ),
          log: false
        )

      true ->
        search_term = "%#{SearchHelpers.sanitize_like_query(query_str)}%"

        Repo.all(
          from(s in Sheet,
            where: s.project_id in ^project_ids and is_nil(s.deleted_at),
            where: ilike(s.name, ^search_term) or ilike(s.shortcut, ^search_term),
            order_by: [asc: s.name],
            limit: ^limit
          ),
          log: false
        )
    end
  end

  @doc """
  Searches sheets by name or shortcut.
  Empty query returns most recently updated sheets.

  ## Options
    - `:limit` - Max results (default #{@default_search_limit})
    - `:offset` - Skip N results (default 0)
  """
  @spec search_sheets(integer(), String.t(), keyword()) :: [Sheet.t()]
  def search_sheets(project_id, query, opts \\ []) when is_binary(query) do
    limit = Keyword.get(opts, :limit, @default_search_limit)
    offset = Keyword.get(opts, :offset, 0)
    query_str = String.trim(query)

    if query_str == "" do
      Repo.all(
        from(s in Sheet,
          where: s.project_id == ^project_id and is_nil(s.deleted_at),
          order_by: [desc: s.updated_at],
          limit: ^limit,
          offset: ^offset
        ),
        log: false
      )
    else
      search_term = "%#{SearchHelpers.sanitize_like_query(query_str)}%"

      Repo.all(
        from(s in Sheet,
          where: s.project_id == ^project_id and is_nil(s.deleted_at),
          where: ilike(s.name, ^search_term) or ilike(s.shortcut, ^search_term),
          order_by: [asc: s.name],
          limit: ^limit,
          offset: ^offset
        ),
        log: false
      )
    end
  end

  @doc """
  Searches sheet metadata and authored content inside active blocks, tables,
  and galleries.

  The search remains scoped to one project and returns matching sheets rather
  than the individual child records that matched.

  ## Options
    - `:limit` - Max results (default #{@default_search_limit}, max #{@max_deep_search_limit})
    - `:offset` - Skip N results (default 0, max #{@max_deep_search_offset})
  """
  @spec search_sheets_deep(integer(), String.t(), keyword()) :: [Sheet.t()]
  def search_sheets_deep(project_id, query, opts \\ []) when is_binary(query) do
    limit = bounded_deep_search_limit(opts)
    offset = bounded_deep_search_offset(opts)
    query_str = String.trim(query)

    if query_str == "" do
      search_sheets(project_id, query_str, limit: limit, offset: offset)
    else
      search_term = "%#{SearchHelpers.sanitize_like_query(query_str)}%"

      Repo.all(
        from(s in Sheet,
          where: s.project_id == ^project_id and is_nil(s.deleted_at),
          where:
            ilike(s.name, ^search_term) or
              ilike(s.shortcut, ^search_term) or
              ilike(s.description, ^search_term) or
              s.id in subquery(sheet_ids_matching_blocks(project_id, search_term)) or
              s.id in subquery(sheet_ids_matching_table_columns(project_id, search_term)) or
              s.id in subquery(sheet_ids_matching_table_rows(project_id, search_term)) or
              s.id in subquery(sheet_ids_matching_gallery_images(project_id, search_term)),
          order_by: [asc: s.name, asc: s.id],
          limit: ^limit,
          offset: ^offset
        ),
        log: false
      )
    end
  end

  defp sheet_ids_matching_blocks(project_id, search_term) do
    from(b in Block,
      join: s in Sheet,
      on: s.id == b.sheet_id,
      where: s.project_id == ^project_id and is_nil(s.deleted_at) and is_nil(b.deleted_at),
      where:
        ilike(b.variable_name, ^search_term) or
          ilike(fragment("?->>'label'", b.config), ^search_term) or
          ilike(fragment("?->>'placeholder'", b.config), ^search_term) or
          ilike(fragment("?->>'content'", b.value), ^search_term) or
          fragment(
            """
            EXISTS (
              SELECT 1
              FROM jsonb_array_elements(COALESCE(?->'options', '[]'::jsonb)) AS option(item)
              WHERE CASE jsonb_typeof(option.item)
                WHEN 'string' THEN option.item #>> '{}'
                WHEN 'object' THEN COALESCE(option.item->>'value', '')
                ELSE ''
              END ILIKE ?
            )
            """,
            b.config,
            ^search_term
          ),
      select: b.sheet_id
    )
  end

  defp sheet_ids_matching_table_columns(project_id, search_term) do
    from(c in TableColumn,
      join: b in Block,
      on: b.id == c.block_id,
      join: s in Sheet,
      on: s.id == b.sheet_id,
      where: s.project_id == ^project_id and is_nil(s.deleted_at) and is_nil(b.deleted_at),
      where:
        ilike(c.name, ^search_term) or
          ilike(c.slug, ^search_term) or
          ilike(fragment("CAST(?->'options' AS TEXT)", c.config), ^search_term),
      select: b.sheet_id
    )
  end

  defp sheet_ids_matching_table_rows(project_id, search_term) do
    from(r in TableRow,
      join: b in Block,
      on: b.id == r.block_id,
      join: s in Sheet,
      on: s.id == b.sheet_id,
      where: s.project_id == ^project_id and is_nil(s.deleted_at) and is_nil(b.deleted_at),
      where:
        ilike(r.name, ^search_term) or
          ilike(r.slug, ^search_term) or
          ilike(fragment("CAST(? AS TEXT)", r.cells), ^search_term),
      select: b.sheet_id
    )
  end

  defp sheet_ids_matching_gallery_images(project_id, search_term) do
    from(i in BlockGalleryImage,
      join: b in Block,
      on: b.id == i.block_id,
      join: s in Sheet,
      on: s.id == b.sheet_id,
      where: s.project_id == ^project_id and is_nil(s.deleted_at) and is_nil(b.deleted_at),
      where: ilike(i.label, ^search_term) or ilike(i.description, ^search_term),
      select: b.sheet_id
    )
  end

  defp bounded_deep_search_limit(opts) do
    case Keyword.get(opts, :limit, @default_search_limit) do
      limit when is_integer(limit) -> limit |> max(1) |> min(@max_deep_search_limit)
      _invalid -> @default_search_limit
    end
  end

  defp bounded_deep_search_offset(opts) do
    case Keyword.get(opts, :offset, 0) do
      offset when is_integer(offset) -> offset |> max(0) |> min(@max_deep_search_offset)
      _invalid -> 0
    end
  end

  @doc """
  Finds a sheet by its unique shortcut within a project.
  Returns nil if not found or shortcut is nil.
  """
  @spec get_sheet_by_shortcut(integer(), String.t() | nil) :: Sheet.t() | nil
  def get_sheet_by_shortcut(project_id, shortcut) when is_binary(shortcut) do
    Repo.one(
      from(s in Sheet,
        where: s.project_id == ^project_id and s.shortcut == ^shortcut and is_nil(s.deleted_at),
        preload: [:blocks, avatars: :asset]
      )
    )
  end

  def get_sheet_by_shortcut(_project_id, _shortcut), do: nil

  # =============================================================================
  # Variables
  # =============================================================================

  @doc """
  Lists all variables in a project (block variables + table cell variables).
  Each entry includes sheet info, variable name, type, options, and constraints.
  """
  @spec list_project_variables(integer()) :: [map()]
  def list_project_variables(project_id) do
    list_block_variables(project_id) ++ list_table_variables(project_id)
  end

  defp list_block_variables(project_id) do
    variable_types = ~w(text rich_text number select multi_select boolean date)

    from(b in Block,
      join: s in Sheet,
      on: b.sheet_id == s.id,
      where:
        s.project_id == ^project_id and
          is_nil(s.deleted_at) and
          is_nil(b.deleted_at) and
          b.type in ^variable_types and
          b.is_constant == false and
          not is_nil(b.variable_name) and
          b.variable_name != "" and
          VariableNamespaceResolver.authoritative_namespace_owner?(s),
      select: %{
        sheet_id: s.id,
        sheet_name: s.name,
        sheet_shortcut: coalesce(s.shortcut, fragment("CAST(? AS TEXT)", s.id)),
        block_id: b.id,
        variable_name: b.variable_name,
        block_type: b.type,
        config: b.config,
        value: b.value
      },
      order_by: [asc: s.name, asc: b.position]
    )
    |> Repo.all()
    |> Enum.map(&extract_variable_constraints/1)
    |> Enum.map(&extract_variable_options/1)
    |> Enum.map(&Map.merge(&1, %{table_name: nil, row_name: nil, column_name: nil}))
  end

  defp list_table_variables(project_id) do
    variable_column_types = ~w(number text boolean select multi_select date reference formula)

    raw_vars =
      Repo.all(
        from(tc in TableColumn,
          join: b in Block,
          on: tc.block_id == b.id,
          join: s in Sheet,
          on: b.sheet_id == s.id,
          join: tr in TableRow,
          on: tr.block_id == b.id,
          where: s.project_id == ^project_id,
          where: is_nil(s.deleted_at) and is_nil(b.deleted_at),
          where: b.type == "table",
          where: tc.type in ^variable_column_types,
          where: tc.is_constant == false or tc.type == "formula",
          where: VariableNamespaceResolver.authoritative_namespace_owner?(s),
          select: %{
            sheet_id: s.id,
            sheet_name: s.name,
            sheet_shortcut: coalesce(s.shortcut, fragment("CAST(? AS TEXT)", s.id)),
            block_id: b.id,
            variable_name: fragment("? || '.' || ? || '.' || ?", b.variable_name, tr.slug, tc.slug),
            block_type: tc.type,
            config: tc.config,
            cell_value: fragment("?->?", tr.cells, tc.slug),
            table_name: b.variable_name,
            row_name: tr.slug,
            column_name: tc.slug
          },
          order_by: [asc: s.name, asc: b.position, asc: tr.position, asc: tc.position]
        )
      )

    # If any reference columns exist, load project sheets for option population
    has_references = Enum.any?(raw_vars, &(&1.block_type == "reference"))

    sheet_options =
      if has_references, do: list_sheet_options(project_id), else: []

    raw_vars
    |> Enum.map(&remap_reference_type(&1, sheet_options))
    |> Enum.map(&extract_variable_constraints/1)
    |> Enum.map(&extract_variable_options/1)
  end

  # Remaps reference columns to select/multi_select and injects sheet options
  defp remap_reference_type(%{block_type: "reference", config: config} = var, sheet_options) do
    effective_type = if config["multiple"], do: "multi_select", else: "select"
    updated_config = Map.put(config || %{}, "options", sheet_options)
    %{var | block_type: effective_type, config: updated_config}
  end

  defp remap_reference_type(var, _sheet_options), do: var

  defp extract_variable_constraints(%{block_type: "number", config: config} = var) when is_map(config),
    do: Map.put(var, :constraints, Storyarn.Sheets.Constraints.Number.extract(config))

  defp extract_variable_constraints(%{block_type: t, config: config} = var)
       when t in ["text", "rich_text"] and is_map(config),
       do: Map.put(var, :constraints, Storyarn.Sheets.Constraints.String.extract(config))

  defp extract_variable_constraints(%{block_type: t, config: config} = var)
       when t in ["select", "multi_select"] and is_map(config),
       do: Map.put(var, :constraints, Storyarn.Sheets.Constraints.Selector.extract(config))

  defp extract_variable_constraints(%{block_type: "date", config: config} = var) when is_map(config),
    do: Map.put(var, :constraints, Storyarn.Sheets.Constraints.Date.extract(config))

  defp extract_variable_constraints(%{block_type: "boolean", config: config} = var) when is_map(config),
    do: Map.put(var, :constraints, Storyarn.Sheets.Constraints.Boolean.extract(config))

  defp extract_variable_constraints(var), do: Map.put(var, :constraints, nil)

  defp extract_variable_options(var) do
    options = extract_options_from_config(var.block_type, var.config)

    var
    |> Map.put(:options, options)
    |> Map.delete(:config)
  end

  defp extract_options_from_config(type, config) when type in ["select", "multi_select"] do
    config["options"] || []
  end

  defp extract_options_from_config(_type, _config), do: nil

  @doc """
  Returns project sheets as options for reference columns.
  Each option has `"key"` (shortcut) and `"value"` (name).
  """
  @spec list_reference_options(integer()) :: [map()]
  def list_reference_options(project_id), do: list_sheet_options(project_id)

  defp list_sheet_options(project_id) do
    from(s in Sheet,
      where: s.project_id == ^project_id,
      where: is_nil(s.deleted_at),
      where: not is_nil(s.shortcut) and s.shortcut != "",
      order_by: [asc: s.name],
      select: %{name: s.name, shortcut: s.shortcut}
    )
    |> Repo.all()
    |> Enum.map(fn s -> %{"key" => s.shortcut, "value" => s.name} end)
  end

  # =============================================================================
  # Variable Value Resolution
  # =============================================================================

  @doc """
  Resolves current default values for a list of variable references.
  Returns `%{"ref" => value}` for each found variable.

  Refs can be simple (2-part: "sheet_shortcut.variable_name") or
  table (4-part: "sheet_shortcut.table_name.row_slug.column_slug").
  """
  @spec resolve_variable_values(integer(), [String.t()]) :: map()
  def resolve_variable_values(project_id, refs) when is_list(refs) do
    {simple_refs, table_refs} = classify_refs(refs)

    simple_values = resolve_simple_values(project_id, simple_refs)
    table_values = resolve_table_values(project_id, table_refs)

    Map.merge(simple_values, table_values)
  end

  defp classify_refs(refs) do
    Enum.split_with(refs, fn ref ->
      ref |> String.split(".") |> length() == 2
    end)
  end

  defp resolve_simple_values(_project_id, []), do: %{}

  defp resolve_simple_values(project_id, refs) do
    pairs = parse_simple_refs(refs)
    do_resolve_simple(project_id, pairs)
  end

  defp parse_simple_refs(refs) do
    refs
    |> Enum.map(&parse_simple_ref/1)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_simple_ref(ref) do
    case String.split(ref, ".", parts: 2) do
      [shortcut, var_name] -> {shortcut, var_name}
      _ -> nil
    end
  end

  defp do_resolve_simple(_project_id, []), do: %{}

  defp do_resolve_simple(project_id, pairs) do
    namespaces = pairs |> Enum.map(&elem(&1, 0)) |> Enum.uniq()
    namespace_ids = VariableNamespaceResolver.resolve_sheet_ids(project_id, namespaces)
    namespace_by_id = Map.new(namespace_ids, fn {namespace, id} -> {id, namespace} end)
    pair_set = MapSet.new(pairs)

    project_id
    |> query_simple_blocks(Map.keys(namespace_by_id))
    |> Repo.all()
    |> build_simple_results(pair_set, namespace_by_id)
  end

  defp query_simple_blocks(project_id, sheet_ids) do
    from(b in Block,
      join: s in Sheet,
      on: b.sheet_id == s.id,
      where:
        s.project_id == ^project_id and
          is_nil(s.deleted_at) and
          is_nil(b.deleted_at) and
          not is_nil(b.variable_name) and
          b.variable_name != "" and
          s.id in ^sheet_ids,
      select: %{
        sheet_id: s.id,
        variable_name: b.variable_name,
        value: b.value
      }
    )
  end

  defp build_simple_results(rows, pair_set, namespace_by_id) do
    Enum.reduce(rows, %{}, fn row, acc ->
      namespace = Map.fetch!(namespace_by_id, row.sheet_id)

      if MapSet.member?(pair_set, {namespace, row.variable_name}) do
        Map.put(acc, "#{namespace}.#{row.variable_name}", extract_block_value(row.value))
      else
        acc
      end
    end)
  end

  defp resolve_table_values(_project_id, []), do: %{}

  defp resolve_table_values(project_id, refs) do
    parsed = parse_table_refs(refs)
    do_resolve_table(project_id, parsed)
  end

  defp parse_table_refs(refs) do
    refs
    |> Enum.map(&parse_table_ref/1)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_table_ref(ref) do
    case String.split(ref, ".") do
      [shortcut, table_name, row_slug, col_slug] ->
        %{
          shortcut: shortcut,
          table_name: table_name,
          row_slug: row_slug,
          col_slug: col_slug,
          ref: ref
        }

      _ ->
        nil
    end
  end

  defp do_resolve_table(_project_id, []), do: %{}

  defp do_resolve_table(project_id, parsed) do
    namespaces = parsed |> Enum.map(& &1.shortcut) |> Enum.uniq()
    namespace_ids = VariableNamespaceResolver.resolve_sheet_ids(project_id, namespaces)
    namespace_by_id = Map.new(namespace_ids, fn {namespace, id} -> {id, namespace} end)
    rows = project_id |> query_table_rows(Map.keys(namespace_by_id)) |> Repo.all()

    Enum.reduce(parsed, %{}, fn entry, acc ->
      match_table_row(rows, entry, acc, namespace_by_id)
    end)
  end

  defp query_table_rows(project_id, sheet_ids) do
    from(tr in TableRow,
      join: b in Block,
      on: tr.block_id == b.id,
      join: s in Sheet,
      on: b.sheet_id == s.id,
      where:
        s.project_id == ^project_id and
          is_nil(s.deleted_at) and
          is_nil(b.deleted_at) and
          b.type == "table" and
          s.id in ^sheet_ids,
      select: %{
        sheet_id: s.id,
        table_name: b.variable_name,
        row_slug: tr.slug,
        cells: tr.cells
      }
    )
  end

  defp match_table_row(rows, entry, acc, namespace_by_id) do
    case find_matching_row(rows, entry, namespace_by_id) do
      nil -> acc
      row -> Map.put(acc, entry.ref, resolve_cell_value(row.cells, entry.col_slug))
    end
  end

  defp find_matching_row(rows, entry, namespace_by_id) do
    Enum.find(rows, fn r ->
      Map.fetch!(namespace_by_id, r.sheet_id) == entry.shortcut and r.table_name == entry.table_name and
        r.row_slug == entry.row_slug
    end)
  end

  # Resolve a cell value — if it's a formula map, compute it inline using same-row cells
  defp resolve_cell_value(cells, col_slug) do
    case cells[col_slug] do
      %{"expression" => expr, "bindings" => bindings} when is_binary(expr) and expr != "" ->
        compute_formula_cell(expr, bindings, cells)

      other ->
        other
    end
  end

  defp compute_formula_cell(expression, bindings, row_cells) do
    values =
      Map.new(bindings || %{}, fn {symbol, binding} ->
        value =
          case binding do
            %{"type" => "same_row", "column_slug" => slug} ->
              MapUtils.parse_to_number(row_cells[slug])

            %{"type" => "variable", "ref" => _ref} ->
              # Cross-table variable refs in nested formulas fall back to 0
              # (the outer formula resolver handles cross-table resolution)
              0.0

            _ ->
              0.0
          end

        {symbol, value}
      end)

    case FormulaEngine.compute(expression, values) do
      {:ok, result} -> MapUtils.format_number_result(result)
      {:error, _} -> nil
    end
  end

  defp extract_block_value(%{"content" => content}), do: content
  defp extract_block_value(_), do: nil

  # =============================================================================
  # Reference Validation
  # =============================================================================

  @doc false
  @spec search_reference_flows(integer(), String.t(), keyword()) :: [FlowRecord.t()]
  def search_reference_flows(project_id, query, opts \\ []) when is_binary(query) do
    limit = Keyword.get(opts, :limit, 25)
    offset = Keyword.get(opts, :offset, 0)
    query = String.trim(query)

    base =
      from(flow in FlowRecord,
        where: flow.project_id == ^project_id and is_nil(flow.deleted_at)
      )

    if query == "" do
      Repo.all(
        from(flow in base,
          order_by: [desc: flow.updated_at],
          limit: ^limit,
          offset: ^offset
        ),
        log: false
      )
    else
      search_term = "%#{SearchHelpers.sanitize_like_query(query)}%"

      Repo.all(
        from(flow in base,
          where: ilike(flow.name, ^search_term) or ilike(flow.shortcut, ^search_term),
          order_by: [asc: flow.name],
          limit: ^limit,
          offset: ^offset
        ),
        log: false
      )
    end
  end

  @doc false
  @spec get_reference_flow(integer(), integer()) :: FlowRecord.t() | nil
  def get_reference_flow(project_id, flow_id) do
    Repo.one(
      from(flow in FlowRecord,
        where:
          flow.project_id == ^project_id and flow.id == ^flow_id and
            is_nil(flow.deleted_at)
      )
    )
  end

  @doc """
  Validates that a reference target (sheet or flow) exists in the project.
  Returns `{:ok, entity}` or `{:error, reason}`.
  """
  @spec validate_reference_target(String.t(), integer(), integer()) ::
          {:ok, Sheet.t() | FlowRecord.t()} | {:error, :not_found | :invalid_type}
  def validate_reference_target(target_type, target_id, project_id) do
    case target_type do
      "sheet" ->
        case get_sheet(project_id, target_id) do
          nil -> {:error, :not_found}
          sheet -> {:ok, sheet}
        end

      "flow" ->
        case get_reference_flow(project_id, target_id) do
          nil -> {:error, :not_found}
          flow -> {:ok, flow}
        end

      _ ->
        {:error, :invalid_type}
    end
  end

  # =============================================================================
  # Inheritance Queries
  # =============================================================================

  @doc """
  Loads a sheet with its blocks split into inherited and own groups.
  Returns `{inherited_groups, own_blocks}` where inherited_groups is
  `[%{source_sheet: sheet, blocks: [block, ...]}]`.
  """
  @spec get_sheet_blocks_grouped(integer()) ::
          {[%{source_sheet: Sheet.t(), blocks: [Block.t()]}], [Block.t()]}
  def get_sheet_blocks_grouped(sheet_id) do
    blocks =
      Repo.all(
        from(b in Block,
          where: b.sheet_id == ^sheet_id and is_nil(b.deleted_at),
          # `id` last is not decoration: two blocks can share a position (delete a
          # block, reorder the survivors, restore it from its snapshot) and block
          # ORDER decides which one an `invalid_block_layout` finding names.
          # Without it the answer is whatever plan PostgreSQL picked.
          order_by: [asc: b.position, asc: b.id],
          preload: [:inherited_from_block]
        )
      )

    # Batch-load all source sheets to avoid N+1
    source_sheet_ids =
      blocks
      |> Enum.filter(&Block.inherited?/1)
      |> Enum.map(&inherited_source_sheet_id/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    source_sheets_by_id =
      if source_sheet_ids == [] do
        %{}
      else
        from(s in Sheet,
          where: s.id in ^source_sheet_ids and is_nil(s.deleted_at),
          preload: [avatars: :asset]
        )
        |> Repo.all()
        |> Map.new(fn s -> {s.id, s} end)
      end

    group_blocks(blocks, source_sheets_by_id)
  end

  @doc """
  Loads every active block of a project, grouped per sheet exactly as
  `get_sheet_blocks_grouped/1` groups one sheet's.

  Two queries for a whole project instead of two per sheet. `sheets` supplies the
  inheritance sources, so a sheet whose source sheet is absent from it drops its
  inherited blocks — the same way the per-sheet loader drops blocks whose source
  sheet was deleted.

  Returns `%{sheet_id => {inherited_groups, own_blocks}}`, with an entry for every
  sheet in `sheets`.
  """
  @spec list_project_blocks_grouped([Sheet.t()]) ::
          %{integer() => {[%{source_sheet: Sheet.t(), blocks: [Block.t()]}], [Block.t()]}}
  def list_project_blocks_grouped([]), do: %{}

  def list_project_blocks_grouped(sheets) do
    sheet_ids = Enum.map(sheets, & &1.id)
    source_sheets_by_id = Map.new(sheets, &{&1.id, &1})

    blocks_by_sheet =
      from(b in Block,
        where: b.sheet_id in ^sheet_ids and is_nil(b.deleted_at),
        # Same tiebreak as `get_sheet_blocks_grouped/1`, and for the same reason —
        # the two must slice the same sheet into the same block order or the sweep
        # and the editor blame different blocks for one broken column group.
        order_by: [asc: b.sheet_id, asc: b.position, asc: b.id],
        preload: [:inherited_from_block]
      )
      |> Repo.all()
      |> Enum.group_by(& &1.sheet_id)

    Map.new(sheet_ids, fn sheet_id ->
      {sheet_id, group_blocks(Map.get(blocks_by_sheet, sheet_id, []), source_sheets_by_id)}
    end)
  end

  @doc """
  Splits one sheet's blocks into inherited groups and own blocks.

  Inherited blocks whose source block or source sheet is gone are dropped: they
  are reported as inheritance issues, not rendered as fields.
  """
  @spec group_blocks([Block.t()], %{integer() => Sheet.t()}) ::
          {[%{source_sheet: Sheet.t(), blocks: [Block.t()]}], [Block.t()]}
  def group_blocks(blocks, source_sheets_by_id) do
    {inherited, own} = Enum.split_with(blocks, &Block.inherited?/1)

    inherited_groups =
      inherited
      |> Enum.group_by(&inherited_source_sheet_id/1)
      |> Enum.reject(fn {source_sheet_id, _blocks} -> is_nil(source_sheet_id) end)
      |> Enum.map(fn {source_sheet_id, blocks} ->
        %{source_sheet: Map.get(source_sheets_by_id, source_sheet_id), blocks: blocks}
      end)
      |> Enum.reject(fn group -> is_nil(group.source_sheet) end)

    {inherited_groups, own}
  end

  defp inherited_source_sheet_id(%Block{inherited_from_block: %Block{sheet_id: sheet_id}}), do: sheet_id
  defp inherited_source_sheet_id(_block), do: nil

  @doc """
  Lists all blocks with `scope: "children"` for a sheet.
  """
  @spec list_inheritable_blocks(integer()) :: [Block.t()]
  def list_inheritable_blocks(sheet_id) do
    Repo.all(
      from(b in Block,
        where: b.sheet_id == ^sheet_id and b.scope == "children" and is_nil(b.deleted_at),
        # Positions tie, so `id` decides the order inherited instances are created
        # in rather than the plan.
        order_by: [asc: b.position, asc: b.id]
      )
    )
  end

  @doc """
  Lists all instance blocks for a given parent block ID.
  """
  @spec list_inherited_instances(integer()) :: [Block.t()]
  def list_inherited_instances(parent_block_id) do
    Repo.all(
      from(b in Block, where: b.inherited_from_block_id == ^parent_block_id and is_nil(b.deleted_at), preload: [:sheet])
    )
  end

  # =============================================================================
  # Trash
  # =============================================================================

  @doc """
  Lists all soft-deleted sheets for the trash view.
  """
  @spec list_trashed_sheets(integer()) :: [Sheet.t()]
  def list_trashed_sheets(project_id) do
    Repo.all(
      from(s in Sheet,
        where: s.project_id == ^project_id and not is_nil(s.deleted_at),
        order_by: [desc: s.deleted_at],
        preload: [avatars: :asset]
      )
    )
  end

  @doc """
  Gets a single trashed sheet for restore/permanent-delete operations.
  """
  @spec get_trashed_sheet(integer(), integer()) :: Sheet.t() | nil
  def get_trashed_sheet(project_id, sheet_id) do
    Sheet
    |> where(project_id: ^project_id, id: ^sheet_id)
    |> where([s], not is_nil(s.deleted_at))
    |> preload(avatars: :asset)
    |> Repo.one()
  end

  # =============================================================================
  # Ancestor Chain
  # =============================================================================

  @doc """
  Returns the ancestor chain for a sheet (child-first order: nearest parent first).
  Uses a recursive CTE for O(1) queries regardless of tree depth.
  """
  @spec list_ancestors(integer()) :: [Sheet.t()]
  def list_ancestors(sheet_id) do
    anchor =
      from(s in "sheets",
        where: s.id == ^sheet_id and is_nil(s.deleted_at),
        select: %{parent_id: s.parent_id, depth: 0}
      )

    recursion =
      from(s in "sheets",
        join: a in "ancestors",
        on: s.id == a.parent_id,
        where: is_nil(s.deleted_at),
        select: %{parent_id: s.parent_id, depth: a.depth + 1}
      )

    cte_query = union_all(anchor, ^recursion)

    # Get ordered ancestor IDs from the CTE
    ancestor_ids =
      from("ancestors")
      |> recursive_ctes(true)
      |> with_cte("ancestors", as: ^cte_query)
      |> where([a], not is_nil(a.parent_id))
      |> select([a], a.parent_id)
      |> Repo.all()

    if ancestor_ids == [] do
      []
    else
      # Load full structs with preloads in a single query
      ancestors_map =
        from(s in Sheet,
          where: s.id in ^ancestor_ids and is_nil(s.deleted_at),
          preload: [avatars: :asset]
        )
        |> Repo.all()
        |> Map.new(fn s -> {s.id, s} end)

      # Reconstruct order from CTE result (child-first)
      ancestor_ids
      |> Enum.map(&Map.get(ancestors_map, &1))
      |> Enum.reject(&is_nil/1)
    end
  end

  # =============================================================================
  # Export / Import helpers
  # =============================================================================

  @doc """
  Returns the project_id for a sheet by its ID.
  Used by the Localization TextExtractor to resolve project scope.
  """
  def get_sheet_project_id(sheet_id) do
    Repo.one(from(s in Sheet, where: s.id == ^sheet_id, select: s.project_id))
  end

  @doc """
  Lists all non-deleted sheets with blocks, table_columns, and table_rows preloaded.
  Used by the export DataCollector.
  """
  def list_sheets_for_export(project_id, opts \\ []) do
    filter_ids = Keyword.get(opts, :filter_ids, :all)

    blocks_query =
      from(b in Block,
        where: is_nil(b.deleted_at),
        preload: [:table_columns, :table_rows],
        # An export is a file people diff. Two blocks at one position would
        # otherwise swap places between runs with nothing having changed.
        order_by: [asc: b.position, asc: b.id]
      )

    query =
      from(s in Sheet,
        where: s.project_id == ^project_id and is_nil(s.deleted_at),
        preload: [blocks: ^blocks_query, avatars: :asset],
        order_by: [asc: s.position, asc: s.name]
      )

    query
    |> maybe_filter_export_ids(filter_ids)
    |> Repo.all()
  end

  @doc """
  Counts non-deleted sheets for a project.
  """
  def count_sheets(project_id) do
    Repo.aggregate(from(s in Sheet, where: s.project_id == ^project_id and is_nil(s.deleted_at)), :count)
  end

  @doc """
  Lists active project sheets with no preloads, in tree order.

  For project-wide sweeps that need sheet identity and tree shape (`parent_id`,
  `hidden_inherited_block_ids`) but never render a sheet — `list_all_sheets/1`
  costs three extra queries for avatars and banners nothing there looks at.
  """
  @spec list_sheets_unpreloaded(integer()) :: [Sheet.t()]
  def list_sheets_unpreloaded(project_id) do
    Repo.all(
      from(s in Sheet,
        where: s.project_id == ^project_id and is_nil(s.deleted_at),
        order_by: [asc: s.position, asc: s.name]
      )
    )
  end

  @doc """
  Lists all non-deleted blocks for the given sheet IDs.
  Used by the Localization TextExtractor for bulk extraction.
  """
  def list_blocks_for_sheet_ids(sheet_ids) do
    Repo.all(from(b in Block, where: b.sheet_id in ^sheet_ids))
  end

  @doc """
  Lists brief sheet data (id, name, shortcut) for a project.
  Used by the export Validator for orphan sheet detection.
  """
  def list_sheets_brief(project_id, opts \\ []) do
    filter_ids = Keyword.get(opts, :filter_ids, :all)

    from(s in Sheet,
      where: s.project_id == ^project_id and is_nil(s.deleted_at),
      select: %{id: s.id, name: s.name, shortcut: s.shortcut}
    )
    |> maybe_filter_export_ids(filter_ids)
    |> Repo.all()
  end

  @doc """
  Lists existing shortcuts for sheets in a project.
  Used by the import parser for conflict detection.
  """
  def list_shortcuts(project_id) do
    from(s in Sheet,
      where: s.project_id == ^project_id and is_nil(s.deleted_at),
      select: s.shortcut
    )
    |> Repo.all()
    |> MapSet.new()
  end

  @doc """
  Detects shortcut conflicts between imported sheets and existing ones.
  """
  def detect_shortcut_conflicts(project_id, shortcuts) when is_list(shortcuts) do
    if shortcuts == [] do
      []
    else
      Repo.all(
        from(s in Sheet,
          where: s.project_id == ^project_id and s.shortcut in ^shortcuts and is_nil(s.deleted_at),
          select: s.shortcut
        )
      )
    end
  end

  @doc """
  Soft-deletes existing sheets with the given shortcut (for overwrite import strategy).
  """
  def soft_delete_by_shortcut(project_id, shortcut) do
    now = Storyarn.Shared.TimeHelpers.now()

    Repo.update_all(
      from(s in Sheet, where: s.project_id == ^project_id and s.shortcut == ^shortcut and is_nil(s.deleted_at)),
      set: [deleted_at: now]
    )
  end

  @doc """
  Returns stale variable reference data for flow nodes.
  Joins variable_references with flow_nodes, flows, blocks, and sheets
  to detect staleness via SQL comparison of stored vs current names.
  Used by the project integrity workflow for stale reference detection.
  """
  def check_stale_flow_node_variable_references(block_id, project_id) do
    Repo.all(
      from(vr in VariableReferenceRecord,
        join: n in FlowNodeRecord,
        on: vr.source_type == "flow_node" and n.id == vr.source_id,
        join: f in FlowRecord,
        on: f.id == n.flow_id,
        join: b in Block,
        on: b.id == vr.block_id,
        join: s in Sheet,
        on: s.id == b.sheet_id,
        where: vr.block_id == ^block_id,
        where: f.project_id == ^project_id,
        where: is_nil(f.deleted_at),
        where: is_nil(n.deleted_at),
        where: is_nil(s.deleted_at),
        where: is_nil(b.deleted_at),
        select: %{
          source_type: vr.source_type,
          kind: vr.kind,
          flow_id: f.id,
          flow_name: f.name,
          flow_shortcut: f.shortcut,
          node_id: n.id,
          node_type: n.type,
          node_data: n.data,
          source_sheet: vr.source_sheet,
          source_variable: vr.source_variable,
          stale:
            not VariableNamespaceResolver.authoritative_namespace_owner?(s) or
              fragment(
                """
                CASE WHEN ? = 'table' THEN
                  ? != ? OR NOT EXISTS (
                    SELECT 1 FROM table_rows tr
                    JOIN table_columns tc ON tc.block_id = tr.block_id
                    WHERE tr.block_id = ?
                      AND ? = ? || '.' || tr.slug || '.' || tc.slug
                  )
                ELSE
                  ? != ? OR ? != ?
                END
                """,
                b.type,
                vr.source_sheet,
                fragment("COALESCE(?, CAST(? AS TEXT))", s.shortcut, s.id),
                b.id,
                vr.source_variable,
                b.variable_name,
                vr.source_sheet,
                fragment("COALESCE(?, CAST(? AS TEXT))", s.shortcut, s.id),
                vr.source_variable,
                b.variable_name
              )
        },
        order_by: [asc: vr.kind, asc: f.name]
      )
    )
  end

  @doc """
  Returns variable references with current block info for stale repair.
  Joins variable_references with flow_nodes, flows, blocks, and sheets.
  Used by the project integrity workflow for stale reference repair.
  """
  def list_variable_refs_with_block_info_for_repair(project_id) do
    Repo.all(
      from(vr in VariableReferenceRecord,
        join: n in FlowNodeRecord,
        on: vr.source_type == "flow_node" and n.id == vr.source_id,
        join: f in FlowRecord,
        on: f.id == n.flow_id,
        join: b in Block,
        on: b.id == vr.block_id,
        join: s in Sheet,
        on: s.id == b.sheet_id,
        where: f.project_id == ^project_id,
        where: is_nil(f.deleted_at),
        where: is_nil(s.deleted_at),
        where: is_nil(b.deleted_at),
        where: VariableNamespaceResolver.authoritative_namespace_owner?(s),
        select: %{
          node_id: n.id,
          node_type: n.type,
          node_data: n.data,
          kind: vr.kind,
          block_id: vr.block_id,
          current_shortcut: coalesce(s.shortcut, fragment("CAST(? AS TEXT)", s.id)),
          current_variable: b.variable_name,
          source_sheet: vr.source_sheet,
          source_variable: vr.source_variable
        }
      )
    )
  end

  @type stale_node_variable_refs_by_flow :: %{
          integer() => %{integer() => MapSet.t(String.t())}
        }

  @doc """
  Stale variable references for MANY flows at once, keyed by flow and node.

  The per-flow pair costs two queries each, so a project-wide sweep over N flows
  would otherwise pay 2N. This returns the same information in two queries total
  while retaining the original full reference needed to distinguish exportable
  expressions from draft rows on the same node.
  """
  @spec list_stale_node_variable_refs_by_flow([integer()]) ::
          stale_node_variable_refs_by_flow()
  def list_stale_node_variable_refs_by_flow([]), do: %{}

  def list_stale_node_variable_refs_by_flow(flow_ids) do
    regular = stale_regular_refs(flow_ids)
    table = stale_table_refs(flow_ids)

    Enum.reduce(regular ++ table, %{}, fn
      {flow_id, node_id, source_sheet, source_variable}, refs_by_flow ->
        full_ref = "#{source_sheet}.#{source_variable}"

        Map.update(
          refs_by_flow,
          flow_id,
          %{node_id => MapSet.new([full_ref])},
          &Map.update(&1, node_id, MapSet.new([full_ref]), fn refs ->
            MapSet.put(refs, full_ref)
          end)
        )
    end)
  end

  @doc """
  Stale node ids for MANY flows at once, keyed by flow — the project-wide sweep.

  This compatibility view is derived from
  `list_stale_node_variable_refs_by_flow/1`, preserving the same two-query cost.
  """
  @spec list_stale_node_ids_by_flow([integer()]) :: %{integer() => MapSet.t()}
  def list_stale_node_ids_by_flow(flow_ids) do
    flow_ids
    |> list_stale_node_variable_refs_by_flow()
    |> Map.new(fn {flow_id, refs_by_node} ->
      {flow_id, refs_by_node |> Map.keys() |> MapSet.new()}
    end)
  end

  # A reference is stale when the shortcut it was written against no longer names
  # its sheet, or the variable no longer carries its name.
  defp stale_regular_refs(flow_ids) do
    Repo.all(
      from(vr in VariableReferenceRecord,
        join: n in FlowNodeRecord,
        on: vr.source_type == "flow_node" and n.id == vr.source_id,
        join: b in Block,
        on: b.id == vr.block_id,
        join: s in Sheet,
        on: s.id == b.sheet_id,
        where: n.flow_id in ^flow_ids,
        where: is_nil(s.deleted_at),
        where: is_nil(b.deleted_at),
        where: b.type != "table",
        where:
          not VariableNamespaceResolver.authoritative_namespace_owner?(s) or
            vr.source_sheet != coalesce(s.shortcut, fragment("CAST(? AS TEXT)", s.id)) or
            vr.source_variable != b.variable_name,
        distinct: true,
        select: {n.flow_id, n.id, vr.source_sheet, vr.source_variable}
      )
    )
  end

  # A table reference spells its own path — `variable.row_slug.column_slug` — so
  # its second staleness cause is a row or column that no longer exists, which no
  # column on `variable_references` can answer. Hence the correlated subquery.
  defp stale_table_refs(flow_ids) do
    table_cell_exists =
      from(tr in TableRow,
        join: tc in TableColumn,
        on: tc.block_id == tr.block_id,
        where:
          parent_as(:vr).source_variable ==
            fragment(
              "? || '.' || ? || '.' || ?",
              parent_as(:block).variable_name,
              tr.slug,
              tc.slug
            ),
        select: 1
      )

    Repo.all(
      from(vr in VariableReferenceRecord,
        as: :vr,
        join: n in FlowNodeRecord,
        on: vr.source_type == "flow_node" and n.id == vr.source_id,
        join: b in Block,
        as: :block,
        on: b.id == vr.block_id,
        join: s in Sheet,
        on: s.id == b.sheet_id,
        where: n.flow_id in ^flow_ids,
        where: is_nil(s.deleted_at),
        where: is_nil(b.deleted_at),
        where: b.type == "table",
        where:
          not VariableNamespaceResolver.authoritative_namespace_owner?(s) or
            vr.source_sheet != coalesce(s.shortcut, fragment("CAST(? AS TEXT)", s.id)) or
            not exists(table_cell_exists),
        distinct: true,
        select: {n.flow_id, n.id, vr.source_sheet, vr.source_variable}
      )
    )
  end

  @doc """
  Stale regular (non-table) node IDs in ONE flow, for the flow editor.

  The batched builder restricted to a single flow rather than a second copy of the
  same SQL: two hand-maintained spellings of one rule drift, and nothing compares
  them at runtime — the editor reads one, the dashboard the other.
  """
  @spec list_stale_regular_node_ids(integer()) :: MapSet.t()
  def list_stale_regular_node_ids(flow_id) do
    [flow_id] |> stale_regular_refs() |> node_ids_for_flow(flow_id)
  end

  @doc """
  Stale table node IDs in ONE flow, for the flow editor.

  Same restriction of `stale_table_refs/1`, for the same reason as
  `list_stale_regular_node_ids/1`.
  """
  @spec list_stale_table_node_ids(integer()) :: MapSet.t()
  def list_stale_table_node_ids(flow_id) do
    [flow_id] |> stale_table_refs() |> node_ids_for_flow(flow_id)
  end

  defp node_ids_for_flow(refs, flow_id) do
    for {^flow_id, node_id, _source_sheet, _source_variable} <- refs,
        into: MapSet.new(),
        do: node_id
  end

  @doc """
  Resolves a block ID by sheet shortcut and variable name.
  Returns the block ID or nil if not found.

  The query follows the canonical variable catalog contract: constants and
  unsupported block types are not runtime variables.
  """
  def resolve_block_id_by_variable(project_id, sheet_shortcut, variable_name) do
    variable_types = VariableCatalog.regular_variable_types()

    case VariableNamespaceResolver.resolve_sheet_id(project_id, sheet_shortcut) do
      nil ->
        nil

      sheet_id ->
        Repo.one(
          from(b in Block,
            join: s in Sheet,
            on: s.id == b.sheet_id,
            where: s.project_id == ^project_id and s.id == ^sheet_id,
            where: b.variable_name == ^variable_name,
            where: b.type in ^variable_types,
            where: b.is_constant == false,
            where: is_nil(s.deleted_at),
            where: is_nil(b.deleted_at),
            select: b.id,
            limit: 1
          )
        )
    end
  end

  @doc """
  Resolves a table block ID by sheet shortcut, table name, row slug, and column slug.
  Returns the block ID or nil if not found.

  The selected column must satisfy the same type and constant rules as the
  canonical variable catalog.
  """
  def resolve_table_block_id_by_variable(project_id, sheet_shortcut, table_name, row_slug, column_slug) do
    variable_types = VariableCatalog.table_variable_types()
    constant_variable_types = VariableCatalog.constant_table_variable_types()

    case VariableNamespaceResolver.resolve_sheet_id(project_id, sheet_shortcut) do
      nil ->
        nil

      sheet_id ->
        Repo.one(
          from(b in Block,
            join: s in Sheet,
            on: s.id == b.sheet_id,
            join: tr in TableRow,
            on: tr.block_id == b.id,
            join: tc in TableColumn,
            on: tc.block_id == b.id,
            where: s.project_id == ^project_id and s.id == ^sheet_id,
            where: b.variable_name == ^table_name,
            where: b.type == "table",
            where: tc.type in ^variable_types,
            where: tc.is_constant == false or tc.type in ^constant_variable_types,
            where: tr.slug == ^row_slug,
            where: tc.slug == ^column_slug,
            where: is_nil(s.deleted_at),
            where: is_nil(b.deleted_at),
            select: b.id,
            limit: 1
          )
        )
    end
  end

  @doc """
  Lists sheet IDs that are referenced through variable_references in a project.
  Joins VariableReference -> Block -> Sheet to find all referenced sheet IDs.
  Used by the export Validator for orphan sheet detection.
  """
  def list_variable_referenced_sheet_ids(project_id) do
    from(vr in VariableReferenceRecord,
      join: b in Block,
      on: vr.block_id == b.id,
      join: s in Sheet,
      on: b.sheet_id == s.id,
      where: s.project_id == ^project_id,
      select: s.id
    )
    |> Repo.all()
    |> MapSet.new()
  end

  @doc """
  Lists sheets using a specific asset as their avatar.
  Used by the Assets context for usage tracking.
  """
  def list_sheets_using_asset_as_avatar(project_id, asset_id) do
    alias Storyarn.Sheets.SheetAvatar

    Repo.all(
      from(s in Sheet,
        join: sa in SheetAvatar,
        on: sa.sheet_id == s.id and sa.asset_id == ^asset_id,
        where: s.project_id == ^project_id,
        where: is_nil(s.deleted_at),
        distinct: true,
        order_by: [asc: s.name]
      )
    )
  end

  @doc """
  Lists sheets using a specific asset as their banner.
  Used by the Assets context for usage tracking.
  """
  def list_sheets_using_asset_as_banner(project_id, asset_id) do
    Repo.all(
      from(s in Sheet,
        where: s.project_id == ^project_id,
        where: is_nil(s.deleted_at),
        where: s.banner_asset_id == ^asset_id,
        order_by: [asc: s.name]
      )
    )
  end

  @doc """
  Lists sheet IDs referenced by scene pins in a project.
  Used by the export Validator for orphan sheet detection.
  Delegates to the Scenes context to avoid cross-context schema queries.
  """
  def list_pin_referenced_sheet_ids(project_id) do
    Storyarn.Scenes.list_pin_referenced_sheet_ids(project_id)
  end

  defp maybe_filter_export_ids(query, :all), do: query

  defp maybe_filter_export_ids(query, ids) when is_list(ids) do
    from(q in query, where: q.id in ^ids)
  end
end

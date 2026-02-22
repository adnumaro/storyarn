defmodule Storyarn.Sheets.SheetQueries do
  @moduledoc """
  Read-only query functions for sheets.

  Provides all sheet retrieval, listing, search, and tree traversal operations.
  Mutation operations remain in `SheetCrud`.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Repo
  alias Storyarn.Shared.SearchHelpers
  alias Storyarn.Sheets.{Block, Sheet, TableColumn, TableRow}

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
      from(s in Sheet,
        where: s.project_id == ^project_id and is_nil(s.deleted_at),
        order_by: [asc: s.position, asc: s.name],
        preload: [:avatar_asset]
      )
      |> Repo.all()

    build_tree(all_sheets, nil)
  end

  @doc """
  Gets a sheet with blocks and assets preloaded. Returns nil if not found.
  """
  @spec get_sheet(integer(), integer()) :: Sheet.t() | nil
  def get_sheet(project_id, sheet_id) do
    Sheet
    |> where(project_id: ^project_id, id: ^sheet_id)
    |> where([s], is_nil(s.deleted_at))
    |> preload([:blocks, :avatar_asset, :banner_asset])
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
    |> preload([:blocks, :avatar_asset, :banner_asset])
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
    |> preload([:blocks, :avatar_asset, :banner_asset, :current_version])
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
    |> preload([:blocks, :avatar_asset, :banner_asset, :current_version])
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
      sheet -> Enum.reverse(list_ancestors(sheet.id)) ++ [sheet]
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
          from(s in Sheet,
            where: s.project_id == ^project_id and is_nil(s.deleted_at),
            order_by: [asc: s.position, asc: s.name],
            preload: [:avatar_asset]
          )
          |> Repo.all()

        grouped = Enum.group_by(all_sheets, & &1.parent_id)
        %{sheet | children: build_subtree(grouped, sheet.id)}
    end
  end

  @doc """
  Lists direct children of a sheet, ordered by position then name.
  """
  @spec get_children(integer()) :: [Sheet.t()]
  def get_children(sheet_id) do
    from(s in Sheet,
      where: s.parent_id == ^sheet_id and is_nil(s.deleted_at),
      order_by: [asc: s.position, asc: s.name],
      preload: [:avatar_asset]
    )
    |> Repo.all()
  end

  @doc """
  Lists all non-deleted sheets for a project (flat, no tree structure).
  """
  @spec list_all_sheets(integer()) :: [Sheet.t()]
  def list_all_sheets(project_id) do
    from(s in Sheet,
      where: s.project_id == ^project_id and is_nil(s.deleted_at),
      order_by: [asc: s.position, asc: s.name],
      preload: [:avatar_asset]
    )
    |> Repo.all()
  end

  @doc """
  Lists sheets that have no children (leaf nodes in the tree).
  """
  @spec list_leaf_sheets(integer()) :: [Sheet.t()]
  def list_leaf_sheets(project_id) do
    parent_ids_subquery =
      from(s in Sheet,
        where: s.project_id == ^project_id and not is_nil(s.parent_id) and is_nil(s.deleted_at),
        select: s.parent_id
      )

    from(s in Sheet,
      where:
        s.project_id == ^project_id and s.id not in subquery(parent_ids_subquery) and
          is_nil(s.deleted_at),
      order_by: [asc: s.position, asc: s.name],
      preload: [:avatar_asset]
    )
    |> Repo.all()
  end

  # =============================================================================
  # Search
  # =============================================================================

  @doc """
  Searches sheets by name or shortcut. Returns up to 10 results.
  Empty query returns most recently updated sheets.
  """
  @spec search_sheets(integer(), String.t()) :: [Sheet.t()]
  def search_sheets(project_id, query) when is_binary(query) do
    query = String.trim(query)

    if query == "" do
      from(s in Sheet,
        where: s.project_id == ^project_id and is_nil(s.deleted_at),
        order_by: [desc: s.updated_at],
        limit: 10
      )
      |> Repo.all()
    else
      search_term = "%#{SearchHelpers.sanitize_like_query(query)}%"

      from(s in Sheet,
        where: s.project_id == ^project_id and is_nil(s.deleted_at),
        where: ilike(s.name, ^search_term) or ilike(s.shortcut, ^search_term),
        order_by: [asc: s.name],
        limit: 10
      )
      |> Repo.all()
    end
  end

  @doc """
  Finds a sheet by its unique shortcut within a project.
  Returns nil if not found or shortcut is nil.
  """
  @spec get_sheet_by_shortcut(integer(), String.t() | nil) :: Sheet.t() | nil
  def get_sheet_by_shortcut(project_id, shortcut) when is_binary(shortcut) do
    from(s in Sheet,
      where: s.project_id == ^project_id and s.shortcut == ^shortcut and is_nil(s.deleted_at),
      preload: [:blocks, :avatar_asset]
    )
    |> Repo.one()
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
          not is_nil(b.variable_name) and
          b.variable_name != "" and
          b.is_constant == false,
      select: %{
        sheet_id: s.id,
        sheet_name: s.name,
        sheet_shortcut: coalesce(s.shortcut, fragment("CAST(? AS TEXT)", s.id)),
        block_id: b.id,
        variable_name: b.variable_name,
        block_type: b.type,
        config: b.config
      },
      order_by: [asc: s.name, asc: b.position]
    )
    |> Repo.all()
    |> Enum.map(&extract_variable_constraints/1)
    |> Enum.map(&extract_variable_options/1)
    |> Enum.map(&Map.merge(&1, %{table_name: nil, row_name: nil, column_name: nil}))
  end

  defp list_table_variables(project_id) do
    variable_column_types = ~w(number text boolean select multi_select date reference)

    raw_vars =
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
        where: tc.is_constant == false,
        where: tc.type in ^variable_column_types,
        select: %{
          sheet_id: s.id,
          sheet_name: s.name,
          sheet_shortcut: coalesce(s.shortcut, fragment("CAST(? AS TEXT)", s.id)),
          block_id: b.id,
          variable_name: fragment("? || '.' || ? || '.' || ?", b.variable_name, tr.slug, tc.slug),
          block_type: tc.type,
          config: tc.config,
          table_name: b.variable_name,
          row_name: tr.slug,
          column_name: tc.slug
        },
        order_by: [asc: s.name, asc: b.position, asc: tr.position, asc: tc.position]
      )
      |> Repo.all()

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

  defp extract_variable_constraints(%{block_type: "number", config: config} = var)
       when is_map(config),
       do: Map.put(var, :constraints, Storyarn.Sheets.Constraints.Number.extract(config))

  defp extract_variable_constraints(%{block_type: t, config: config} = var)
       when t in ["text", "rich_text"] and is_map(config),
       do: Map.put(var, :constraints, Storyarn.Sheets.Constraints.String.extract(config))

  defp extract_variable_constraints(%{block_type: t, config: config} = var)
       when t in ["select", "multi_select"] and is_map(config),
       do: Map.put(var, :constraints, Storyarn.Sheets.Constraints.Selector.extract(config))

  defp extract_variable_constraints(%{block_type: "date", config: config} = var)
       when is_map(config),
       do: Map.put(var, :constraints, Storyarn.Sheets.Constraints.Date.extract(config))

  defp extract_variable_constraints(%{block_type: "boolean", config: config} = var)
       when is_map(config),
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
    shortcuts = pairs |> Enum.map(&elem(&1, 0)) |> Enum.uniq()
    pair_set = MapSet.new(pairs)

    query_simple_blocks(project_id, shortcuts)
    |> Repo.all()
    |> build_simple_results(pair_set)
  end

  defp query_simple_blocks(project_id, shortcuts) do
    from(b in Block,
      join: s in Sheet,
      on: b.sheet_id == s.id,
      where:
        s.project_id == ^project_id and
          is_nil(s.deleted_at) and
          is_nil(b.deleted_at) and
          not is_nil(b.variable_name) and
          b.variable_name != "" and
          coalesce(s.shortcut, fragment("CAST(? AS TEXT)", s.id)) in ^shortcuts,
      select: %{
        shortcut: coalesce(s.shortcut, fragment("CAST(? AS TEXT)", s.id)),
        variable_name: b.variable_name,
        value: b.value
      }
    )
  end

  defp build_simple_results(rows, pair_set) do
    Enum.reduce(rows, %{}, fn row, acc ->
      if MapSet.member?(pair_set, {row.shortcut, row.variable_name}) do
        Map.put(acc, "#{row.shortcut}.#{row.variable_name}", extract_block_value(row.value))
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
    shortcuts = parsed |> Enum.map(& &1.shortcut) |> Enum.uniq()
    rows = query_table_rows(project_id, shortcuts) |> Repo.all()

    Enum.reduce(parsed, %{}, fn entry, acc ->
      match_table_row(rows, entry, acc)
    end)
  end

  defp query_table_rows(project_id, shortcuts) do
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
          coalesce(s.shortcut, fragment("CAST(? AS TEXT)", s.id)) in ^shortcuts,
      select: %{
        shortcut: coalesce(s.shortcut, fragment("CAST(? AS TEXT)", s.id)),
        table_name: b.variable_name,
        row_slug: tr.slug,
        values: tr.values
      }
    )
  end

  defp match_table_row(rows, entry, acc) do
    case find_matching_row(rows, entry) do
      nil -> acc
      row -> Map.put(acc, entry.ref, get_in(row.values, [entry.col_slug]))
    end
  end

  defp find_matching_row(rows, entry) do
    Enum.find(rows, fn r ->
      r.shortcut == entry.shortcut and r.table_name == entry.table_name and
        r.row_slug == entry.row_slug
    end)
  end

  defp extract_block_value(%{"content" => content}), do: content
  defp extract_block_value(_), do: nil

  # =============================================================================
  # Reference Validation
  # =============================================================================

  @doc """
  Validates that a reference target (sheet or flow) exists in the project.
  Returns `{:ok, entity}` or `{:error, reason}`.
  """
  @spec validate_reference_target(String.t(), integer(), integer()) ::
          {:ok, Sheet.t() | Storyarn.Flows.Flow.t()} | {:error, :not_found | :invalid_type}
  def validate_reference_target(target_type, target_id, project_id) do
    case target_type do
      "sheet" ->
        case get_sheet(project_id, target_id) do
          nil -> {:error, :not_found}
          sheet -> {:ok, sheet}
        end

      "flow" ->
        case Storyarn.Flows.get_flow(project_id, target_id) do
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
      from(b in Block,
        where: b.sheet_id == ^sheet_id and is_nil(b.deleted_at),
        order_by: [asc: b.position],
        preload: [:inherited_from_block]
      )
      |> Repo.all()

    {inherited, own} =
      Enum.split_with(blocks, fn b ->
        Block.inherited?(b)
      end)

    # Batch-load all source sheets to avoid N+1
    source_sheet_ids =
      inherited
      |> Enum.map(fn b ->
        case b.inherited_from_block do
          nil -> nil
          source -> source.sheet_id
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    source_sheets_map =
      if source_sheet_ids == [] do
        %{}
      else
        from(s in Sheet,
          where: s.id in ^source_sheet_ids and is_nil(s.deleted_at),
          preload: [:avatar_asset]
        )
        |> Repo.all()
        |> Map.new(fn s -> {s.id, s} end)
      end

    # Group inherited blocks by source sheet
    inherited_groups =
      inherited
      |> Enum.group_by(fn b ->
        case b.inherited_from_block do
          nil -> nil
          source -> source.sheet_id
        end
      end)
      |> Enum.reject(fn {k, _} -> is_nil(k) end)
      |> Enum.map(fn {source_sheet_id, blocks} ->
        %{source_sheet: Map.get(source_sheets_map, source_sheet_id), blocks: blocks}
      end)
      |> Enum.reject(fn g -> is_nil(g.source_sheet) end)

    {inherited_groups, own}
  end

  @doc """
  Lists all blocks with `scope: "children"` for a sheet.
  """
  @spec list_inheritable_blocks(integer()) :: [Block.t()]
  def list_inheritable_blocks(sheet_id) do
    from(b in Block,
      where:
        b.sheet_id == ^sheet_id and
          b.scope == "children" and
          is_nil(b.deleted_at),
      order_by: [asc: b.position]
    )
    |> Repo.all()
  end

  @doc """
  Lists all instance blocks for a given parent block ID.
  """
  @spec list_inherited_instances(integer()) :: [Block.t()]
  def list_inherited_instances(parent_block_id) do
    from(b in Block,
      where:
        b.inherited_from_block_id == ^parent_block_id and
          is_nil(b.deleted_at),
      preload: [:sheet]
    )
    |> Repo.all()
  end

  # =============================================================================
  # Trash
  # =============================================================================

  @doc """
  Lists all soft-deleted sheets for the trash view.
  """
  @spec list_trashed_sheets(integer()) :: [Sheet.t()]
  def list_trashed_sheets(project_id) do
    from(s in Sheet,
      where: s.project_id == ^project_id and not is_nil(s.deleted_at),
      order_by: [desc: s.deleted_at],
      preload: [:avatar_asset]
    )
    |> Repo.all()
  end

  @doc """
  Gets a single trashed sheet for restore/permanent-delete operations.
  """
  @spec get_trashed_sheet(integer(), integer()) :: Sheet.t() | nil
  def get_trashed_sheet(project_id, sheet_id) do
    Sheet
    |> where(project_id: ^project_id, id: ^sheet_id)
    |> where([s], not is_nil(s.deleted_at))
    |> preload([:avatar_asset])
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

    cte_query =
      anchor
      |> union_all(^recursion)

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
          preload: [:avatar_asset]
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
  # Private Helpers
  # =============================================================================

  defp build_tree(all_items, root_parent_id) do
    grouped = Enum.group_by(all_items, & &1.parent_id)
    build_subtree(grouped, root_parent_id)
  end

  defp build_subtree(grouped, parent_id) do
    (Map.get(grouped, parent_id) || [])
    |> Enum.map(fn item ->
      %{item | children: build_subtree(grouped, item.id)}
    end)
  end
end

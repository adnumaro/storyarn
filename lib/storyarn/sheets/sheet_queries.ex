defmodule Storyarn.Sheets.SheetQueries do
  @moduledoc """
  Read-only query functions for sheets.

  Provides all sheet retrieval, listing, search, and tree traversal operations.
  Mutation operations remain in `SheetCrud`.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Repo
  alias Storyarn.Sheets.{Block, Sheet, TableColumn, TableRow}

  # =============================================================================
  # Tree Operations
  # =============================================================================

  @spec list_sheets_tree(integer()) :: [Sheet.t()]
  def list_sheets_tree(project_id) do
    from(s in Sheet,
      where: s.project_id == ^project_id and is_nil(s.parent_id) and is_nil(s.deleted_at),
      order_by: [asc: s.position, asc: s.name]
    )
    |> Repo.all()
    |> preload_children_recursive()
  end

  @spec get_sheet(integer(), integer()) :: Sheet.t() | nil
  def get_sheet(project_id, sheet_id) do
    Sheet
    |> where(project_id: ^project_id, id: ^sheet_id)
    |> where([s], is_nil(s.deleted_at))
    |> preload([:blocks, :avatar_asset, :banner_asset])
    |> Repo.one()
  end

  @spec get_sheet!(integer(), integer()) :: Sheet.t()
  def get_sheet!(project_id, sheet_id) do
    Sheet
    |> where(project_id: ^project_id, id: ^sheet_id)
    |> where([s], is_nil(s.deleted_at))
    |> preload([:blocks, :avatar_asset, :banner_asset])
    |> Repo.one!()
  end

  @spec get_sheet_with_ancestors(integer(), integer()) :: [Sheet.t()] | nil
  def get_sheet_with_ancestors(project_id, sheet_id) do
    case get_sheet(project_id, sheet_id) do
      nil -> nil
      sheet -> build_ancestor_chain(sheet, [sheet])
    end
  end

  @spec get_sheet_with_descendants(integer(), integer()) :: Sheet.t() | nil
  def get_sheet_with_descendants(project_id, sheet_id) do
    case get_sheet(project_id, sheet_id) do
      nil -> nil
      sheet -> sheet |> preload_children_recursive() |> List.wrap() |> List.first()
    end
  end

  @spec get_children(integer()) :: [Sheet.t()]
  def get_children(sheet_id) do
    from(s in Sheet,
      where: s.parent_id == ^sheet_id and is_nil(s.deleted_at),
      order_by: [asc: s.position, asc: s.name],
      preload: [:avatar_asset]
    )
    |> Repo.all()
  end

  @spec list_all_sheets(integer()) :: [Sheet.t()]
  def list_all_sheets(project_id) do
    from(s in Sheet,
      where: s.project_id == ^project_id and is_nil(s.deleted_at),
      order_by: [asc: s.position, asc: s.name],
      preload: [:avatar_asset]
    )
    |> Repo.all()
  end

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
      search_term = "%#{query}%"

      from(s in Sheet,
        where: s.project_id == ^project_id and is_nil(s.deleted_at),
        where: ilike(s.name, ^search_term) or ilike(s.shortcut, ^search_term),
        order_by: [asc: s.name],
        limit: 10
      )
      |> Repo.all()
    end
  end

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
  # Reference Validation
  # =============================================================================

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

  @spec list_trashed_sheets(integer()) :: [Sheet.t()]
  def list_trashed_sheets(project_id) do
    from(s in Sheet,
      where: s.project_id == ^project_id and not is_nil(s.deleted_at),
      order_by: [desc: s.deleted_at],
      preload: [:avatar_asset]
    )
    |> Repo.all()
  end

  @spec get_trashed_sheet(integer(), integer()) :: Sheet.t() | nil
  def get_trashed_sheet(project_id, sheet_id) do
    Sheet
    |> where(project_id: ^project_id, id: ^sheet_id)
    |> where([s], not is_nil(s.deleted_at))
    |> preload([:avatar_asset])
    |> Repo.one()
  end

  # =============================================================================
  # Private Helpers
  # =============================================================================

  defp build_ancestor_chain(%Sheet{parent_id: nil}, chain), do: chain

  defp build_ancestor_chain(%Sheet{parent_id: parent_id, project_id: project_id}, chain) do
    parent =
      Sheet
      |> Repo.get!(parent_id)
      |> Repo.preload(:avatar_asset)

    if parent.project_id == project_id do
      build_ancestor_chain(parent, [parent | chain])
    else
      chain
    end
  end

  defp preload_children_recursive(sheets) when is_list(sheets) do
    Enum.map(sheets, &preload_children_recursive/1)
  end

  defp preload_children_recursive(%Sheet{} = sheet) do
    sheet = Repo.preload(sheet, :avatar_asset)

    children =
      from(s in Sheet,
        where: s.parent_id == ^sheet.id and is_nil(s.deleted_at),
        order_by: [asc: s.position, asc: s.name]
      )
      |> Repo.all()
      |> preload_children_recursive()

    %{sheet | children: children}
  end
end

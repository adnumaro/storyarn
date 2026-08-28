defmodule Storyarn.Sheets.Editor.Queries.Sheets do
  @moduledoc """
  Read-only query functions for sheets.

  Provides all sheet retrieval, listing, search, and tree traversal operations.
  Mutation operations remain in the editor's command modules.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Platform.Shared.SearchHelpers
  alias Storyarn.Repo
  alias Storyarn.Sheets.Block
  alias Storyarn.Sheets.BlockGalleryImage
  alias Storyarn.Sheets.Editor.Queries.Tree, as: TreeQueries
  alias Storyarn.Sheets.Sheet
  alias Storyarn.Sheets.TableColumn
  alias Storyarn.Sheets.TableRow

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

    TreeQueries.build_from_flat_list(all_sheets)
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

        children = TreeQueries.build_from_flat_list(all_sheets, sheet.id)
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

  Callers OWN the authorization of `project_ids` (see `Storyarn.Platform.GlobalSearch`);
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

  defp maybe_filter_export_ids(query, :all), do: query

  defp maybe_filter_export_ids(query, ids) when is_list(ids) do
    from(q in query, where: q.id in ^ids)
  end
end

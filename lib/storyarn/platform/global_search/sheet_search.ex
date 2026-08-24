defmodule Storyarn.Platform.GlobalSearch.SheetSearch do
  @moduledoc false

  import Ecto.Query

  alias Storyarn.Platform.GlobalSearch.Persistence.BlockGalleryImageRecord
  alias Storyarn.Platform.GlobalSearch.Persistence.BlockRecord
  alias Storyarn.Platform.GlobalSearch.Persistence.SheetRecord
  alias Storyarn.Platform.GlobalSearch.Persistence.TableColumnRecord
  alias Storyarn.Platform.GlobalSearch.Persistence.TableRowRecord
  alias Storyarn.Platform.Shared.SearchHelpers
  alias Storyarn.Repo

  @default_search_limit 20
  @max_deep_search_limit 50
  @max_deep_search_offset 10_000

  @spec get(integer(), integer()) :: SheetRecord.t() | nil
  def get(project_id, sheet_id) do
    Repo.one(
      from(sheet in SheetRecord,
        where:
          sheet.id == ^sheet_id and sheet.project_id == ^project_id and
            is_nil(sheet.deleted_at)
      )
    )
  end

  @spec search_in_projects([integer()], String.t(), keyword()) :: [SheetRecord.t()]
  def search_in_projects(project_ids, query, opts \\ []) when is_list(project_ids) and is_binary(query) do
    limit = Keyword.get(opts, :limit, @default_search_limit)
    query_str = String.trim(query)

    cond do
      project_ids == [] ->
        []

      query_str == "" ->
        Repo.all(
          from(sheet in SheetRecord,
            where: sheet.project_id in ^project_ids and is_nil(sheet.deleted_at),
            order_by: [desc: sheet.updated_at, desc: sheet.id],
            limit: ^limit
          ),
          log: false
        )

      true ->
        search_term = "%#{SearchHelpers.sanitize_like_query(query_str)}%"

        Repo.all(
          from(sheet in SheetRecord,
            where: sheet.project_id in ^project_ids and is_nil(sheet.deleted_at),
            where: ilike(sheet.name, ^search_term) or ilike(sheet.shortcut, ^search_term),
            order_by: [asc: sheet.name],
            limit: ^limit
          ),
          log: false
        )
    end
  end

  @spec search(integer(), String.t(), keyword()) :: [SheetRecord.t()]
  def search(project_id, query, opts \\ []) when is_binary(query) do
    limit = Keyword.get(opts, :limit, @default_search_limit)
    offset = Keyword.get(opts, :offset, 0)
    query_str = String.trim(query)

    if query_str == "" do
      Repo.all(
        from(sheet in SheetRecord,
          where: sheet.project_id == ^project_id and is_nil(sheet.deleted_at),
          order_by: [desc: sheet.updated_at],
          limit: ^limit,
          offset: ^offset
        ),
        log: false
      )
    else
      search_term = "%#{SearchHelpers.sanitize_like_query(query_str)}%"

      Repo.all(
        from(sheet in SheetRecord,
          where: sheet.project_id == ^project_id and is_nil(sheet.deleted_at),
          where: ilike(sheet.name, ^search_term) or ilike(sheet.shortcut, ^search_term),
          order_by: [asc: sheet.name],
          limit: ^limit,
          offset: ^offset
        ),
        log: false
      )
    end
  end

  @spec search_deep(integer(), String.t(), keyword()) :: [SheetRecord.t()]
  def search_deep(project_id, query, opts \\ []) when is_binary(query) do
    limit = bounded_deep_search_limit(opts)
    offset = bounded_deep_search_offset(opts)
    query_str = String.trim(query)

    if query_str == "" do
      search(project_id, query_str, limit: limit, offset: offset)
    else
      search_term = "%#{SearchHelpers.sanitize_like_query(query_str)}%"

      Repo.all(
        from(sheet in SheetRecord,
          where: sheet.project_id == ^project_id and is_nil(sheet.deleted_at),
          where:
            ilike(sheet.name, ^search_term) or
              ilike(sheet.shortcut, ^search_term) or
              ilike(sheet.description, ^search_term) or
              sheet.id in subquery(sheet_ids_matching_blocks(project_id, search_term)) or
              sheet.id in subquery(sheet_ids_matching_table_columns(project_id, search_term)) or
              sheet.id in subquery(sheet_ids_matching_table_rows(project_id, search_term)) or
              sheet.id in subquery(sheet_ids_matching_gallery_images(project_id, search_term)),
          order_by: [asc: sheet.name, asc: sheet.id],
          limit: ^limit,
          offset: ^offset
        ),
        log: false
      )
    end
  end

  defp sheet_ids_matching_blocks(project_id, search_term) do
    from(block in BlockRecord,
      join: sheet in SheetRecord,
      on: sheet.id == block.sheet_id,
      where: sheet.project_id == ^project_id and is_nil(sheet.deleted_at) and is_nil(block.deleted_at),
      where:
        ilike(block.variable_name, ^search_term) or
          ilike(fragment("?->>'label'", block.config), ^search_term) or
          ilike(fragment("?->>'placeholder'", block.config), ^search_term) or
          ilike(fragment("?->>'content'", block.value), ^search_term) or
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
            block.config,
            ^search_term
          ),
      select: block.sheet_id
    )
  end

  defp sheet_ids_matching_table_columns(project_id, search_term) do
    from(column in TableColumnRecord,
      join: block in BlockRecord,
      on: block.id == column.block_id,
      join: sheet in SheetRecord,
      on: sheet.id == block.sheet_id,
      where: sheet.project_id == ^project_id and is_nil(sheet.deleted_at) and is_nil(block.deleted_at),
      where:
        ilike(column.name, ^search_term) or
          ilike(column.slug, ^search_term) or
          ilike(fragment("CAST(?->'options' AS TEXT)", column.config), ^search_term),
      select: block.sheet_id
    )
  end

  defp sheet_ids_matching_table_rows(project_id, search_term) do
    from(row in TableRowRecord,
      join: block in BlockRecord,
      on: block.id == row.block_id,
      join: sheet in SheetRecord,
      on: sheet.id == block.sheet_id,
      where: sheet.project_id == ^project_id and is_nil(sheet.deleted_at) and is_nil(block.deleted_at),
      where:
        ilike(row.name, ^search_term) or
          ilike(row.slug, ^search_term) or
          ilike(fragment("CAST(? AS TEXT)", row.cells), ^search_term),
      select: block.sheet_id
    )
  end

  defp sheet_ids_matching_gallery_images(project_id, search_term) do
    from(image in BlockGalleryImageRecord,
      join: block in BlockRecord,
      on: block.id == image.block_id,
      join: sheet in SheetRecord,
      on: sheet.id == block.sheet_id,
      where: sheet.project_id == ^project_id and is_nil(sheet.deleted_at) and is_nil(block.deleted_at),
      where: ilike(image.label, ^search_term) or ilike(image.description, ^search_term),
      select: block.sheet_id
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
end

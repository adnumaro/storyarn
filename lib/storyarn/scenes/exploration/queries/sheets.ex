defmodule Storyarn.Scenes.SheetCatalog do
  @moduledoc """
  Scene-owned read model for Sheet identity and speaker presentation data.

  These projections intentionally mirror only what the scene editor and scene
  exploration runtime consume.
  """

  import Ecto.Query

  alias Storyarn.Platform.Shared.SearchHelpers
  alias Storyarn.Repo
  alias Storyarn.Scenes.Exploration.Projections.SheetRecord

  @default_search_limit 20

  @spec list_sheets_tree(integer()) :: [map()]
  def list_sheets_tree(project_id) do
    project_id
    |> list_all_sheets()
    |> build_tree_from_flat_list()
  end

  @spec list_all_sheets(integer()) :: [SheetRecord.t()]
  def list_all_sheets(project_id) do
    Repo.all(
      from sheet in SheetRecord,
        where: sheet.project_id == ^project_id and is_nil(sheet.deleted_at),
        order_by: [asc: sheet.position, asc: sheet.name],
        preload: [avatars: :asset]
    )
  end

  @spec search_sheets(integer(), String.t(), keyword()) :: [SheetRecord.t()]
  def search_sheets(project_id, query, opts \\ []) when is_binary(query) do
    limit = Keyword.get(opts, :limit, @default_search_limit)
    offset = Keyword.get(opts, :offset, 0)
    query = String.trim(query)

    base =
      from sheet in SheetRecord,
        where: sheet.project_id == ^project_id and is_nil(sheet.deleted_at)

    if query == "" do
      Repo.all(
        from sheet in base,
          order_by: [desc: sheet.updated_at],
          limit: ^limit,
          offset: ^offset
      )
    else
      term = "%#{SearchHelpers.sanitize_like_query(query)}%"

      Repo.all(
        from sheet in base,
          where: ilike(sheet.name, ^term) or ilike(sheet.shortcut, ^term),
          order_by: [asc: sheet.name],
          limit: ^limit,
          offset: ^offset
      )
    end
  end

  @spec get_sheet(integer(), integer()) :: SheetRecord.t() | nil
  def get_sheet(project_id, sheet_id) do
    Repo.one(
      from sheet in SheetRecord,
        where:
          sheet.project_id == ^project_id and sheet.id == ^sheet_id and
            is_nil(sheet.deleted_at),
        preload: [avatars: :asset]
    )
  end

  defp build_tree_from_flat_list(items) do
    items
    |> Enum.group_by(& &1.parent_id)
    |> build_subtree(nil)
  end

  defp build_subtree(grouped, parent_id) do
    Enum.map(Map.get(grouped, parent_id, []), fn item ->
      Map.put(item, :children, build_subtree(grouped, item.id))
    end)
  end
end

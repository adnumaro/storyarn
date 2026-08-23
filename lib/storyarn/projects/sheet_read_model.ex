defmodule Storyarn.Projects.SheetReadModel do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Projects.Persistence.BlockRecord
  alias Storyarn.Projects.Persistence.SheetRecord
  alias Storyarn.Repo

  @doc """
  Lists active sheets with the exact preload shape project snapshots capture.

  Blocks are ordered deterministically so a rebuilt export never reorders
  unchanged content.
  """
  def list_for_export(project_id, opts \\ []) do
    filter_ids = Keyword.get(opts, :filter_ids, :all)

    blocks_query =
      from(block in BlockRecord,
        where: is_nil(block.deleted_at),
        preload: [:table_columns, :table_rows],
        # An export is a file people diff. Two blocks at one position would
        # otherwise swap places between runs with nothing having changed.
        order_by: [asc: block.position, asc: block.id]
      )

    query =
      from(sheet in SheetRecord,
        where: sheet.project_id == ^project_id and is_nil(sheet.deleted_at),
        preload: [blocks: ^blocks_query, avatars: :asset],
        order_by: [asc: sheet.position, asc: sheet.name]
      )

    query
    |> maybe_filter_ids(filter_ids)
    |> Repo.all()
  end

  defp maybe_filter_ids(query, :all), do: query

  defp maybe_filter_ids(query, ids) when is_list(ids) do
    from(sheet in query, where: sheet.id in ^ids)
  end
end

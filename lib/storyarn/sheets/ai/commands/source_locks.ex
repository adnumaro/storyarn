defmodule Storyarn.Sheets.AI.SourceLocks do
  @moduledoc false

  import Ecto.Query

  alias Storyarn.Repo
  alias Storyarn.Sheets.AI.Projections.BlockRecord, as: Block
  alias Storyarn.Sheets.AI.Projections.FlowRecord
  alias Storyarn.Sheets.AI.Projections.ProjectRecord
  alias Storyarn.Sheets.AI.Projections.SheetRecord, as: Sheet

  @persisted_types ~w(flow sheet sheet_block)
  @max_included_sources 500

  @spec acquire(map()) :: :ok | {:error, :stale_context}
  def acquire(%{context_hash: nil, context_manifest: nil, context_subject: nil}), do: :ok

  def acquire(%{project_id_snapshot: project_id, context_hash: hash, context_manifest: %{} = manifest})
      when is_integer(project_id) and is_binary(hash) do
    with {:ok, source_ids} <- included_source_ids(manifest),
         :ok <- active_project(project_id),
         {:ok, block_parents} <- block_parents(project_id, MapSet.to_list(source_ids["sheet_block"])),
         sheet_ids =
           source_ids["sheet"]
           |> MapSet.union(MapSet.new(Map.values(block_parents)))
           |> MapSet.to_list()
           |> Enum.sort(),
         flow_ids = source_ids["flow"] |> MapSet.to_list() |> Enum.sort(),
         :ok <- lock_flows(project_id, flow_ids),
         :ok <- lock_sheets(project_id, sheet_ids),
         {:ok, locked_blocks} <- lock_blocks(source_ids["sheet_block"], sheet_ids),
         :ok <- included_sources_locked(source_ids, flow_ids, sheet_ids, locked_blocks) do
      :ok
    else
      _error -> {:error, :stale_context}
    end
  end

  def acquire(%{}), do: {:error, :stale_context}

  defp included_source_ids(manifest) do
    case value(manifest, :included) do
      included when is_list(included) and length(included) <= @max_included_sources ->
        Enum.reduce_while(included, {:ok, empty_source_ids()}, &include_source/2)

      _invalid ->
        {:error, :invalid_manifest}
    end
  end

  defp include_source(%{} = item, {:ok, source_ids}) do
    type = value(item, :type)
    id = value(item, :id)

    if type in @persisted_types and positive_id?(id) do
      {:cont, {:ok, Map.update!(source_ids, type, &MapSet.put(&1, id))}}
    else
      {:halt, {:error, :invalid_manifest}}
    end
  end

  defp include_source(_item, _acc), do: {:halt, {:error, :invalid_manifest}}
  defp empty_source_ids, do: Map.new(@persisted_types, &{&1, MapSet.new()})

  defp active_project(project_id) do
    if Repo.exists?(
         from(project in ProjectRecord,
           where: project.id == ^project_id and is_nil(project.deleted_at)
         )
       ),
       do: :ok,
       else: {:error, :context_missing}
  end

  defp block_parents(_project_id, []), do: {:ok, %{}}

  defp block_parents(project_id, block_ids) do
    rows =
      Repo.all(
        from(block in Block,
          join: sheet in Sheet,
          on: sheet.id == block.sheet_id,
          where:
            block.id in ^block_ids and sheet.project_id == ^project_id and
              is_nil(block.deleted_at) and is_nil(sheet.deleted_at),
          order_by: [asc: block.id],
          select: {block.id, block.sheet_id}
        )
      )

    parents = Map.new(rows)

    if MapSet.new(Map.keys(parents)) == MapSet.new(block_ids),
      do: {:ok, parents},
      else: {:error, :context_missing}
  end

  defp lock_flows(_project_id, []), do: :ok

  defp lock_flows(project_id, flow_ids) do
    locked_ids =
      Repo.all(
        from(flow in FlowRecord,
          where:
            flow.id in ^flow_ids and flow.project_id == ^project_id and
              is_nil(flow.deleted_at),
          order_by: [asc: flow.id],
          select: flow.id,
          lock: "FOR UPDATE"
        )
      )

    exact_ids(locked_ids, flow_ids)
  end

  defp lock_sheets(_project_id, []), do: :ok

  defp lock_sheets(project_id, sheet_ids) do
    locked_ids =
      Repo.all(
        from(sheet in Sheet,
          where:
            sheet.id in ^sheet_ids and sheet.project_id == ^project_id and
              is_nil(sheet.deleted_at),
          order_by: [asc: sheet.id],
          select: sheet.id,
          lock: "FOR UPDATE"
        )
      )

    exact_ids(locked_ids, sheet_ids)
  end

  defp lock_blocks(block_ids, sheet_ids) do
    block_ids = MapSet.to_list(block_ids)

    rows =
      Repo.all(
        from(block in Block,
          where:
            block.id in ^block_ids and block.sheet_id in ^sheet_ids and
              is_nil(block.deleted_at),
          order_by: [asc: block.id],
          select: block.id,
          lock: "FOR UPDATE"
        )
      )

    {:ok, MapSet.new(rows)}
  end

  defp included_sources_locked(source_ids, flow_ids, sheet_ids, locked_blocks) do
    checks = [
      MapSet.subset?(source_ids["flow"], MapSet.new(flow_ids)),
      MapSet.subset?(source_ids["sheet"], MapSet.new(sheet_ids)),
      MapSet.subset?(source_ids["sheet_block"], locked_blocks)
    ]

    if Enum.all?(checks), do: :ok, else: {:error, :context_missing}
  end

  defp exact_ids(locked_ids, expected_ids) do
    if locked_ids == Enum.sort(expected_ids),
      do: :ok,
      else: {:error, :context_missing}
  end

  defp positive_id?(value), do: is_integer(value) and value > 0
  defp value(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end

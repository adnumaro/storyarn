defmodule Storyarn.Sheets.Editor.Queries.Inheritance do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Repo
  alias Storyarn.Sheets.Block
  alias Storyarn.Sheets.Editor.Queries.InheritanceAudit
  alias Storyarn.Sheets.Editor.Queries.Sheets, as: SheetQueries
  alias Storyarn.Sheets.Sheet

  def resolve(sheet_id) do
    {groups, _hidden_source_ids} = resolution(sheet_id)
    groups
  end

  def list_health_issues(sheet_id) do
    {groups, hidden_source_ids} = resolution(sheet_id)
    eligible_sources = Enum.flat_map(groups, & &1.blocks)

    instances =
      sheet_id
      |> active_instances()
      |> Enum.reject(&MapSet.member?(hidden_source_ids, &1.inherited_from_block_id))

    InheritanceAudit.issues(
      eligible_sources,
      instances,
      InheritanceAudit.table_structures(eligible_sources ++ instances)
    )
  end

  def list_project_health_issues(sheets, table_data \\ nil)
  def list_project_health_issues([], _table_data), do: %{}

  def list_project_health_issues(sheets, table_data) do
    sheets_by_id = Map.new(sheets, &{&1.id, &1})
    ancestors_by_sheet = Map.new(sheets, &{&1.id, ancestor_chain(&1, sheets_by_id)})

    sources_by_sheet =
      sheets
      |> Enum.map(& &1.id)
      |> load_children_scope_blocks()
      |> Enum.group_by(& &1.sheet_id)

    instances_by_sheet =
      sheets
      |> Enum.map(& &1.id)
      |> active_instances_for_sheets()
      |> Enum.group_by(& &1.sheet_id)

    resolved =
      Map.new(sheets, fn sheet ->
        ancestors = Map.get(ancestors_by_sheet, sheet.id, [])
        hidden_source_ids = MapSet.new(hidden_block_ids([sheet | ancestors]))

        sources =
          ancestors
          |> Enum.flat_map(&Map.get(sources_by_sheet, &1.id, []))
          |> Enum.reject(&MapSet.member?(hidden_source_ids, &1.id))

        instances =
          instances_by_sheet
          |> Map.get(sheet.id, [])
          |> Enum.reject(&MapSet.member?(hidden_source_ids, &1.inherited_from_block_id))

        {sheet.id, {sources, instances}}
      end)

    structures = table_structures(resolved, table_data)

    Map.new(resolved, fn {sheet_id, {sources, instances}} ->
      {sheet_id, InheritanceAudit.issues(sources, instances, structures)}
    end)
  end

  def get_source_sheet(%Block{inherited_from_block_id: nil}), do: nil

  def get_source_sheet(%Block{inherited_from_block_id: source_id}) do
    case Repo.get(Block, source_id) do
      nil -> nil
      source_block -> Repo.get(Sheet, source_block.sheet_id)
    end
  end

  def descendant_sheet_ids(sheet_id) do
    case active_sheet_project_id(sheet_id) do
      nil -> []
      project_id -> load_descendant_sheet_ids(project_id, sheet_id)
    end
  end

  defp resolution(sheet_id) do
    sheet = Repo.get!(Sheet, sheet_id)
    ancestors = ancestors(sheet)

    if ancestors == [] do
      {[], MapSet.new(hidden_block_ids([sheet]))}
    else
      hidden_source_ids = MapSet.new(hidden_block_ids([sheet | ancestors]))

      blocks_by_sheet =
        ancestors
        |> Enum.map(& &1.id)
        |> load_children_scope_blocks()
        |> Enum.reject(&MapSet.member?(hidden_source_ids, &1.id))
        |> Enum.group_by(& &1.sheet_id)

      groups =
        ancestors
        |> Enum.map(&%{source_sheet: &1, blocks: Map.get(blocks_by_sheet, &1.id, [])})
        |> Enum.reject(&(&1.blocks == []))

      {groups, hidden_source_ids}
    end
  end

  defp ancestors(%Sheet{parent_id: nil}), do: []
  defp ancestors(%Sheet{} = sheet), do: SheetQueries.list_ancestors(sheet.id)

  defp hidden_block_ids(sheets) do
    sheets
    |> Enum.flat_map(&(&1.hidden_inherited_block_ids || []))
    |> Enum.uniq()
  end

  defp load_children_scope_blocks([]), do: []

  defp load_children_scope_blocks(sheet_ids) do
    Repo.all(
      from(block in Block,
        where:
          block.sheet_id in ^sheet_ids and block.scope == "children" and
            is_nil(block.deleted_at),
        order_by: [asc: block.sheet_id, asc: block.position, asc: block.id]
      )
    )
  end

  defp active_instances(sheet_id) do
    Repo.all(
      from(block in Block,
        where:
          block.sheet_id == ^sheet_id and not is_nil(block.inherited_from_block_id) and
            block.detached == false and is_nil(block.deleted_at),
        order_by: [asc: block.id]
      )
    )
  end

  defp active_instances_for_sheets(sheet_ids) do
    Repo.all(
      from(block in Block,
        where:
          block.sheet_id in ^sheet_ids and not is_nil(block.inherited_from_block_id) and
            block.detached == false and is_nil(block.deleted_at),
        order_by: [asc: block.id]
      )
    )
  end

  defp table_structures(resolved, nil) do
    resolved
    |> Enum.flat_map(fn {_sheet_id, {sources, instances}} -> sources ++ instances end)
    |> Enum.uniq_by(& &1.id)
    |> InheritanceAudit.table_structures()
  end

  defp table_structures(_resolved, table_data) when is_map(table_data) do
    InheritanceAudit.table_structures_from_data(table_data)
  end

  defp ancestor_chain(sheet, sheets_by_id, seen \\ [])
  defp ancestor_chain(%Sheet{parent_id: nil}, _sheets_by_id, _seen), do: []

  defp ancestor_chain(%Sheet{} = sheet, sheets_by_id, seen) do
    case Map.get(sheets_by_id, sheet.parent_id) do
      nil ->
        []

      parent ->
        if parent.id in seen do
          []
        else
          [parent | ancestor_chain(parent, sheets_by_id, [parent.id | seen])]
        end
    end
  end

  defp active_sheet_project_id(sheet_id) do
    Repo.one(
      from(sheet in Sheet,
        where: sheet.id == ^sheet_id and is_nil(sheet.deleted_at),
        select: sheet.project_id
      )
    )
  end

  defp load_descendant_sheet_ids(project_id, sheet_id) do
    anchor =
      from(sheet in "sheets",
        where:
          sheet.parent_id == ^sheet_id and sheet.project_id == ^project_id and
            is_nil(sheet.deleted_at),
        select: %{id: sheet.id}
      )

    recursion =
      from(sheet in "sheets",
        join: descendant in "descendants",
        on: sheet.parent_id == descendant.id,
        where: sheet.project_id == ^project_id and is_nil(sheet.deleted_at),
        select: %{id: sheet.id}
      )

    cte_query = union_all(anchor, ^recursion)

    from("descendants")
    |> recursive_ctes(true)
    |> with_cte("descendants", as: ^cte_query)
    |> select([descendant], descendant.id)
    |> Repo.all()
  end
end

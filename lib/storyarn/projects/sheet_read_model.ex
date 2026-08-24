defmodule Storyarn.Projects.SheetReadModel do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Platform.Shared.HtmlUtils
  alias Storyarn.Projects.FlowVariableNamespaceResolver
  alias Storyarn.Projects.Persistence.BlockRecord
  alias Storyarn.Projects.Persistence.SheetRecord
  alias Storyarn.Projects.Persistence.TableColumnRecord
  alias Storyarn.Projects.Persistence.TableRowRecord
  alias Storyarn.Repo

  require FlowVariableNamespaceResolver

  @localizable_block_types ~w(text rich_text)

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

  @doc """
  Lists active sheets by id with the banner and avatar preloads the project
  snapshot builders serialize.
  """
  def list_by_ids(_project_id, []), do: []

  def list_by_ids(project_id, ids) do
    Repo.all(
      from(sheet in SheetRecord,
        where: sheet.project_id == ^project_id and sheet.id in ^ids and is_nil(sheet.deleted_at),
        preload: [:banner_asset, avatars: :asset]
      )
    )
  end

  @doc "Counts non-deleted sheets for a project."
  def count_active(project_id) do
    Repo.aggregate(
      from(sheet in SheetRecord, where: sheet.project_id == ^project_id and is_nil(sheet.deleted_at)),
      :count
    )
  end

  @doc """
  Counts the project's sheet variables with the exact filters the Sheet tool's
  variable catalog applies — including the table variant, which counts every
  cell (column x row), not columns.
  """
  def count_variables(project_id) do
    count_block_variables(project_id) + count_table_variables(project_id)
  end

  defp count_block_variables(project_id) do
    variable_types = ~w(text rich_text number select multi_select boolean date)

    Repo.aggregate(
      from(block in BlockRecord,
        join: sheet in SheetRecord,
        on: block.sheet_id == sheet.id,
        where:
          sheet.project_id == ^project_id and
            is_nil(sheet.deleted_at) and
            is_nil(block.deleted_at) and
            block.type in ^variable_types and
            block.is_constant == false and
            not is_nil(block.variable_name) and
            block.variable_name != "" and
            FlowVariableNamespaceResolver.authoritative_namespace_owner?(sheet)
      ),
      :count
    )
  end

  defp count_table_variables(project_id) do
    variable_column_types = ~w(number text boolean select multi_select date reference formula)

    Repo.aggregate(
      from(column in TableColumnRecord,
        join: block in BlockRecord,
        on: column.block_id == block.id,
        join: sheet in SheetRecord,
        on: block.sheet_id == sheet.id,
        join: row in TableRowRecord,
        on: row.block_id == block.id,
        where: sheet.project_id == ^project_id,
        where: is_nil(sheet.deleted_at) and is_nil(block.deleted_at),
        where: block.type == "table",
        where: column.type in ^variable_column_types,
        where: column.is_constant == false or column.type == "formula",
        where: FlowVariableNamespaceResolver.authoritative_namespace_owner?(sheet)
      ),
      :count
    )
  end

  @doc """
  Word counts per active sheet — name words plus localizable block words,
  mirroring the Sheet tool's runtime content contract.
  """
  def sheet_word_counts(project_id) do
    block_counts =
      from(block in BlockRecord,
        join: sheet in SheetRecord,
        on: sheet.id == block.sheet_id,
        where:
          sheet.project_id == ^project_id and is_nil(sheet.deleted_at) and
            block.type in ^@localizable_block_types,
        select: %{
          sheet_id: block.sheet_id,
          type: block.type,
          is_constant: block.is_constant,
          variable_name: block.variable_name,
          deleted_at: block.deleted_at,
          word_count: block.word_count
        }
      )
      |> Repo.all()
      |> Enum.filter(&localizable_block?/1)
      |> Enum.reduce(%{}, fn block, counts ->
        Map.update(counts, block.sheet_id, block.word_count, &(&1 + block.word_count))
      end)

    sheet_counts =
      SheetRecord
      |> where([sheet], sheet.project_id == ^project_id and is_nil(sheet.deleted_at))
      |> select([sheet], {sheet.id, sheet.name})
      |> Repo.all()
      |> Map.new(fn {sheet_id, name} -> {sheet_id, name_word_count(name)} end)

    Map.merge(sheet_counts, block_counts, fn _sheet_id, name_words, block_words ->
      name_words + block_words
    end)
  end

  defp localizable_block?(block) do
    block.type in @localizable_block_types and
      block.is_constant == false and
      present_variable_name?(block.variable_name) and
      is_nil(block.deleted_at)
  end

  defp present_variable_name?(name) when is_binary(name), do: String.trim(name) != ""
  defp present_variable_name?(_name), do: false

  defp name_word_count(name) when is_binary(name), do: HtmlUtils.word_count(name)
  defp name_word_count(_name), do: 0

  defp maybe_filter_ids(query, :all), do: query

  defp maybe_filter_ids(query, ids) when is_list(ids) do
    from(sheet in query, where: sheet.id in ^ids)
  end
end

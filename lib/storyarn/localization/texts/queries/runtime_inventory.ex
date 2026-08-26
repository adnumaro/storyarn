defmodule Storyarn.Localization.Texts.Queries.RuntimeInventory do
  @moduledoc "Read-only runtime word-count projections for Flows and Sheets."

  import Ecto.Query, warn: false

  alias Storyarn.Localization.SourceContract
  alias Storyarn.Localization.Texts.Data.BlockRecord
  alias Storyarn.Localization.Texts.Data.FlowNodeRecord
  alias Storyarn.Localization.Texts.Data.FlowRecord
  alias Storyarn.Localization.Texts.Data.SheetRecord
  alias Storyarn.Platform.Shared.HtmlUtils
  alias Storyarn.Repo

  # Public — Runtime Word Counts
  # =============================================================================

  @doc "Returns per-flow counts for player-facing runtime text."
  @spec flow_word_counts(integer()) :: %{integer() => non_neg_integer()}
  def flow_word_counts(project_id) do
    localizable_node_types = SourceContract.localizable_flow_node_types()

    from(node in FlowNodeRecord,
      join: flow in FlowRecord,
      on: flow.id == node.flow_id,
      where:
        flow.project_id == ^project_id and is_nil(flow.deleted_at) and is_nil(node.deleted_at) and
          node.type in ^localizable_node_types,
      group_by: node.flow_id,
      select: {node.flow_id, coalesce(sum(node.word_count), 0)}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc "Returns per-sheet counts for exported sheet names and textual runtime variables."
  @spec sheet_word_counts(integer()) :: %{integer() => non_neg_integer()}
  def sheet_word_counts(project_id) do
    localizable_block_types = SourceContract.localizable_block_types()

    block_counts =
      from(block in BlockRecord,
        join: sheet in SheetRecord,
        on: sheet.id == block.sheet_id,
        where:
          sheet.project_id == ^project_id and is_nil(sheet.deleted_at) and
            block.type in ^localizable_block_types,
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
      |> Enum.filter(&SourceContract.localizable_block?/1)
      |> Enum.reduce(%{}, fn block, counts ->
        Map.update(counts, block.sheet_id, block.word_count, &(&1 + block.word_count))
      end)

    project_id
    |> runtime_sheets()
    |> Map.new(fn sheet -> {sheet.id, sheet |> speaker_source_fields() |> count_fields()} end)
    |> Map.merge(block_counts, fn _sheet_id, name_words, block_words -> name_words + block_words end)
  end

  defp runtime_sheets(project_id) do
    Repo.all(
      from(sheet in SheetRecord,
        where: sheet.project_id == ^project_id and is_nil(sheet.deleted_at),
        order_by: [asc: sheet.id]
      )
    )
  end

  defp speaker_source_fields(%SheetRecord{name: name}) do
    optional_field("name", name, "speaker_name")
  end

  defp optional_field(_field, text, _role, _opts \\ [])
  defp optional_field(_field, nil, _role, _opts), do: []
  defp optional_field(_field, "", _role, _opts), do: []

  defp optional_field(field, text, role, opts) when is_binary(text) do
    if HtmlUtils.strip_html(text) == "" do
      []
    else
      [
        %{
          field: field,
          text: text,
          content_role: role,
          vo_eligible: Keyword.get(opts, :vo_eligible, false),
          speaker_sheet_id: Keyword.get(opts, :speaker_sheet_id)
        }
      ]
    end
  end

  defp optional_field(_field, _text, _role, _opts), do: []
  defp count_fields(fields), do: Enum.sum(Enum.map(fields, &HtmlUtils.word_count(&1.text)))
end

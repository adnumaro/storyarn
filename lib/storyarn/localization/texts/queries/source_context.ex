defmodule Storyarn.Localization.Texts.Queries.SourceContext do
  @moduledoc """
  Read-only lookup of the entity a localized text was extracted from.

  The translation editor names the source as "Flow › node" or "Sheet › block"
  and links back to it. The lookup reads Texts' passive Flow, Sheet and Block
  projections and never mutates them.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Localization.LocalizedText
  alias Storyarn.Localization.Texts.Projections.BlockRecord
  alias Storyarn.Localization.Texts.Projections.FlowNodeRecord
  alias Storyarn.Localization.Texts.Projections.FlowRecord
  alias Storyarn.Localization.Texts.Projections.SheetRecord
  alias Storyarn.Platform.Shared.HtmlUtils
  alias Storyarn.Platform.Shared.StringUtils
  alias Storyarn.Repo

  @max_label_length 48

  @type t :: %{
          kind: :flow_node | :block | :sheet,
          parent_name: String.t() | nil,
          label: String.t() | nil,
          flow_id: integer() | nil,
          node_id: integer() | nil,
          sheet_id: integer() | nil
        }

  @doc "Returns the source context of a text, or `nil` when the source or its parent is deleted or gone."
  @spec for_text(LocalizedText.t()) :: t() | nil
  def for_text(%LocalizedText{source_type: "flow_node", source_id: node_id}) do
    from(node in FlowNodeRecord,
      join: flow in FlowRecord,
      on: flow.id == node.flow_id,
      where: node.id == ^node_id and is_nil(node.deleted_at) and is_nil(flow.deleted_at),
      select: %{flow_id: flow.id, flow_name: flow.name, data: node.data}
    )
    |> Repo.one()
    |> case do
      nil ->
        nil

      row ->
        %{
          kind: :flow_node,
          parent_name: row.flow_name,
          label: node_label(row.data),
          flow_id: row.flow_id,
          node_id: node_id,
          sheet_id: nil
        }
    end
  end

  def for_text(%LocalizedText{source_type: "block", source_id: block_id}) do
    from(block in BlockRecord,
      join: sheet in SheetRecord,
      on: sheet.id == block.sheet_id,
      where: block.id == ^block_id and is_nil(block.deleted_at) and is_nil(sheet.deleted_at),
      select: %{sheet_id: sheet.id, sheet_name: sheet.name, variable_name: block.variable_name}
    )
    |> Repo.one()
    |> case do
      nil ->
        nil

      row ->
        %{
          kind: :block,
          parent_name: row.sheet_name,
          label: present(row.variable_name),
          flow_id: nil,
          node_id: nil,
          sheet_id: row.sheet_id
        }
    end
  end

  def for_text(%LocalizedText{source_type: "sheet", source_id: sheet_id}) do
    from(sheet in SheetRecord,
      where: sheet.id == ^sheet_id and is_nil(sheet.deleted_at),
      select: %{id: sheet.id, name: sheet.name}
    )
    |> Repo.one()
    |> case do
      nil -> nil
      row -> %{kind: :sheet, parent_name: row.name, label: nil, flow_id: nil, node_id: nil, sheet_id: row.id}
    end
  end

  def for_text(_text), do: nil

  # Same precedence the Flow editor uses for a node title: technical id, label,
  # then an excerpt of the dialogue text.
  defp node_label(data) when is_map(data) do
    Enum.find_value([data["technical_id"], data["label"], text_excerpt(data["text"])], &present/1)
  end

  defp node_label(_data), do: nil

  defp text_excerpt(text) when is_binary(text) do
    text
    |> HtmlUtils.strip_html()
    |> String.trim()
    |> String.slice(0, @max_label_length)
  end

  defp text_excerpt(_text), do: nil

  defp present(value) when is_binary(value) do
    if StringUtils.blank?(String.trim(value)), do: nil, else: value
  end

  defp present(_value), do: nil
end

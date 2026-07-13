defmodule Storyarn.Localization.TextExtractor do
  @moduledoc false

  alias Storyarn.Localization.LocalizableWords

  defdelegate extract_all(project_id), to: LocalizableWords
  defdelegate extract_flow_node(node), to: LocalizableWords
  defdelegate extract_block(block), to: LocalizableWords
  defdelegate extract_flow_nodes(flow_id), to: LocalizableWords
  defdelegate extract_sheet_blocks(sheet_id), to: LocalizableWords
  defdelegate extract_sheet_blocks_for_sheets(sheet_ids), to: LocalizableWords
  defdelegate extract_block_tree(block_id), to: LocalizableWords
  defdelegate sync_sheet_names(project_id), to: LocalizableWords

  defdelegate delete_flow_node_texts(node_id), to: LocalizableWords
  defdelegate delete_flow_node_texts_for_flows(flow_ids), to: LocalizableWords
  defdelegate delete_block_texts(block_id), to: LocalizableWords
  defdelegate delete_block_tree_texts(block_id), to: LocalizableWords
  defdelegate delete_block_texts_for_sheets(sheet_ids), to: LocalizableWords
end

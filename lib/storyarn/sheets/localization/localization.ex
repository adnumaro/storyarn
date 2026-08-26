defmodule Storyarn.Sheets.Localization do
  @moduledoc """
  Public boundary for Sheet-owned localization behavior.

  Sheets decides which authored fields are runtime content, counts that content
  and reconciles its sources into the shared localization inventory. The global
  Localization context still owns languages, translations and translation runs.
  """

  alias Storyarn.Sheets.Localization.Commands.Projection
  alias Storyarn.Sheets.Localization.Contracts.Content
  alias Storyarn.Sheets.Localization.Rules.WordCount

  defdelegate localizable_block_types(), to: Content
  defdelegate exported_block?(block), to: Content
  defdelegate localizable_block?(block), to: Content

  defdelegate word_count_for_block_value(value), to: WordCount, as: :for_block_value
  defdelegate word_count_for_block(type, value), to: WordCount, as: :for_block
  defdelegate word_count_for_name(name), to: WordCount, as: :for_name

  defdelegate extract_block(block), to: Projection

  defdelegate archive_restore_texts_for_sources(source_type, source_ids, reason),
    to: Projection

  defdelegate archive_texts_for_active_target_locales(project_id, source_type, source_ids, reason),
    to: Projection

  defdelegate lock_inventory!(project_id), to: Projection
  defdelegate extract_sheet_blocks(sheet_id), to: Projection
  defdelegate extract_sheet_blocks_for_sheets(sheet_ids), to: Projection
  defdelegate extract_block_tree(block_id), to: Projection
  defdelegate sync_sheet_names(project_id), to: Projection
  defdelegate delete_block_texts(block_id), to: Projection
  defdelegate delete_block_tree_texts(block_id), to: Projection
  defdelegate delete_block_texts_for_sheets(sheet_ids), to: Projection
  defdelegate delete_texts_for_source(source_type, source_id), to: Projection
  defdelegate purge_texts_for_source(source_type, source_id), to: Projection
  defdelegate purge_texts_for_sources(source_type, source_ids), to: Projection
end

defmodule Storyarn.Localization.Texts do
  @moduledoc """
  Public capability boundary for the localized-text inventory, translation
  state, runtime extraction and export-facing read models.
  """

  alias Storyarn.Localization.Texts.Commands.Create
  alias Storyarn.Localization.Texts.Commands.Extract
  alias Storyarn.Localization.Texts.Commands.Lifecycle
  alias Storyarn.Localization.Texts.Commands.Reconcile
  alias Storyarn.Localization.Texts.Commands.Update
  alias Storyarn.Localization.Texts.Commands.Upsert
  alias Storyarn.Localization.Texts.Commands.VersionRestore
  alias Storyarn.Localization.Texts.Queries.BatchTranslation
  alias Storyarn.Localization.Texts.Queries.ExportInventory
  alias Storyarn.Localization.Texts.Queries.RuntimeInventory
  alias Storyarn.Localization.Texts.Queries.SourceContext
  alias Storyarn.Localization.Texts.Queries.Texts, as: TextQueries
  alias Storyarn.Localization.Texts.Rules.HtmlHandler

  defdelegate list_texts(project_id, opts \\ []), to: TextQueries
  defdelegate count_texts(project_id, opts \\ []), to: TextQueries
  defdelegate get_text(project_id, id), to: TextQueries
  defdelegate get_text(project_id, id, opts), to: TextQueries
  defdelegate get_text!(project_id, id), to: TextQueries
  defdelegate source_context(text), to: SourceContext, as: :for_text
  defdelegate get_text_by_source(source_type, source_id, source_field, locale_code), to: TextQueries
  defdelegate get_text_by_source(source_type, source_id, source_field, locale_code, opts), to: TextQueries
  defdelegate get_texts_for_source(source_type, source_id), to: TextQueries
  defdelegate get_progress(project_id, locale_code), to: TextQueries

  defdelegate list_texts_for_batch_translation(project_id, opts \\ []), to: BatchTranslation
  defdelegate max_text_id_for_batch_translation(project_id, opts \\ []), to: BatchTranslation

  defdelegate create_text(project_id, attrs), to: Create
  defdelegate update_text(text, attrs), to: Update
  defdelegate upsert_text(project_id, attrs), to: Upsert

  defdelegate delete_texts_for_source(source_type, source_id), to: Lifecycle
  defdelegate delete_texts_for_sources(source_type, source_ids), to: Lifecycle
  defdelegate delete_texts_for_source_field(source_type, source_id, source_field), to: Lifecycle
  defdelegate archive_texts_for_source(source_type, source_id, reason \\ "source_deleted"), to: Lifecycle
  defdelegate archive_texts_for_sources(source_type, source_ids, reason), to: Lifecycle

  defdelegate archive_texts_for_active_target_locales(project_id, source_type, source_ids, reason),
    to: Lifecycle

  defdelegate purge_texts_for_source(source_type, source_id), to: Lifecycle
  defdelegate purge_texts_for_sources(source_type, source_ids), to: Lifecycle
  defdelegate reset_project_texts(project_id), to: Lifecycle

  def archive_sheet_texts(source_type, source_ids, reason)
      when source_type in ~w(block sheet) and is_list(source_ids) and
             reason in ~w(source_deleted source_field_removed source_not_runtime version_replaced) do
    Lifecycle.archive_texts_for_sources(source_type, source_ids, reason)
  end

  def archive_sheet_active_target_texts(project_id, source_type, source_ids, reason)
      when source_type in ~w(block sheet) and is_list(source_ids) and
             reason in ~w(source_deleted source_field_removed source_not_runtime version_replaced) do
    Lifecycle.archive_texts_for_active_target_locales(
      project_id,
      source_type,
      source_ids,
      reason
    )
  end

  def purge_flow_node_texts(node_ids) when is_list(node_ids), do: Lifecycle.purge_texts_for_sources("flow_node", node_ids)

  def purge_sheet_texts(source_type, source_ids) when source_type in ~w(block sheet) and is_list(source_ids),
    do: Lifecycle.purge_texts_for_sources(source_type, source_ids)

  defdelegate prepare_flow_version_texts(project_id, deleted_node_ids, target_node_ids),
    to: VersionRestore,
    as: :prepare_flow

  defdelegate restore_flow_version_texts(project_id, rows, id_maps),
    to: VersionRestore,
    as: :restore_flow

  defdelegate restore_sheet_version_texts(project_id, rows, id_maps),
    to: VersionRestore,
    as: :restore_sheet

  defdelegate batch_upsert_texts(project_id, entries), to: Reconcile
  defdelegate reconcile_project_texts(project_id, entries, source_keys), to: Reconcile
  defdelegate bulk_import_texts(attrs_list), to: Reconcile

  defdelegate list_texts_for_export(project_id, locale_codes, opts \\ []), to: ExportInventory
  defdelegate list_texts_for_canonical_snapshot(project_id), to: ExportInventory
  defdelegate texts_for_export_query(project_id, locale_codes, opts \\ []), to: ExportInventory
  defdelegate list_texts_for_backup(project_id, locale_codes), to: ExportInventory
  defdelegate list_target_locale_codes(project_id), to: ExportInventory
  defdelegate count_texts_for_export(project_id, locale_codes, opts), to: ExportInventory

  def export_readiness_by_locale(project_id, languages, opts \\ []),
    do: ExportInventory.export_readiness_by_locale(project_id, languages, opts)

  defdelegate export_readiness_by_locale(project_id, languages, opts, flow_node_ids),
    to: ExportInventory

  defdelegate flow_word_counts(project_id), to: RuntimeInventory
  defdelegate sheet_word_counts(project_id), to: RuntimeInventory

  defdelegate text_placeholders(text), to: HtmlHandler, as: :placeholders
  defdelegate placeholders(text), to: HtmlHandler
  defdelegate html?(text), to: HtmlHandler
  defdelegate pre_translate(text), to: HtmlHandler
  defdelegate post_translate(text), to: HtmlHandler
  defdelegate validate_placeholders(source_text, translated_text), to: HtmlHandler

  defdelegate extract_all(project_id), to: Extract
  defdelegate extract_locale(project_id, locale_code), to: Extract
  defdelegate lock_inventory!(project_id), to: Extract
  defdelegate lock_inventory_after_project_lock!(project_id), to: Extract
  defdelegate extract_flow_node(node), to: Extract
  defdelegate flow_node_texts_current?(node, project_id), to: Extract
  defdelegate flow_node_texts_current_ids(nodes, project_id), to: Extract
  defdelegate extract_block(block), to: Extract
  defdelegate sync_sheet_names(project_id), to: Extract
  defdelegate extract_flow_nodes(flow_id), to: Extract
  defdelegate extract_sheet_blocks(sheet_id), to: Extract
  defdelegate extract_sheet_blocks_for_sheets(sheet_ids), to: Extract
  defdelegate extract_block_tree(block_id), to: Extract
  defdelegate delete_flow_node_texts(node_id), to: Extract
  defdelegate delete_flow_node_texts_for_flows(flow_ids), to: Extract
  defdelegate delete_block_texts(block_id), to: Extract
  defdelegate delete_block_tree_texts(block_id), to: Extract
  defdelegate delete_block_texts_for_sheets(sheet_ids), to: Extract
end

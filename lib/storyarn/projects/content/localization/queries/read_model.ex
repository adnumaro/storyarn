defmodule Storyarn.Projects.LocalizationReadModel do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Projects.LocalizationRuntimeKey
  alias Storyarn.Projects.LocalizationSourceContract
  alias Storyarn.Projects.Persistence.BlockRecord, as: Block
  alias Storyarn.Projects.Persistence.FlowNodeRecord, as: FlowNode
  alias Storyarn.Projects.Persistence.FlowRecord, as: Flow
  alias Storyarn.Projects.Persistence.GlossaryEntryRecord, as: GlossaryEntry
  alias Storyarn.Projects.Persistence.LocalizedTextRecord, as: LocalizedText
  alias Storyarn.Projects.Persistence.ProjectLanguageRecord, as: ProjectLanguage
  alias Storyarn.Projects.Persistence.SheetRecord, as: Sheet
  alias Storyarn.Repo

  def list_languages(project_id) do
    Repo.all(
      from(language in ProjectLanguage,
        where: language.project_id == ^project_id and is_nil(language.archived_at),
        order_by: [asc: language.position, asc: language.name]
      )
    )
  end

  def list_languages_for_backup(project_id) do
    Repo.all(
      from(language in ProjectLanguage,
        where: language.project_id == ^project_id,
        order_by: [asc: language.position, asc: language.name]
      )
    )
  end

  def get_source_language(project_id) do
    Repo.one(
      from(language in ProjectLanguage,
        where:
          language.project_id == ^project_id and language.is_source == true and
            is_nil(language.archived_at)
      )
    )
  end

  def list_target_locale_codes(project_id) do
    Repo.all(
      from(language in ProjectLanguage,
        where:
          language.project_id == ^project_id and language.is_source == false and
            is_nil(language.archived_at),
        select: language.locale_code
      )
    )
  end

  def list_texts_for_export(project_id, locale_codes, opts \\ []) do
    project_id
    |> texts_for_export_query(locale_codes, opts)
    |> order_by([text],
      asc: text.source_type,
      asc: text.source_id,
      asc: text.source_field,
      asc: text.locale_code
    )
    |> Repo.all()
    |> maybe_attach_runtime_localization_keys(opts)
  end

  def list_texts_for_canonical_snapshot(project_id) do
    Repo.all(
      from(text in LocalizedText,
        where: text.project_id == ^project_id and is_nil(text.archived_at),
        order_by: [
          asc: text.source_type,
          asc: text.source_id,
          asc: text.source_field,
          asc: text.locale_code,
          asc: text.id
        ]
      )
    )
  end

  def list_texts_for_backup(project_id, locale_codes) do
    Repo.all(
      from(text in LocalizedText,
        where: text.project_id == ^project_id and text.locale_code in ^locale_codes,
        order_by: [asc: text.source_type, asc: text.source_id, asc: text.source_field, asc: text.locale_code]
      )
    )
  end

  def texts_for_export_query(project_id, locale_codes, opts \\ []) do
    query =
      from(text in LocalizedText,
        where: text.project_id == ^project_id and is_nil(text.archived_at)
      )

    query =
      case locale_codes do
        :all -> query
        codes -> where(query, [text], text.locale_code in ^codes)
      end

    scope_engine_export_sources(query, project_id, opts)
  end

  def count_texts_for_export(project_id, locale_codes, opts) do
    project_id
    |> texts_for_export_query(locale_codes, opts)
    |> Repo.aggregate(:count)
  end

  def export_readiness_by_locale(project_id, languages, opts, flow_node_ids) when is_list(flow_node_ids) do
    project_id
    |> export_readiness_query(languages)
    |> scope_engine_export_sources(project_id, opts, %{flow_node: flow_node_ids})
    |> Repo.all()
    |> Map.new()
  end

  def list_glossary_for_export(project_id) do
    Repo.all(
      from(entry in GlossaryEntry,
        where: entry.project_id == ^project_id,
        order_by: [asc: entry.source_term, asc: entry.target_locale]
      )
    )
  end

  defp export_readiness_query(project_id, languages) do
    from(text in LocalizedText,
      where:
        text.project_id == ^project_id and is_nil(text.archived_at) and
          text.locale_code in ^languages,
      group_by: text.locale_code,
      select:
        {text.locale_code,
         %{
           total: count(text.id),
           preview_ready:
             fragment(
               "count(*) FILTER (WHERE NULLIF(BTRIM(?), '') IS NOT NULL)",
               text.translated_text
             ),
           release_ready:
             fragment(
               "count(*) FILTER (WHERE NULLIF(BTRIM(?), '') IS NOT NULL AND ? = 'final' AND ? IS NOT NULL AND ? = ?)",
               text.translated_text,
               text.status,
               text.source_text_hash,
               text.translated_source_hash,
               text.source_text_hash
             )
         }}
    )
  end

  defp scope_engine_export_sources(query, project_id, opts, source_overrides \\ %{}) do
    %{flow_node: node_ids, block: block_ids, sheet: sheet_ids} =
      engine_export_source_ids(project_id, opts, source_overrides)

    source_scope =
      dynamic(
        [text],
        (text.source_type == "flow_node" and text.source_id in ^node_ids) or
          (text.source_type == "block" and text.source_id in ^block_ids) or
          (text.source_type == "sheet" and text.source_id in ^sheet_ids)
      )

    query = where(query, ^source_scope)

    case export_option(opts, :format, nil) do
      nil -> query
      format -> where(query, [text], text.content_role in ^LocalizationSourceContract.export_content_roles(format))
    end
  end

  defp engine_export_source_ids(project_id, opts, source_overrides) do
    {sheet_ids, block_ids} = engine_sheet_source_ids(project_id, opts)

    %{
      flow_node:
        Map.get_lazy(source_overrides, :flow_node, fn ->
          engine_flow_node_ids(project_id, opts)
        end),
      block: block_ids,
      sheet: sheet_ids
    }
  end

  defp engine_flow_node_ids(project_id, opts) do
    if export_option(opts, :include_flows, true) do
      query =
        from(node in FlowNode,
          join: flow in Flow,
          on: flow.id == node.flow_id,
          where:
            flow.project_id == ^project_id and is_nil(flow.deleted_at) and
              is_nil(node.deleted_at),
          select: node.id
        )

      query
      |> maybe_filter_export_parent_ids(:flow, export_option(opts, :flow_ids, :all))
      |> Repo.all()
    else
      []
    end
  end

  defp engine_sheet_source_ids(project_id, opts) do
    if export_option(opts, :include_sheets, true) do
      sheet_query =
        from(sheet in Sheet,
          where: sheet.project_id == ^project_id and is_nil(sheet.deleted_at),
          select: sheet.id
        )

      sheet_ids =
        sheet_query
        |> maybe_filter_export_parent_ids(:sheet, export_option(opts, :sheet_ids, :all))
        |> Repo.all()

      localizable_block_types = LocalizationSourceContract.localizable_block_types()

      block_ids =
        from(block in Block,
          where: block.sheet_id in ^sheet_ids and block.type in ^localizable_block_types,
          select: %{
            id: block.id,
            type: block.type,
            is_constant: block.is_constant,
            variable_name: block.variable_name,
            deleted_at: block.deleted_at
          }
        )
        |> Repo.all()
        |> Enum.filter(&LocalizationSourceContract.localizable_block?/1)
        |> Enum.map(& &1.id)

      {sheet_ids, block_ids}
    else
      {[], []}
    end
  end

  defp maybe_filter_export_parent_ids(query, _binding, :all), do: query
  defp maybe_filter_export_parent_ids(query, _binding, []), do: where(query, false)
  defp maybe_filter_export_parent_ids(query, :flow, ids), do: where(query, [_node, flow], flow.id in ^ids)
  defp maybe_filter_export_parent_ids(query, :sheet, ids), do: where(query, [sheet], sheet.id in ^ids)

  defp export_option(opts, key, default) when is_list(opts), do: Keyword.get(opts, key, default)
  defp export_option(opts, key, default) when is_map(opts), do: Map.get(opts, key, default)

  defp maybe_attach_runtime_localization_keys(texts, opts) do
    if export_option(opts, :format, :storyarn) in [:ink, :godot, :unreal, :articy] do
      attach_runtime_localization_keys(texts)
    else
      texts
    end
  end

  defp attach_runtime_localization_keys([]), do: []

  defp attach_runtime_localization_keys(texts) do
    refs =
      texts
      |> Enum.group_by(& &1.source_type, & &1.source_id)
      |> Enum.reduce(%{}, fn
        {"flow_node", ids}, acc -> Map.merge(acc, flow_node_runtime_refs(ids))
        {"block", ids}, acc -> Map.merge(acc, block_runtime_refs(ids))
        {"sheet", ids}, acc -> Map.merge(acc, sheet_runtime_refs(ids))
        {_source_type, _ids}, acc -> acc
      end)

    Enum.flat_map(texts, fn text ->
      case Map.fetch(refs, {text.source_type, text.source_id}) do
        {:ok, source_ref} when is_binary(source_ref) and source_ref != "" ->
          [%{text | localization_key: LocalizationRuntimeKey.key(text.source_type, source_ref, text.source_field)}]

        _missing_or_invalid_source ->
          []
      end
    end)
  end

  defp flow_node_runtime_refs(ids) do
    from(node in FlowNode,
      where: node.id in ^Enum.uniq(ids),
      select: {node.id, fragment("?->>'localization_id'", node.data)}
    )
    |> Repo.all()
    |> Enum.flat_map(fn
      {id, source_ref} when is_binary(source_ref) and source_ref != "" -> [{{"flow_node", id}, source_ref}]
      _invalid_source -> []
    end)
    |> Map.new()
  end

  defp block_runtime_refs(ids) do
    from(block in Block,
      join: sheet in Sheet,
      on: sheet.id == block.sheet_id,
      where: block.id in ^Enum.uniq(ids),
      select: {block.id, sheet.shortcut, block.variable_name}
    )
    |> Repo.all()
    |> Enum.flat_map(fn {id, sheet_shortcut, variable_name} ->
      case safe_qualified_block_ref(sheet_shortcut, variable_name) do
        nil -> []
        source_ref -> [{{"block", id}, source_ref}]
      end
    end)
    |> Map.new()
  end

  defp sheet_runtime_refs(ids) do
    from(sheet in Sheet,
      where: sheet.id in ^Enum.uniq(ids),
      select: {sheet.id, sheet.shortcut}
    )
    |> Repo.all()
    |> Enum.flat_map(fn
      {id, source_ref} when is_binary(source_ref) and source_ref != "" -> [{{"sheet", id}, source_ref}]
      _invalid_source -> []
    end)
    |> Map.new()
  end

  defp safe_qualified_block_ref(sheet_shortcut, variable_name) do
    LocalizationRuntimeKey.qualified_block_ref!(sheet_shortcut, variable_name)
  rescue
    ArgumentError -> nil
  end
end

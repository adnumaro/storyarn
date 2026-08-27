defmodule Storyarn.Localization.Texts.Queries.ExportInventory do
  @moduledoc "Read-side inventory and readiness queries for localization exports."

  import Ecto.Query, warn: false

  alias Storyarn.Localization.LocalizedText
  alias Storyarn.Localization.RuntimeKey
  alias Storyarn.Localization.SourceContract
  alias Storyarn.Localization.Texts.Projections.BlockRecord
  alias Storyarn.Localization.Texts.Projections.FlowNodeRecord
  alias Storyarn.Localization.Texts.Projections.FlowRecord
  alias Storyarn.Localization.Texts.Projections.LanguageRecord
  alias Storyarn.Localization.Texts.Projections.SheetRecord
  alias Storyarn.Repo

  @doc """
  Lists localized texts for export, filtered by locale codes.
  """
  def list_texts_for_export(project_id, locale_codes, opts \\ []) do
    project_id
    |> texts_for_export_query(locale_codes, opts)
    |> order_by([lt], asc: lt.source_type, asc: lt.source_id, asc: lt.source_field, asc: lt.locale_code)
    |> Repo.all()
    |> maybe_attach_runtime_localization_keys(opts)
  end

  @doc """
  Lists every active localized-text row for canonical snapshot capture.

  This inventory intentionally does not filter by locale registration, source
  existence, source lifecycle, or runtime source type. Canonical snapshots must
  preserve every active row exactly, including inconsistent stored state.
  """
  @spec list_texts_for_canonical_snapshot(integer()) :: [LocalizedText.t()]
  def list_texts_for_canonical_snapshot(project_id) do
    Repo.all(
      from(lt in LocalizedText,
        where: lt.project_id == ^project_id and is_nil(lt.archived_at),
        order_by: [
          asc: lt.source_type,
          asc: lt.source_id,
          asc: lt.source_field,
          asc: lt.locale_code,
          asc: lt.id
        ]
      )
    )
  end

  @doc "Returns the active, source-scoped localized-text query used by engine exports."
  def texts_for_export_query(project_id, locale_codes, opts \\ []) do
    query =
      from(lt in LocalizedText,
        where: lt.project_id == ^project_id and is_nil(lt.archived_at)
      )

    query =
      case locale_codes do
        :all -> query
        codes -> where(query, [lt], lt.locale_code in ^codes)
      end

    scope_engine_export_sources(query, project_id, opts)
  end

  @doc "Lists active and archived localized texts for native backups."
  def list_texts_for_backup(project_id, locale_codes) do
    Repo.all(
      from(lt in LocalizedText,
        where: lt.project_id == ^project_id and lt.locale_code in ^locale_codes,
        order_by: [asc: lt.source_type, asc: lt.source_id, asc: lt.source_field, asc: lt.locale_code]
      )
    )
  end

  @doc """
  Lists target (non-source) locale codes for a project.
  Used by the export Validator.
  """
  def list_target_locale_codes(project_id) do
    Repo.all(
      from(l in LanguageRecord,
        where: l.project_id == ^project_id and l.is_source == false and is_nil(l.archived_at),
        select: l.locale_code
      )
    )
  end

  @doc "Returns active localization export readiness counts grouped by target locale."
  def export_readiness_by_locale(project_id, languages, opts \\ []) do
    export_readiness_by_locale(project_id, languages, opts, :all)
  end

  @doc """
  Returns active localization export readiness counts for an explicit effective
  flow-node inventory while retaining the selected sheet scope from the export
  options.
  """
  def export_readiness_by_locale(project_id, languages, opts, flow_node_ids) when is_list(flow_node_ids) do
    project_id
    |> export_readiness_query(languages)
    |> scope_engine_export_sources(project_id, opts, %{flow_node: flow_node_ids})
    |> Repo.all()
    |> Map.new()
  end

  def export_readiness_by_locale(project_id, languages, opts, :all) do
    project_id
    |> export_readiness_query(languages)
    |> scope_engine_export_sources(project_id, opts)
    |> Repo.all()
    |> Map.new()
  end

  defp export_readiness_query(project_id, languages) do
    from(lt in LocalizedText,
      where:
        lt.project_id == ^project_id and is_nil(lt.archived_at) and
          lt.locale_code in ^languages,
      group_by: lt.locale_code,
      select:
        {lt.locale_code,
         %{
           total: count(lt.id),
           preview_ready:
             fragment(
               "count(*) FILTER (WHERE NULLIF(BTRIM(?), '') IS NOT NULL)",
               lt.translated_text
             ),
           release_ready:
             fragment(
               "count(*) FILTER (WHERE NULLIF(BTRIM(?), '') IS NOT NULL AND ? = 'final' AND ? IS NOT NULL AND ? = ?)",
               lt.translated_text,
               lt.status,
               lt.source_text_hash,
               lt.translated_source_hash,
               lt.source_text_hash
             )
         }}
    )
  end

  @doc "Counts active localized texts in the same source scope as an engine export."
  def count_texts_for_export(project_id, locale_codes, opts) do
    project_id
    |> texts_for_export_query(locale_codes, opts)
    |> Repo.aggregate(:count)
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

    # Filtering by content role is an ENGINE-export concern: each engine can only
    # address some of the roles. Callers that pass no format are not exporting to
    # an engine (snapshots, templates, recovery) and want every role.
    #
    # This used to default the format to `:storyarn`, whose entry in the role map
    # was the full set — so "no format" and "all roles" happened to coincide.
    # Once that format was removed the default resolved to `[]` instead, and the
    # filter silently matched nothing.
    case export_option(opts, :format, nil) do
      nil -> query
      format -> where(query, [text], text.content_role in ^SourceContract.export_content_roles(format))
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
        from(n in FlowNodeRecord,
          join: f in FlowRecord,
          on: f.id == n.flow_id,
          where: f.project_id == ^project_id and is_nil(f.deleted_at) and is_nil(n.deleted_at),
          select: n.id
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
        from(s in SheetRecord,
          where: s.project_id == ^project_id and is_nil(s.deleted_at),
          select: s.id
        )

      sheet_ids =
        sheet_query
        |> maybe_filter_export_parent_ids(:sheet, export_option(opts, :sheet_ids, :all))
        |> Repo.all()

      localizable_block_types = SourceContract.localizable_block_types()

      block_ids =
        from(b in BlockRecord,
          where: b.sheet_id in ^sheet_ids and b.type in ^localizable_block_types,
          select: %{
            id: b.id,
            type: b.type,
            is_constant: b.is_constant,
            variable_name: b.variable_name,
            deleted_at: b.deleted_at
          }
        )
        |> Repo.all()
        |> Enum.filter(&SourceContract.localizable_block?/1)
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
          [%{text | localization_key: RuntimeKey.key(text.source_type, source_ref, text.source_field)}]

        _missing_or_invalid_source ->
          []
      end
    end)
  end

  defp maybe_attach_runtime_localization_keys(texts, opts) do
    if export_option(opts, :format, :storyarn) in [:ink, :godot, :unreal, :articy],
      do: attach_runtime_localization_keys(texts),
      else: texts
  end

  defp flow_node_runtime_refs(ids) do
    ids = Enum.uniq(ids)

    from(node in FlowNodeRecord,
      where: node.id in ^ids,
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
    ids = Enum.uniq(ids)

    from(block in BlockRecord,
      join: sheet in SheetRecord,
      on: sheet.id == block.sheet_id,
      where: block.id in ^ids,
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
    ids = Enum.uniq(ids)

    from(sheet in SheetRecord,
      where: sheet.id in ^ids,
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
    RuntimeKey.qualified_block_ref!(sheet_shortcut, variable_name)
  rescue
    ArgumentError -> nil
  end
end

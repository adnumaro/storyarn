defmodule Storyarn.Localization.TextCrud do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Assets.Asset
  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Localization.LocalizedText
  alias Storyarn.Localization.ProjectLanguage
  alias Storyarn.Localization.RuntimeKey
  alias Storyarn.Localization.SourceContract
  alias Storyarn.References.ProjectReferenceIntegrity
  alias Storyarn.Repo
  alias Storyarn.Shared.MapUtils
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Sheets.Block
  alias Storyarn.Sheets.Sheet

  # =============================================================================
  # Queries
  # =============================================================================

  @doc """
  Lists all localized texts for a project, optionally filtered.

  Options:
  - `:locale_code` - Filter by locale
  - `:status` - Filter by status
  - `:source_type` - Filter by source type
  - `:speaker_sheet_id` - Filter by speaker
  - `:search` - Search in source_text and translated_text
  - `:limit` - Max results
  - `:offset` - Offset for pagination
  """
  def list_texts(project_id, opts \\ []) do
    from(t in LocalizedText,
      where: t.project_id == ^project_id,
      order_by: [asc: t.source_type, asc: t.source_id, asc: t.source_field]
    )
    |> maybe_filter_archived(opts[:include_archived])
    |> maybe_filter_locale(opts[:locale_code])
    |> maybe_filter_status(opts[:status])
    |> maybe_filter_source_type(opts[:source_type])
    |> maybe_filter_speaker(opts[:speaker_sheet_id])
    |> maybe_search(opts[:search])
    |> maybe_paginate(opts[:limit], opts[:offset])
    |> Repo.all()
  end

  @doc """
  Counts localized texts for a project, optionally filtered.
  Accepts the same filter options as `list_texts/2`.
  """
  def count_texts(project_id, opts \\ []) do
    from(t in LocalizedText,
      where: t.project_id == ^project_id,
      select: count(t.id)
    )
    |> maybe_filter_archived(opts[:include_archived])
    |> maybe_filter_locale(opts[:locale_code])
    |> maybe_filter_status(opts[:status])
    |> maybe_filter_source_type(opts[:source_type])
    |> maybe_filter_speaker(opts[:speaker_sheet_id])
    |> maybe_search(opts[:search])
    |> Repo.one!()
  end

  @doc """
  Lists localized texts for batch translation using a stable id cursor.

  This is intentionally separate from `list_texts/2`, whose default ordering is
  optimized for UI grouping rather than mutation-safe batch processing.
  """
  def list_texts_for_batch_translation(project_id, opts \\ []) do
    from(t in LocalizedText,
      where: t.project_id == ^project_id,
      order_by: [asc: t.id]
    )
    |> maybe_filter_archived(opts[:include_archived])
    |> maybe_filter_locale(opts[:locale_code])
    |> maybe_filter_status(opts[:status])
    |> maybe_filter_source_type(opts[:source_type])
    |> maybe_filter_after_id(opts[:after_id])
    |> maybe_filter_max_id(opts[:max_id])
    |> maybe_paginate(opts[:limit], nil)
    |> Repo.all()
  end

  def max_text_id_for_batch_translation(project_id, opts \\ []) do
    from(t in LocalizedText,
      where: t.project_id == ^project_id,
      select: max(t.id)
    )
    |> maybe_filter_archived(opts[:include_archived])
    |> maybe_filter_locale(opts[:locale_code])
    |> maybe_filter_status(opts[:status])
    |> maybe_filter_source_type(opts[:source_type])
    |> Repo.one()
  end

  def get_text(project_id, id) do
    Repo.one(from(t in LocalizedText, where: t.id == ^id and t.project_id == ^project_id and is_nil(t.archived_at)))
  end

  def get_text!(project_id, id) do
    Repo.one!(from(t in LocalizedText, where: t.id == ^id and t.project_id == ^project_id and is_nil(t.archived_at)))
  end

  @doc """
  Gets a specific localized text by its composite key.
  """
  def get_text_by_source(source_type, source_id, source_field, locale_code) do
    get_text_by_source(source_type, source_id, source_field, locale_code, [])
  end

  def get_text_by_source(source_type, source_id, source_field, locale_code, opts) do
    from(t in LocalizedText,
      where:
        t.source_type == ^source_type and t.source_id == ^source_id and t.source_field == ^source_field and
          t.locale_code == ^locale_code
    )
    |> maybe_filter_archived(opts[:include_archived])
    |> Repo.one()
  end

  @doc """
  Gets all localized texts for a source entity across all locales.
  """
  def get_texts_for_source(source_type, source_id) do
    Repo.all(
      from(t in LocalizedText,
        where: t.source_type == ^source_type and t.source_id == ^source_id and is_nil(t.archived_at),
        order_by: [asc: t.source_field, asc: t.locale_code]
      )
    )
  end

  @doc """
  Gets translation progress stats for a project and locale.
  Returns `%{total: integer, pending: integer, draft: integer, in_progress: integer, review: integer, final: integer}`.
  """
  def get_progress(project_id, locale_code) do
    counts =
      from(t in LocalizedText,
        where: t.project_id == ^project_id and t.locale_code == ^locale_code and is_nil(t.archived_at),
        group_by: t.status,
        select: {t.status, count(t.id)}
      )
      |> Repo.all()
      |> Map.new()

    stale =
      Repo.one!(
        from(t in LocalizedText,
          where:
            t.project_id == ^project_id and t.locale_code == ^locale_code and
              is_nil(t.archived_at) and
              not is_nil(t.translated_text) and t.translated_text != "" and
              (is_nil(t.translated_source_hash) or t.translated_source_hash != t.source_text_hash),
          select: count(t.id)
        )
      )

    then(counts, fn counts ->
      total =
        counts |> Map.values() |> Enum.sum()

      %{
        total: total,
        pending: Map.get(counts, "pending", 0),
        draft: Map.get(counts, "draft", 0),
        in_progress: Map.get(counts, "in_progress", 0),
        review: Map.get(counts, "review", 0),
        final: Map.get(counts, "final", 0),
        stale: stale
      }
    end)
  end

  # =============================================================================
  # Mutations
  # =============================================================================

  def create_text(project_id, attrs) do
    attrs =
      attrs
      |> MapUtils.stringify_keys()
      |> apply_source_metadata()
      |> prepare_create_translation_attrs()

    %LocalizedText{project_id: project_id}
    |> LocalizedText.create_changeset(attrs)
    |> Repo.insert()
  end

  def update_text(%LocalizedText{} = text, attrs) do
    attrs = MapUtils.stringify_keys(attrs)

    fn ->
      update_text_in_transaction(text, attrs)
    end
    |> Repo.transaction()
    |> normalize_update_text_result(text, attrs)
  end

  @doc """
  Upserts a localized text by its composite key.
  Creates if not exists, updates source_text if hash changed.
  Returns `{:ok, localized_text}` or `{:error, changeset}`.
  """
  def upsert_text(project_id, attrs) do
    do_upsert_text(project_id, attrs, 3)
  end

  defp do_upsert_text(project_id, attrs, retries_left) do
    attrs = attrs |> MapUtils.stringify_keys() |> apply_source_metadata()

    source_type = attrs["source_type"]
    source_id = attrs["source_id"]
    source_field = attrs["source_field"]
    locale_code = attrs["locale_code"]

    # Use insert with on_conflict to avoid TOCTOU race on concurrent extractions.
    # First try to insert; on conflict, fall back to update with status downgrade logic.
    changeset = LocalizedText.create_changeset(%LocalizedText{project_id: project_id}, attrs)

    case Repo.insert(changeset,
           on_conflict: :nothing,
           conflict_target: [:source_type, :source_id, :source_field, :locale_code]
         ) do
      {:ok, %{id: nil}} ->
        resolve_upsert_conflict(project_id, attrs, source_type, source_id, source_field, locale_code, retries_left)

      {:ok, text} ->
        {:ok, text}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Archives all localized texts for a given source entity.
  Translation work remains recoverable when the source is restored.
  """
  def delete_texts_for_source(source_type, source_id) do
    archive_texts_for_source(source_type, source_id, "source_deleted")
  end

  @doc "Deletes localized texts for a collection of source entities."
  def delete_texts_for_sources(_source_type, []), do: {0, nil}

  def delete_texts_for_sources(source_type, source_ids) do
    archive_texts_for_sources(source_type, source_ids, "source_deleted")
  end

  @doc """
  Archives all localized texts for a source field removed from the runtime contract.
  """
  def delete_texts_for_source_field(source_type, source_id, source_field) do
    now = TimeHelpers.now()

    Repo.update_all(
      from(t in LocalizedText,
        where:
          t.source_type == ^source_type and t.source_id == ^source_id and
            t.source_field == ^source_field and is_nil(t.archived_at)
      ),
      set: [archived_at: now, archive_reason: "source_field_removed", updated_at: now],
      inc: [lock_version: 1]
    )
  end

  def archive_texts_for_source(source_type, source_id, reason \\ "source_deleted") do
    archive_texts_for_sources(source_type, [source_id], reason)
  end

  def archive_texts_for_sources(_source_type, [], _reason), do: {0, nil}

  def archive_texts_for_sources(source_type, source_ids, reason) do
    now = TimeHelpers.now()

    Repo.update_all(
      from(t in LocalizedText,
        where:
          t.source_type == ^source_type and t.source_id in ^source_ids and
            is_nil(t.archived_at)
      ),
      set: [archived_at: now, archive_reason: reason, updated_at: now],
      inc: [lock_version: 1]
    )
  end

  @doc """
  Archives active localized texts only for the project's active target locales.

  Version restore uses this narrower operation so translations retained under
  archived project languages are not mutated when the snapshot contract covers
  only active target languages.
  """
  def archive_texts_for_active_target_locales(_project_id, _source_type, [], _reason), do: {0, nil}

  def archive_texts_for_active_target_locales(project_id, source_type, source_ids, reason) do
    now = TimeHelpers.now()

    active_target_locales =
      from(language in ProjectLanguage,
        where:
          language.project_id == ^project_id and language.is_source == false and
            is_nil(language.archived_at),
        select: language.locale_code
      )

    Repo.update_all(
      from(text in LocalizedText,
        where:
          text.project_id == ^project_id and text.source_type == ^source_type and
            text.source_id in ^source_ids and is_nil(text.archived_at) and
            text.locale_code in subquery(active_target_locales)
      ),
      set: [archived_at: now, archive_reason: reason, updated_at: now],
      inc: [lock_version: 1]
    )
  end

  def purge_texts_for_source(source_type, source_id) do
    purge_texts_for_sources(source_type, [source_id])
  end

  def purge_texts_for_sources(_source_type, []), do: {0, nil}

  def purge_texts_for_sources(source_type, source_ids) do
    Repo.delete_all(
      from(t in LocalizedText,
        where: t.source_type == ^source_type and t.source_id in ^source_ids
      )
    )
  end

  # =============================================================================
  # Private
  # =============================================================================

  defp update_text_in_transaction(text, attrs) do
    # localized_texts activity triggers update the project row. Lock it for
    # update before touching localized_texts. Besides keeping normal writers
    # project-first, this prevents a DDL migration that already owns every
    # project row from deadlocking while it upgrades its localized_texts lock.
    # The caller's project_id is only an identity hint: the row is re-read and
    # ownership-checked below while locked.
    case ProjectReferenceIntegrity.lock_active_project(text.project_id, :update) do
      {:ok, _project} -> :ok
      {:error, reason} -> Repo.rollback(reason)
    end

    locked_text =
      Repo.one(
        from(current in LocalizedText,
          where:
            current.id == ^text.id and current.project_id == ^text.project_id and
              is_nil(current.archived_at),
          lock: "FOR UPDATE"
        )
      ) || Repo.rollback(:localized_text_not_active)

    attrs =
      attrs
      |> lock_and_normalize_translation_references!(locked_text)
      |> prepare_translation_attrs(locked_text)

    # Build from the caller's struct so optimistic_lock/3 still detects a stale
    # editor. The locked row supplies the final-state reference validation.
    case text
         |> LocalizedText.update_changeset(attrs)
         |> Repo.update(stale_error_field: :lock_version) do
      {:ok, updated_text} -> updated_text
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp normalize_update_text_result({:ok, %LocalizedText{} = text}, _original, _attrs), do: {:ok, text}

  defp normalize_update_text_result({:error, %Ecto.Changeset{} = changeset}, _text, _attrs), do: {:error, changeset}

  defp normalize_update_text_result({:error, reason}, text, attrs) do
    {field, message} = update_text_error(reason)

    changeset =
      text
      |> LocalizedText.update_changeset(attrs)
      |> Ecto.Changeset.add_error(field, message, reason: reason)

    {:error, changeset}
  end

  defp update_text_error(:localized_text_not_found), do: {:base, "no longer exists"}

  defp update_text_error(:localized_text_not_active), do: {:base, "is archived and can no longer be edited"}

  defp update_text_error(:project_not_found), do: {:base, "belongs to a project that no longer exists"}

  defp update_text_error(:project_not_active), do: {:base, "belongs to a project in trash"}

  defp update_text_error({:invalid_project_id, _project_id}), do: {:base, "belongs to an invalid project"}

  defp update_text_error({:immutable_localization_reference, :speaker_sheet_id}),
    do: {:speaker_sheet_id, "cannot be changed manually"}

  defp update_text_error({:invalid_project_reference, :speaker_sheet_id, _value}),
    do: {:speaker_sheet_id, "must reference an active sheet in this project"}

  defp update_text_error({:invalid_project_reference, :vo_asset_id, _value}),
    do: {:vo_asset_id, "must reference an asset in this project"}

  defp update_text_error({:invalid_voiceover_asset_type, _asset_id}), do: {:vo_asset_id, "must reference an audio asset"}

  defp update_text_error(_reason), do: {:base, "could not be updated"}

  defp lock_and_normalize_translation_references!(attrs, text) do
    if Map.has_key?(attrs, "speaker_sheet_id") do
      Repo.rollback({:immutable_localization_reference, :speaker_sheet_id})
    end

    speaker_sheet_id =
      text.speaker_sheet_id

    vo_asset_id =
      if Map.has_key?(attrs, "vo_asset_id"),
        do: attrs["vo_asset_id"],
        else: text.vo_asset_id

    case ProjectReferenceIntegrity.lock_active_references(text.project_id, [
           {:sheet, :speaker_sheet_id, speaker_sheet_id},
           {:asset, :vo_asset_id, vo_asset_id}
         ]) do
      {:ok, [normalized_speaker_sheet_id, normalized_vo_asset_id]} ->
        validate_voiceover_asset_type!(normalized_vo_asset_id)

        attrs
        |> maybe_put_normalized_reference(
          "speaker_sheet_id",
          normalized_speaker_sheet_id
        )
        |> maybe_put_normalized_reference("vo_asset_id", normalized_vo_asset_id)

      {:error, reason} ->
        Repo.rollback(reason)
    end
  end

  defp maybe_put_normalized_reference(attrs, key, value) do
    if Map.has_key?(attrs, key), do: Map.put(attrs, key, value), else: attrs
  end

  defp validate_voiceover_asset_type!(nil), do: :ok

  defp validate_voiceover_asset_type!(asset_id) do
    case Repo.one(
           from(asset in Asset,
             where:
               asset.id == ^asset_id and
                 like(asset.content_type, "audio/%"),
             select: asset.id
           )
         ) do
      ^asset_id -> :ok
      nil -> Repo.rollback({:invalid_voiceover_asset_type, asset_id})
    end
  end

  defp update_source_text(%LocalizedText{} = existing, attrs) do
    new_hash = attrs["source_text_hash"]

    if new_hash && new_hash != existing.source_text_hash do
      new_status = if present?(existing.translated_text), do: "review", else: "pending"

      existing
      |> LocalizedText.source_update_changeset(%{
        "source_text" => attrs["source_text"],
        "source_text_hash" => new_hash,
        "word_count" => attrs["word_count"],
        "speaker_sheet_id" => attrs["speaker_sheet_id"],
        "content_role" => attrs["content_role"],
        "vo_eligible" => attrs["vo_eligible"],
        "vo_status" => invalidated_vo_status(existing),
        "status" => new_status,
        "archived_at" => nil,
        "archive_reason" => nil
      })
      |> Repo.update(stale_error_field: :lock_version)
    else
      # Hash unchanged — keep the runtime classification in sync as well.
      if is_nil(existing.archived_at) and
           attrs["speaker_sheet_id"] == existing.speaker_sheet_id and
           attrs["content_role"] == existing.content_role and
           attrs["vo_eligible"] == existing.vo_eligible do
        {:ok, existing}
      else
        existing
        |> LocalizedText.source_update_changeset(%{
          "speaker_sheet_id" => attrs["speaker_sheet_id"],
          "content_role" => attrs["content_role"],
          "vo_eligible" => attrs["vo_eligible"],
          "archived_at" => nil,
          "archive_reason" => nil
        })
        |> Repo.update(stale_error_field: :lock_version)
      end
    end
  end

  defp maybe_filter_locale(query, nil), do: query

  defp maybe_filter_locale(query, locale_code) do
    where(query, [t], t.locale_code == ^locale_code)
  end

  defp maybe_filter_archived(query, true), do: query
  defp maybe_filter_archived(query, _include_archived), do: where(query, [t], is_nil(t.archived_at))

  defp maybe_filter_status(query, nil), do: query

  defp maybe_filter_status(query, status) do
    where(query, [t], t.status == ^status)
  end

  defp maybe_filter_source_type(query, nil), do: query

  defp maybe_filter_source_type(query, source_type) do
    where(query, [t], t.source_type == ^source_type)
  end

  defp maybe_filter_after_id(query, nil), do: query

  defp maybe_filter_after_id(query, after_id) do
    where(query, [t], t.id > ^after_id)
  end

  defp maybe_filter_max_id(query, nil), do: query

  defp maybe_filter_max_id(query, max_id) do
    where(query, [t], t.id <= ^max_id)
  end

  defp maybe_filter_speaker(query, nil), do: query

  defp maybe_filter_speaker(query, speaker_sheet_id) do
    where(query, [t], t.speaker_sheet_id == ^speaker_sheet_id)
  end

  defp maybe_search(query, nil), do: query
  defp maybe_search(query, ""), do: query

  defp maybe_search(query, search) do
    sanitized = Storyarn.Shared.SearchHelpers.sanitize_like_query(search)
    pattern = "%#{sanitized}%"

    where(
      query,
      [t],
      ilike(t.source_text, ^pattern) or ilike(t.translated_text, ^pattern)
    )
  end

  defp maybe_paginate(query, nil, _offset), do: query

  defp maybe_paginate(query, limit, offset) do
    query
    |> limit(^limit)
    |> offset(^(offset || 0))
  end

  # =============================================================================
  # Export / Import helpers
  # =============================================================================

  @doc """
  Lists localized texts for export, filtered by locale codes.
  """
  def list_texts_for_export(project_id, locale_codes, opts \\ []) do
    from(lt in LocalizedText,
      where:
        lt.project_id == ^project_id and lt.locale_code in ^locale_codes and
          is_nil(lt.archived_at),
      order_by: [asc: lt.source_type, asc: lt.source_id, asc: lt.source_field, asc: lt.locale_code]
    )
    |> scope_engine_export_sources(project_id, opts)
    |> Repo.all()
    |> maybe_attach_runtime_localization_keys(opts)
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
      from(l in ProjectLanguage,
        where: l.project_id == ^project_id and l.is_source == false and is_nil(l.archived_at),
        select: l.locale_code
      )
    )
  end

  @doc "Returns active localization export readiness counts grouped by target locale."
  def export_readiness_by_locale(project_id, languages, opts \\ []) do
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
    |> scope_engine_export_sources(project_id, opts)
    |> Repo.all()
    |> Map.new()
  end

  @doc "Counts active localized texts in the same source scope as an engine export."
  def count_texts_for_export(project_id, locale_codes, opts) do
    query =
      from(lt in LocalizedText,
        where: lt.project_id == ^project_id and is_nil(lt.archived_at)
      )

    query =
      case locale_codes do
        :all -> query
        codes -> where(query, [lt], lt.locale_code in ^codes)
      end

    query
    |> scope_engine_export_sources(project_id, opts)
    |> Repo.aggregate(:count)
  end

  defp scope_engine_export_sources(query, project_id, opts) do
    %{flow_node: node_ids, block: block_ids, sheet: sheet_ids} =
      engine_export_source_ids(project_id, opts)

    source_scope =
      dynamic(
        [text],
        (text.source_type == "flow_node" and text.source_id in ^node_ids) or
          (text.source_type == "block" and text.source_id in ^block_ids) or
          (text.source_type == "sheet" and text.source_id in ^sheet_ids)
      )

    content_roles =
      opts
      |> export_option(:format, :storyarn)
      |> SourceContract.export_content_roles()

    query
    |> where(^source_scope)
    |> where([text], text.content_role in ^content_roles)
  end

  defp engine_export_source_ids(project_id, opts) do
    {sheet_ids, block_ids} = engine_sheet_source_ids(project_id, opts)

    %{
      flow_node: engine_flow_node_ids(project_id, opts),
      block: block_ids,
      sheet: sheet_ids
    }
  end

  defp engine_flow_node_ids(project_id, opts) do
    if export_option(opts, :include_flows, true) do
      query =
        from(n in FlowNode,
          join: f in Flow,
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
        from(s in Sheet,
          where: s.project_id == ^project_id and is_nil(s.deleted_at),
          select: s.id
        )

      sheet_ids =
        sheet_query
        |> maybe_filter_export_parent_ids(:sheet, export_option(opts, :sheet_ids, :all))
        |> Repo.all()

      localizable_block_types = SourceContract.localizable_block_types()

      block_ids =
        from(b in Block,
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

    from(node in FlowNode,
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

    from(block in Block,
      join: sheet in Sheet,
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

    from(sheet in Sheet,
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

  defp stale_lock_error?(%Ecto.Changeset{errors: errors}), do: Keyword.has_key?(errors, :lock_version)
  defp stale_lock_error?(_changeset), do: false

  defp maybe_retry_upsert(error, changeset, project_id, attrs, retries_left) do
    if retries_left > 0 and stale_lock_error?(changeset),
      do: do_upsert_text(project_id, attrs, retries_left - 1),
      else: error
  end

  defp resolve_upsert_conflict(project_id, attrs, source_type, source_id, source_field, locale_code, retries_left) do
    existing = get_text_by_source(source_type, source_id, source_field, locale_code, include_archived: true)

    case if(existing, do: update_source_text(existing, attrs), else: create_text(project_id, attrs)) do
      {:error, changeset} = error -> maybe_retry_upsert(error, changeset, project_id, attrs, retries_left)
      result -> result
    end
  end

  @doc """
  Batch-upserts localized texts for a project using insert_all with on_conflict.

  Each entry in `entries` should be a map with string keys:
  `source_type`, `source_id`, `source_field`, `source_text`, `source_text_hash`,
  `locale_code`, `word_count`, `content_role`, `vo_eligible`, and optionally
  `speaker_sheet_id`.

  On conflict (same source_type/source_id/source_field/locale_code):
  - Updates source_text, source_text_hash, word_count, speaker_sheet_id
  - Marks any existing translation as needing review when source_text_hash changes

  Returns the total number of entries processed.
  """
  @spec batch_upsert_texts(integer(), [map()]) :: non_neg_integer()
  def batch_upsert_texts(_project_id, []), do: 0

  def batch_upsert_texts(project_id, entries) when is_list(entries) do
    if Repo.in_transaction?() do
      do_batch_upsert_texts(project_id, entries)
    else
      {:ok, count} = Repo.transaction(fn -> do_batch_upsert_texts(project_id, entries) end)
      count
    end
  end

  defp do_batch_upsert_texts(project_id, entries) do
    now = TimeHelpers.now()

    rows =
      Enum.map(entries, fn attrs ->
        attrs = apply_source_metadata(attrs)

        %{
          project_id: project_id,
          source_type: attrs["source_type"],
          source_id: attrs["source_id"],
          source_field: attrs["source_field"],
          source_text: attrs["source_text"],
          source_text_hash: attrs["source_text_hash"],
          locale_code: attrs["locale_code"],
          word_count: attrs["word_count"],
          speaker_sheet_id: attrs["speaker_sheet_id"],
          content_role: attrs["content_role"],
          vo_eligible: attrs["vo_eligible"],
          status: "pending",
          vo_status: "none",
          machine_translated: false,
          inserted_at: now,
          updated_at: now
        }
      end)

    rows
    |> Enum.chunk_every(500)
    |> Enum.each(&do_batch_upsert_chunk/1)

    length(rows)
  end

  @upsert_sql """
  INSERT INTO localized_texts (
    project_id, source_type, source_id, source_field, source_text,
    source_text_hash, locale_code, word_count, speaker_sheet_id,
    content_role, vo_eligible, status, vo_status, machine_translated, inserted_at, updated_at
  )
  SELECT * FROM unnest(
    $1::bigint[], $2::text[], $3::bigint[], $4::text[], $5::text[],
    $6::text[], $7::text[], $8::int[], $9::bigint[], $10::text[],
    $11::boolean[], $12::text[], $13::text[], $14::boolean[], $15::timestamp[], $16::timestamp[]
  )
  ON CONFLICT (source_type, source_id, source_field, locale_code)
  DO UPDATE SET
    source_text = EXCLUDED.source_text,
    source_text_hash = EXCLUDED.source_text_hash,
    word_count = EXCLUDED.word_count,
    speaker_sheet_id = EXCLUDED.speaker_sheet_id,
    content_role = EXCLUDED.content_role,
    vo_eligible = EXCLUDED.vo_eligible,
    vo_status = CASE
      WHEN localized_texts.source_text_hash IS DISTINCT FROM EXCLUDED.source_text_hash
        AND EXCLUDED.vo_eligible = true
        AND (localized_texts.vo_status IN ('recorded', 'approved') OR localized_texts.vo_asset_id IS NOT NULL)
      THEN 'needed'
      ELSE localized_texts.vo_status
    END,
    archived_at = NULL,
    archive_reason = NULL,
    status = CASE
      WHEN localized_texts.source_text_hash IS DISTINCT FROM EXCLUDED.source_text_hash
        AND NULLIF(BTRIM(localized_texts.translated_text), '') IS NULL
      THEN 'pending'
      WHEN localized_texts.source_text_hash IS DISTINCT FROM EXCLUDED.source_text_hash
      THEN 'review'
      ELSE localized_texts.status
    END,
    lock_version = localized_texts.lock_version + 1,
    updated_at = EXCLUDED.updated_at
  WHERE localized_texts.source_text_hash IS DISTINCT FROM EXCLUDED.source_text_hash
    OR localized_texts.speaker_sheet_id IS DISTINCT FROM EXCLUDED.speaker_sheet_id
    OR localized_texts.content_role IS DISTINCT FROM EXCLUDED.content_role
    OR localized_texts.vo_eligible IS DISTINCT FROM EXCLUDED.vo_eligible
    OR localized_texts.archived_at IS NOT NULL
  """

  defp do_batch_upsert_chunk(chunk) do
    {project_ids, source_types, source_ids, source_fields, source_texts, source_text_hashes, locale_codes, word_counts,
     speaker_sheet_ids, content_roles, vo_eligibles, statuses, vo_statuses, machine_translateds, inserted_ats,
     updated_ats} =
      Enum.reduce(chunk, {[], [], [], [], [], [], [], [], [], [], [], [], [], [], [], []}, fn row, acc ->
        {p, st, si, sf, stxt, sth, lc, wc, ssi, cr, ve, s, vs, mt, ia, ua} = acc

        {
          [row.project_id | p],
          [row.source_type | st],
          [row.source_id | si],
          [row.source_field | sf],
          [row.source_text | stxt],
          [row.source_text_hash | sth],
          [row.locale_code | lc],
          [row.word_count | wc],
          [row.speaker_sheet_id | ssi],
          [row.content_role | cr],
          [row.vo_eligible | ve],
          [row.status | s],
          [row.vo_status | vs],
          [row.machine_translated | mt],
          [row.inserted_at | ia],
          [row.updated_at | ua]
        }
      end)

    Repo.query!(@upsert_sql, [
      Enum.reverse(project_ids),
      Enum.reverse(source_types),
      Enum.reverse(source_ids),
      Enum.reverse(source_fields),
      Enum.reverse(source_texts),
      Enum.reverse(source_text_hashes),
      Enum.reverse(locale_codes),
      Enum.reverse(word_counts),
      Enum.reverse(speaker_sheet_ids),
      Enum.reverse(content_roles),
      Enum.reverse(vo_eligibles),
      Enum.reverse(statuses),
      Enum.reverse(vo_statuses),
      Enum.reverse(machine_translateds),
      Enum.reverse(inserted_ats),
      Enum.reverse(updated_ats)
    ])
  end

  @doc """
  Upserts the current runtime strings and removes rows whose source no longer
  belongs to the project localization contract.

  Locale rows for still-live sources are retained when a language is archived,
  so re-enabling a locale does not destroy previous translation work.
  """
  @spec reconcile_project_texts(integer(), [map()], MapSet.t()) :: {:ok, non_neg_integer()} | {:error, term()}
  def reconcile_project_texts(project_id, entries, source_keys) do
    Repo.transaction(fn ->
      batch_upsert_texts(project_id, entries)
      archive_obsolete_project_texts(project_id, source_keys)
      MapSet.size(source_keys)
    end)
  end

  defp archive_obsolete_project_texts(project_id, source_keys) do
    allowed_source_types = SourceContract.source_types()

    obsolete_ids =
      from(t in LocalizedText,
        where: t.project_id == ^project_id and is_nil(t.archived_at),
        select: {t.id, t.source_type, t.source_id, t.source_field}
      )
      |> Repo.all()
      |> Enum.reject(fn {_id, source_type, source_id, source_field} ->
        source_type in allowed_source_types and
          MapSet.member?(source_keys, {source_type, source_id, source_field})
      end)
      |> Enum.map(&elem(&1, 0))

    now = TimeHelpers.now()

    obsolete_ids
    |> Enum.chunk_every(500)
    |> Enum.each(fn ids ->
      Repo.update_all(
        from(t in LocalizedText, where: t.id in ^ids),
        set: [archived_at: now, archive_reason: "source_not_runtime", updated_at: now],
        inc: [lock_version: 1]
      )
    end)

    :ok
  end

  @doc """
  Bulk-inserts localized texts from a list of attr maps.
  Uses on_conflict: :nothing for deduplication.
  """
  def bulk_import_texts(attrs_list) do
    attrs_list
    |> Enum.flat_map(fn attrs ->
      case SourceContract.field_metadata(attrs[:source_type], attrs[:source_field]) do
        nil ->
          []

        metadata ->
          [
            attrs
            |> Map.put(:content_role, metadata.content_role)
            |> Map.put(:vo_eligible, metadata.vo_eligible)
            |> maybe_clear_ineligible_voice(metadata)
          ]
      end
    end)
    |> Enum.chunk_every(500)
    |> Enum.each(fn chunk ->
      Repo.insert_all(LocalizedText, chunk, on_conflict: :nothing)
    end)
  end

  defp maybe_clear_ineligible_voice(attrs, %{vo_eligible: true}), do: attrs

  defp maybe_clear_ineligible_voice(attrs, %{vo_eligible: false}) do
    attrs
    |> Map.put(:vo_status, "none")
    |> Map.put(:vo_asset_id, nil)
  end

  defp apply_source_metadata(attrs) do
    case SourceContract.field_metadata(attrs["source_type"], attrs["source_field"]) do
      nil ->
        attrs

      metadata ->
        attrs
        |> Map.put("content_role", metadata.content_role)
        |> Map.put("vo_eligible", metadata.vo_eligible)
    end
  end

  defp prepare_translation_attrs(attrs, text) do
    attrs = Map.delete(attrs, "translated_source_hash")

    attrs =
      case Map.fetch(attrs, "translated_text") do
        :error ->
          maybe_mark_reviewed(attrs)

        {:ok, translated_text} when is_binary(translated_text) ->
          if present?(translated_text) do
            attrs
            |> Map.put("translated_source_hash", text.source_text_hash)
            |> promote_pending_to_draft()
            |> Map.put_new("machine_translated", false)
            |> Map.put("last_translated_at", TimeHelpers.now())
            |> maybe_mark_reviewed()
          else
            attrs
            |> Map.put("translated_text", nil)
            |> Map.put("translated_source_hash", nil)
            |> Map.put("status", "pending")
            |> Map.put("machine_translated", false)
          end

        {:ok, _translated_text} ->
          attrs
          |> Map.put("translated_text", nil)
          |> Map.put("translated_source_hash", nil)
          |> Map.put("status", "pending")
          |> Map.put("machine_translated", false)
      end

    maybe_invalidate_voiceover(attrs, text)
  end

  defp prepare_create_translation_attrs(attrs) do
    attrs = Map.delete(attrs, "translated_source_hash")

    case Map.get(attrs, "translated_text") do
      translated_text when is_binary(translated_text) ->
        if present?(translated_text) do
          attrs
          |> Map.put("translated_source_hash", attrs["source_text_hash"])
          |> promote_pending_to_draft()
          |> Map.put_new("last_translated_at", TimeHelpers.now())
        else
          Map.put(attrs, "translated_text", nil)
        end

      _translated_text ->
        attrs
    end
  end

  defp maybe_mark_reviewed(%{"status" => "final"} = attrs) do
    Map.put_new(attrs, "last_reviewed_at", TimeHelpers.now())
  end

  defp maybe_mark_reviewed(attrs), do: attrs

  defp promote_pending_to_draft(%{"status" => "pending"} = attrs), do: Map.put(attrs, "status", "draft")
  defp promote_pending_to_draft(attrs), do: Map.put_new(attrs, "status", "draft")

  defp maybe_invalidate_voiceover(attrs, text) do
    translation_changed? =
      Map.has_key?(attrs, "translated_text") and attrs["translated_text"] != text.translated_text

    replacement_recording? =
      Map.has_key?(attrs, "vo_asset_id") and attrs["vo_asset_id"] != text.vo_asset_id and
        attrs["vo_status"] in ["recorded", "approved"]

    if translation_changed? and existing_voiceover?(text) and not replacement_recording? do
      Map.put(attrs, "vo_status", invalidated_vo_status(text))
    else
      attrs
    end
  end

  defp existing_voiceover?(%{vo_eligible: true, vo_status: status}) when status in ["recorded", "approved"], do: true
  defp existing_voiceover?(%{vo_eligible: true, vo_asset_id: asset_id}), do: not is_nil(asset_id)
  defp existing_voiceover?(_text), do: false

  defp invalidated_vo_status(%{vo_eligible: true, vo_status: status}) when status in ["recorded", "approved"],
    do: "needed"

  defp invalidated_vo_status(%{vo_eligible: true, vo_asset_id: asset_id}) when not is_nil(asset_id), do: "needed"
  defp invalidated_vo_status(text), do: text.vo_status

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_value), do: false
end

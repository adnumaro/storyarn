defmodule Storyarn.Projects.LocalizationProjection do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Platform.Shared.HtmlUtils
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Projects.LocalizationSourceContract
  alias Storyarn.Projects.Persistence.BlockRecord, as: Block
  alias Storyarn.Projects.Persistence.FlowNodeRecord, as: FlowNode
  alias Storyarn.Projects.Persistence.FlowRecord, as: Flow
  alias Storyarn.Projects.Persistence.LocalizedTextRecord, as: LocalizedText
  alias Storyarn.Projects.Persistence.ProjectLanguageRecord, as: ProjectLanguage
  alias Storyarn.Projects.Persistence.SheetRecord, as: Sheet
  alias Storyarn.Projects.Project
  alias Storyarn.Repo

  @inventory_lock_namespace "storyarn:localization:inventory"
  @block_lock_namespace "storyarn:localization:block"

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

  @doc false
  def lock_inventory!(project_id) when is_integer(project_id) do
    if Repo.in_transaction?() do
      lock_active_project!(project_id)
      lock_exclusive!(@inventory_lock_namespace, project_id)
      :ok
    else
      raise ArgumentError, "localization inventory locks require an explicit database transaction"
    end
  end

  def extract_all(project_id) do
    Repo.transaction(fn ->
      lock_inventory!(project_id)
      sources = runtime_sources(project_id)
      locales = target_locales(project_id)
      entries = for source <- sources, locale <- locales, do: source_to_entry(project_id, source, locale)

      batch_upsert(entries)
      archive_obsolete_project_texts(project_id, MapSet.new(sources, &source_key/1))
      MapSet.size(MapSet.new(sources, &source_key/1))
    end)
  end

  def extract_sheet_blocks(sheet_id), do: extract_sheet_blocks_for_sheets([sheet_id])
  def extract_sheet_blocks_for_sheets([]), do: :ok

  def extract_sheet_blocks_for_sheets(sheet_ids) do
    case sheet_project_id(List.first(sheet_ids)) do
      nil ->
        :ok

      project_id ->
        project_id
        |> with_inventory_lock(fn ->
          Block
          |> where([block], block.sheet_id in ^sheet_ids)
          |> Repo.all()
          |> Enum.each(&reconcile_block(project_id, &1.id))

          :ok
        end)
        |> normalize_lock_result()
    end
  end

  def extract_block(nil), do: :ok

  def extract_block(%{id: block_id, sheet_id: sheet_id}) do
    case sheet_project_id(sheet_id) do
      nil ->
        :ok

      project_id ->
        project_id
        |> with_source_lock(block_id, fn -> reconcile_block(project_id, block_id) end)
        |> normalize_lock_result()
    end
  end

  def sync_sheet_names(project_id) do
    project_id
    |> with_inventory_lock(fn ->
      sources =
        project_id
        |> runtime_sheets()
        |> build_sources("sheet", &sheet_source_fields/1)

      entries =
        for source <- sources, locale <- target_locales(project_id), do: source_to_entry(project_id, source, locale)

      batch_upsert(entries)

      active_ids = MapSet.new(sources, & &1.source_id)

      from(text in LocalizedText,
        where:
          text.project_id == ^project_id and text.source_type == "sheet" and
            is_nil(text.archived_at),
        distinct: true,
        select: text.source_id
      )
      |> Repo.all()
      |> Enum.reject(&MapSet.member?(active_ids, &1))
      |> then(&archive_texts_for_sources("sheet", &1, "source_not_runtime"))

      :ok
    end)
    |> normalize_lock_result()
  end

  @doc "Hard-deletes every localization row for the given sources."
  @spec purge_texts_for_source(String.t(), integer()) :: {non_neg_integer(), nil}
  def purge_texts_for_source(source_type, source_id) do
    purge_texts_for_sources(source_type, [source_id])
  end

  @spec purge_texts_for_sources(String.t(), [integer()]) :: {non_neg_integer(), nil}
  def purge_texts_for_sources(_source_type, []), do: {0, nil}

  def purge_texts_for_sources(source_type, source_ids) do
    Repo.delete_all(
      from(text in LocalizedText,
        where: text.source_type == ^source_type and text.source_id in ^source_ids
      )
    )
  end

  def archive_texts_for_sources(_source_type, [], _reason), do: {0, nil}

  def archive_texts_for_sources(source_type, source_ids, reason) do
    now = TimeHelpers.now()

    Repo.update_all(
      from(text in LocalizedText,
        where:
          text.source_type == ^source_type and text.source_id in ^source_ids and
            is_nil(text.archived_at)
      ),
      set: [archived_at: now, archive_reason: reason, updated_at: now],
      inc: [lock_version: 1]
    )
  end

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

  defp reconcile_block(project_id, block_id) do
    current =
      Repo.one(
        from(block in Block,
          join: sheet in Sheet,
          on: sheet.id == block.sheet_id,
          where:
            block.id == ^block_id and sheet.project_id == ^project_id and
              is_nil(block.deleted_at) and is_nil(sheet.deleted_at),
          select: block
        )
      )

    case current do
      %Block{} = block -> reconcile_current_block(project_id, block)
      nil -> archive_texts_for_sources("block", [block_id], "source_deleted")
    end

    :ok
  end

  defp reconcile_current_block(project_id, block) do
    fields = block_source_fields(block)

    if LocalizationSourceContract.localizable_block?(block) do
      upsert_source_fields(project_id, "block", block.id, fields)
    else
      archive_texts_for_sources("block", [block.id], "source_not_runtime")
    end
  end

  defp upsert_source_fields(project_id, source_type, source_id, fields) do
    entries =
      for field <- fields, locale <- target_locales(project_id) do
        source = Map.merge(field, %{source_type: source_type, source_id: source_id})
        source_to_entry(project_id, source, locale)
      end

    batch_upsert(entries)
    archive_removed_fields(source_type, source_id, MapSet.new(fields, & &1.field))
    :ok
  end

  defp archive_removed_fields(source_type, source_id, current_fields) do
    from(text in LocalizedText,
      where:
        text.source_type == ^source_type and text.source_id == ^source_id and
          is_nil(text.archived_at),
      distinct: true,
      select: text.source_field
    )
    |> Repo.all()
    |> Enum.reject(&MapSet.member?(current_fields, &1))
    |> Enum.each(fn field ->
      now = TimeHelpers.now()

      Repo.update_all(
        from(text in LocalizedText,
          where:
            text.source_type == ^source_type and text.source_id == ^source_id and
              text.source_field == ^field and is_nil(text.archived_at)
        ),
        set: [archived_at: now, archive_reason: "source_field_removed", updated_at: now],
        inc: [lock_version: 1]
      )
    end)
  end

  defp batch_upsert([]), do: :ok

  defp batch_upsert(entries) do
    now = TimeHelpers.now()

    entries
    |> Enum.chunk_every(500)
    |> Enum.each(fn chunk ->
      values =
        chunk
        |> Enum.reduce(
          {[], [], [], [], [], [], [], [], [], [], [], [], [], [], [], []},
          fn entry, acc -> append_upsert_entry(entry, now, acc) end
        )
        |> Tuple.to_list()
        |> Enum.map(&Enum.reverse/1)

      Repo.query!(@upsert_sql, values)
    end)

    :ok
  end

  defp append_upsert_entry(entry, now, acc) do
    {project_ids, source_types, source_ids, source_fields, source_texts, source_hashes, locales, word_counts, speakers,
     roles, vo_eligibles, statuses, vo_statuses, machine_translated, inserted_ats, updated_ats} = acc

    {
      [entry.project_id | project_ids],
      [entry.source_type | source_types],
      [entry.source_id | source_ids],
      [entry.source_field | source_fields],
      [entry.source_text | source_texts],
      [entry.source_text_hash | source_hashes],
      [entry.locale_code | locales],
      [entry.word_count | word_counts],
      [entry.speaker_sheet_id | speakers],
      [entry.content_role | roles],
      [entry.vo_eligible | vo_eligibles],
      ["pending" | statuses],
      ["none" | vo_statuses],
      [false | machine_translated],
      [now | inserted_ats],
      [now | updated_ats]
    }
  end

  defp runtime_sources(project_id) do
    build_sources(project_flow_nodes(project_id), "flow_node", &flow_node_source_fields/1) ++
      build_sources(project_blocks(project_id), "block", &block_source_fields/1) ++
      build_sources(runtime_sheets(project_id), "sheet", &sheet_source_fields/1)
  end

  defp project_flow_nodes(project_id) do
    Repo.all(
      from(node in FlowNode,
        join: flow in Flow,
        on: flow.id == node.flow_id,
        where:
          flow.project_id == ^project_id and is_nil(flow.deleted_at) and
            is_nil(node.deleted_at),
        order_by: [asc: node.id]
      )
    )
  end

  defp project_blocks(project_id) do
    Repo.all(
      from(block in Block,
        join: sheet in Sheet,
        on: sheet.id == block.sheet_id,
        where:
          sheet.project_id == ^project_id and is_nil(sheet.deleted_at) and
            is_nil(block.deleted_at),
        order_by: [asc: block.id]
      )
    )
  end

  defp runtime_sheets(project_id) do
    Repo.all(
      from(sheet in Sheet,
        where: sheet.project_id == ^project_id and is_nil(sheet.deleted_at),
        order_by: [asc: sheet.id]
      )
    )
  end

  defp build_sources(records, source_type, fields_fun) do
    for record <- records, field <- fields_fun.(record) do
      Map.merge(field, %{source_type: source_type, source_id: record.id})
    end
  end

  defp flow_node_source_fields(%{type: "dialogue", data: data}) when is_map(data) do
    speaker_sheet_id = data["speaker_sheet_id"]

    optional_field("text", data["text"], "dialogue",
      vo_eligible: true,
      speaker_sheet_id: speaker_sheet_id
    ) ++
      optional_field("stage_directions", data["stage_directions"], "stage_direction") ++
      optional_field("menu_text", data["menu_text"], "menu") ++
      response_fields(data["responses"], speaker_sheet_id)
  end

  defp flow_node_source_fields(%{type: "exit", data: data}) when is_map(data) do
    optional_field("label", data["label"], "exit")
  end

  defp flow_node_source_fields(_node), do: []

  defp response_fields(responses, speaker_sheet_id) when is_list(responses) do
    Enum.flat_map(responses, fn
      %{"id" => response_id} = response when is_binary(response_id) ->
        optional_field("response.#{response_id}.text", response["text"], "response",
          vo_eligible: true,
          speaker_sheet_id: speaker_sheet_id
        )

      _invalid ->
        []
    end)
  end

  defp response_fields(_responses, _speaker_sheet_id), do: []

  defp block_source_fields(%{value: value} = block) when is_map(value) do
    if LocalizationSourceContract.localizable_block?(block) do
      optional_field("value.content", value["content"], "runtime_value")
    else
      []
    end
  end

  defp block_source_fields(_block), do: []
  defp sheet_source_fields(%{name: name}), do: optional_field("name", name, "speaker_name")

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

  defp source_to_entry(project_id, source, locale) do
    %{
      project_id: project_id,
      source_type: source.source_type,
      source_id: source.source_id,
      source_field: source.field,
      source_text: source.text,
      source_text_hash: hash(source.text),
      locale_code: locale,
      word_count: HtmlUtils.word_count(source.text),
      speaker_sheet_id: source.speaker_sheet_id,
      content_role: source.content_role,
      vo_eligible: source.vo_eligible
    }
  end

  defp source_key(source), do: {source.source_type, source.source_id, source.field}

  defp archive_obsolete_project_texts(project_id, source_keys) do
    allowed_source_types = LocalizationSourceContract.source_types()

    obsolete_ids =
      from(text in LocalizedText,
        where: text.project_id == ^project_id and is_nil(text.archived_at),
        select: {text.id, text.source_type, text.source_id, text.source_field}
      )
      |> Repo.all()
      |> Enum.reject(fn {_id, source_type, source_id, source_field} ->
        source_type in allowed_source_types and
          MapSet.member?(source_keys, {source_type, source_id, source_field})
      end)
      |> Enum.map(&elem(&1, 0))

    now = TimeHelpers.now()

    Enum.each(Enum.chunk_every(obsolete_ids, 500), fn ids ->
      Repo.update_all(
        from(text in LocalizedText, where: text.id in ^ids),
        set: [archived_at: now, archive_reason: "source_not_runtime", updated_at: now],
        inc: [lock_version: 1]
      )
    end)
  end

  defp target_locales(project_id) do
    Repo.all(
      from(language in ProjectLanguage,
        where:
          language.project_id == ^project_id and language.is_source == false and
            is_nil(language.archived_at),
        order_by: [asc: language.position, asc: language.id],
        select: language.locale_code
      )
    )
  end

  defp sheet_project_id(sheet_id) do
    Repo.one(
      from(sheet in Sheet,
        where: sheet.id == ^sheet_id and is_nil(sheet.deleted_at),
        select: sheet.project_id
      )
    )
  end

  defp with_inventory_lock(project_id, callback) do
    Repo.transaction(fn ->
      lock_inventory!(project_id)
      callback.()
    end)
  end

  defp with_source_lock(project_id, block_id, callback) do
    Repo.transaction(fn ->
      lock_active_project!(project_id)
      lock_shared!(@inventory_lock_namespace, project_id)
      lock_exclusive!(@block_lock_namespace, block_id)
      callback.()
    end)
  end

  defp lock_active_project!(project_id) do
    case Repo.one(
           from(project in Project,
             where: project.id == ^project_id and is_nil(project.deleted_at),
             lock: "FOR UPDATE"
           )
         ) do
      %Project{} -> :ok
      nil -> Repo.rollback(:project_not_active)
    end
  end

  defp lock_exclusive!(namespace, id) do
    Repo.query!(
      "SELECT pg_advisory_xact_lock(hashtextextended(concat($1::text, ':', $2::text), 0))",
      [namespace, to_string(id)]
    )
  end

  defp lock_shared!(namespace, id) do
    Repo.query!(
      "SELECT pg_advisory_xact_lock_shared(hashtextextended(concat($1::text, ':', $2::text), 0))",
      [namespace, to_string(id)]
    )
  end

  defp normalize_lock_result({:ok, {:error, reason}}), do: {:error, reason}
  defp normalize_lock_result({:ok, _result}), do: :ok
  defp normalize_lock_result({:error, reason}), do: {:error, reason}
  defp normalize_lock_result(:ok), do: :ok

  defp hash(text), do: :sha256 |> :crypto.hash(text) |> Base.encode16(case: :lower)
end

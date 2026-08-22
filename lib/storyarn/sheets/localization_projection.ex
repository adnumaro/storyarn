defmodule Storyarn.Sheets.LocalizationProjection do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Repo
  alias Storyarn.Shared.HtmlUtils
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Sheets.Block
  alias Storyarn.Sheets.ContentContract
  alias Storyarn.Sheets.Persistence.LocalizedTextRecord
  alias Storyarn.Sheets.Persistence.ProjectLanguageRecord
  alias Storyarn.Sheets.Persistence.ProjectRecord
  alias Storyarn.Sheets.Sheet

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

  @spec extract_block(Block.t() | nil) :: :ok | {:error, term()}
  def extract_block(nil), do: :ok

  def extract_block(%Block{} = block) do
    case sheet_project_id(block.sheet_id) do
      nil ->
        :ok

      project_id ->
        project_id
        |> with_source_lock(block.id, fn -> reconcile_block(project_id, block.id) end)
        |> normalize_lock_result()
    end
  end

  @spec extract_sheet_blocks(integer()) :: :ok | {:error, term()}
  def extract_sheet_blocks(sheet_id), do: extract_sheet_blocks_for_sheets([sheet_id])

  @spec extract_sheet_blocks_for_sheets([integer()]) :: :ok | {:error, term()}
  def extract_sheet_blocks_for_sheets([]), do: :ok

  def extract_sheet_blocks_for_sheets(sheet_ids) when is_list(sheet_ids) do
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

  @spec extract_block_tree(integer()) :: :ok | {:error, term()}
  def extract_block_tree(block_id) do
    case block_project_id(block_id) do
      nil ->
        :ok

      project_id ->
        project_id
        |> with_inventory_lock(fn ->
          Block
          |> where(
            [block],
            block.id == ^block_id or block.inherited_from_block_id == ^block_id
          )
          |> Repo.all()
          |> Enum.each(&reconcile_block(project_id, &1.id))

          :ok
        end)
        |> normalize_lock_result()
    end
  end

  @doc "Synchronizes active Sheet names because engine serializers emit them as runtime actors."
  @spec sync_sheet_names(integer()) :: :ok | {:error, term()}
  def sync_sheet_names(project_id) do
    project_id
    |> with_inventory_lock(fn ->
      sheets = runtime_sheets(project_id)
      locales = target_locales(project_id)

      entries =
        for sheet <- sheets,
            field <- sheet_source_fields(sheet),
            locale <- locales do
          source_entry(project_id, "sheet", sheet.id, field, locale)
        end

      batch_upsert(entries)

      active_ids =
        sheets
        |> Enum.filter(&(sheet_source_fields(&1) != []))
        |> MapSet.new(& &1.id)

      LocalizedTextRecord
      |> where(
        [text],
        text.project_id == ^project_id and text.source_type == "sheet" and
          is_nil(text.archived_at)
      )
      |> distinct([text], true)
      |> select([text], text.source_id)
      |> Repo.all()
      |> Enum.reject(&MapSet.member?(active_ids, &1))
      |> archive_texts_for_sources("sheet", "source_not_runtime")

      :ok
    end)
    |> normalize_lock_result()
  end

  @spec delete_block_texts(integer()) :: :ok
  def delete_block_texts(block_id) do
    with_project_inventory_lock(block_project_id(block_id), fn ->
      archive_texts_for_sources([block_id], "block", "source_deleted")
    end)

    :ok
  end

  @spec delete_block_tree_texts(integer()) :: :ok
  def delete_block_tree_texts(block_id) do
    with_project_inventory_lock(block_project_id(block_id), fn ->
      block_ids =
        Repo.all(
          from(block in Block,
            where:
              block.id == ^block_id or
                block.inherited_from_block_id == ^block_id,
            select: block.id
          )
        )

      archive_texts_for_sources(block_ids, "block", "source_deleted")
    end)

    :ok
  end

  @spec delete_block_texts_for_sheets([integer()]) :: :ok
  def delete_block_texts_for_sheets([]), do: :ok

  def delete_block_texts_for_sheets(sheet_ids) when is_list(sheet_ids) do
    with_project_inventory_lock(sheet_project_id(List.first(sheet_ids)), fn ->
      block_ids =
        Repo.all(
          from(block in Block,
            where: block.sheet_id in ^sheet_ids,
            select: block.id
          )
        )

      archive_texts_for_sources(block_ids, "block", "source_deleted")
    end)

    :ok
  end

  @spec delete_texts_for_source(String.t(), integer()) :: {non_neg_integer(), nil}
  def delete_texts_for_source(source_type, source_id) do
    archive_texts_for_sources([source_id], source_type, "source_deleted")
  end

  @spec purge_texts_for_source(String.t(), integer()) :: {non_neg_integer(), nil}
  def purge_texts_for_source(source_type, source_id) do
    purge_texts_for_sources(source_type, [source_id])
  end

  @spec purge_texts_for_sources(String.t(), [integer()]) :: {non_neg_integer(), nil}
  def purge_texts_for_sources(_source_type, []), do: {0, nil}

  def purge_texts_for_sources(source_type, source_ids) do
    Repo.delete_all(
      from(text in LocalizedTextRecord,
        where: text.source_type == ^source_type and text.source_id in ^source_ids
      )
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
      nil -> archive_texts_for_sources([block_id], "block", "source_deleted")
    end

    :ok
  end

  defp reconcile_current_block(project_id, block) do
    if ContentContract.localizable_block?(block) do
      upsert_source_fields(project_id, "block", block.id, block_source_fields(block))
    else
      archive_texts_for_sources([block.id], "block", "source_not_runtime")
      :ok
    end
  end

  defp upsert_source_fields(project_id, source_type, source_id, fields) do
    locales = target_locales(project_id)

    entries =
      for field <- fields, locale <- locales do
        source_entry(project_id, source_type, source_id, field, locale)
      end

    batch_upsert(entries)
    archive_removed_fields(source_type, source_id, MapSet.new(fields, & &1.field))
    :ok
  end

  defp source_entry(project_id, source_type, source_id, field, locale) do
    %{
      project_id: project_id,
      source_type: source_type,
      source_id: source_id,
      source_field: field.field,
      source_text: field.text,
      source_text_hash: hash(field.text),
      locale_code: locale,
      word_count: HtmlUtils.word_count(field.text),
      speaker_sheet_id: field.speaker_sheet_id,
      content_role: field.content_role,
      vo_eligible: field.vo_eligible
    }
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

  defp archive_removed_fields(source_type, source_id, current_fields) do
    source_type
    |> active_source_fields(source_id)
    |> Enum.reject(&MapSet.member?(current_fields, &1))
    |> Enum.each(fn field ->
      now = TimeHelpers.now()

      Repo.update_all(
        from(text in LocalizedTextRecord,
          where:
            text.source_type == ^source_type and text.source_id == ^source_id and
              text.source_field == ^field and is_nil(text.archived_at)
        ),
        set: [
          archived_at: now,
          archive_reason: "source_field_removed",
          updated_at: now
        ],
        inc: [lock_version: 1]
      )
    end)
  end

  defp active_source_fields(source_type, source_id) do
    Repo.all(
      from(text in LocalizedTextRecord,
        where:
          text.source_type == ^source_type and text.source_id == ^source_id and
            is_nil(text.archived_at),
        distinct: true,
        select: text.source_field
      )
    )
  end

  defp archive_texts_for_sources([], _source_type, _reason), do: {0, nil}

  defp archive_texts_for_sources(source_ids, source_type, reason) do
    now = TimeHelpers.now()

    Repo.update_all(
      from(text in LocalizedTextRecord,
        where:
          text.source_type == ^source_type and text.source_id in ^source_ids and
            is_nil(text.archived_at)
      ),
      set: [archived_at: now, archive_reason: reason, updated_at: now],
      inc: [lock_version: 1]
    )
  end

  defp block_source_fields(%Block{value: value} = block) do
    if ContentContract.localizable_block?(block) do
      optional_field("value.content", field(value, "content", :content), "runtime_value")
    else
      []
    end
  end

  defp sheet_source_fields(%Sheet{name: name}) do
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

  defp target_locales(project_id) do
    Repo.all(
      from(language in ProjectLanguageRecord,
        where:
          language.project_id == ^project_id and language.is_source == false and
            is_nil(language.archived_at),
        order_by: [asc: language.position, asc: language.name],
        select: language.locale_code
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

  defp sheet_project_id(sheet_id) do
    Repo.one(
      from(sheet in Sheet,
        where: sheet.id == ^sheet_id and is_nil(sheet.deleted_at),
        select: sheet.project_id
      )
    )
  end

  defp block_project_id(block_id) do
    Repo.one(
      from(block in Block,
        join: sheet in Sheet,
        on: sheet.id == block.sheet_id,
        where: block.id == ^block_id,
        select: sheet.project_id
      )
    )
  end

  defp with_project_inventory_lock(nil, _callback), do: :ok

  defp with_project_inventory_lock(project_id, callback) do
    with_inventory_lock(project_id, callback)
  end

  defp with_inventory_lock(project_id, callback) do
    Repo.transaction(fn ->
      lock_active_project!(project_id)
      lock_exclusive!(@inventory_lock_namespace, project_id)
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
           from(project in ProjectRecord,
             where: project.id == ^project_id,
             lock: "FOR UPDATE"
           )
         ) do
      %ProjectRecord{deleted_at: nil} -> :ok
      %ProjectRecord{} -> Repo.rollback(:project_not_active)
      nil -> Repo.rollback(:project_not_found)
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

  defp field(map, string_key, atom_key) when is_map(map) do
    case Map.fetch(map, string_key) do
      {:ok, value} -> value
      :error -> Map.get(map, atom_key)
    end
  end

  defp field(_map, _string_key, _atom_key), do: nil

  defp hash(text), do: :sha256 |> :crypto.hash(text) |> Base.encode16(case: :lower)
end

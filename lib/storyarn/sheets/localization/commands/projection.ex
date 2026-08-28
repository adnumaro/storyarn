defmodule Storyarn.Sheets.Localization.Commands.Projection do
  @moduledoc """
  Reconciles Sheet-authored runtime text into the localization inventory.

  The command owns the transactional reconciliation workflow. PostgreSQL batch
  writes and advisory locks are isolated in the capability's adapter.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Platform.Shared.HtmlUtils
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Repo
  alias Storyarn.Sheets.Localization.Adapters.Postgres.Inventory
  alias Storyarn.Sheets.Localization.Contracts.Content
  alias Storyarn.Sheets.Localization.Projections.BlockRecord, as: Block
  alias Storyarn.Sheets.Localization.Projections.LocalizedTextRecord
  alias Storyarn.Sheets.Localization.Projections.ProjectLanguageRecord
  alias Storyarn.Sheets.Localization.Projections.ProjectRecord
  alias Storyarn.Sheets.Localization.Projections.SheetRecord, as: Sheet

  @inventory_lock_namespace "storyarn:localization:inventory"
  @block_lock_namespace "storyarn:localization:block"

  @spec extract_block(map() | nil) :: :ok | {:error, term()}
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

  @doc false
  def archive_restore_texts_for_sources(_source_type, [], _reason), do: {0, nil}

  def archive_restore_texts_for_sources(source_type, source_ids, reason) do
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

  @doc false
  def archive_texts_for_active_target_locales(_project_id, _source_type, [], _reason), do: {0, nil}

  def archive_texts_for_active_target_locales(project_id, source_type, source_ids, reason) do
    now = TimeHelpers.now()

    active_target_locales =
      from(language in ProjectLanguageRecord,
        where:
          language.project_id == ^project_id and language.is_source == false and
            is_nil(language.archived_at),
        select: language.locale_code
      )

    Repo.update_all(
      from(text in LocalizedTextRecord,
        where:
          text.project_id == ^project_id and text.source_type == ^source_type and
            text.source_id in ^source_ids and is_nil(text.archived_at) and
            text.locale_code in subquery(active_target_locales)
      ),
      set: [archived_at: now, archive_reason: reason, updated_at: now],
      inc: [lock_version: 1]
    )
  end

  @doc false
  def lock_inventory!(project_id) when is_integer(project_id) do
    if Repo.in_transaction?() do
      lock_active_project!(project_id)
      Inventory.lock_exclusive!(@inventory_lock_namespace, project_id)
      :ok
    else
      raise ArgumentError, "localization inventory locks require an explicit database transaction"
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
    if Content.localizable_block?(block) do
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
    |> Enum.each(&Inventory.upsert_localized_texts!(&1, now))

    :ok
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
    if Content.localizable_block?(block) do
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
      Inventory.lock_exclusive!(@inventory_lock_namespace, project_id)
      callback.()
    end)
  end

  defp with_source_lock(project_id, block_id, callback) do
    Repo.transaction(fn ->
      lock_active_project!(project_id)
      Inventory.lock_shared!(@inventory_lock_namespace, project_id)
      Inventory.lock_exclusive!(@block_lock_namespace, block_id)
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

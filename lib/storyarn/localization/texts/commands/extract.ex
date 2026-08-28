defmodule Storyarn.Localization.Texts.Commands.Extract do
  @moduledoc "Extracts and reconciles the runtime localization inventory under deterministic locks."

  import Ecto.Query, warn: false

  alias Storyarn.Localization.LocaleCode
  alias Storyarn.Localization.LocalizedText
  alias Storyarn.Localization.ProjectAccess
  alias Storyarn.Localization.SourceContract
  alias Storyarn.Localization.Texts.Adapters.Locks.Postgres
  alias Storyarn.Localization.Texts.Commands.Lifecycle
  alias Storyarn.Localization.Texts.Commands.Reconcile
  alias Storyarn.Localization.Texts.Projections.BlockRecord
  alias Storyarn.Localization.Texts.Projections.FlowNodeRecord
  alias Storyarn.Localization.Texts.Projections.FlowRecord
  alias Storyarn.Localization.Texts.Projections.LanguageRecord
  alias Storyarn.Localization.Texts.Projections.SheetRecord
  alias Storyarn.Localization.Texts.Queries.Texts, as: TextsQuery
  alias Storyarn.Platform.Shared.HtmlUtils
  alias Storyarn.Repo

  @inventory_lock_namespace "storyarn:localization:inventory"
  @flow_node_lock_namespace "storyarn:localization:flow_node"
  @block_lock_namespace "storyarn:localization:block"

  @doc """
  Reconciles the project's localization inventory with its current runtime
  export contract.

  Existing translations for live fields and archived locales are preserved.
  Rows for deleted fields, deleted entities, editor-only metadata and scenes
  are archived outside the active inventory.
  """
  @spec extract_all(integer()) :: {:ok, non_neg_integer()}
  def extract_all(project_id) do
    with_inventory_lock(project_id, fn -> reconcile_current_inventory(project_id) end)
  end

  @doc "Adds or reactivates the current runtime inventory for one target locale."
  @spec extract_locale(integer(), String.t()) :: {:ok, non_neg_integer()} | {:error, term()}
  def extract_locale(project_id, locale_code) do
    locale_code = LocaleCode.ensure_safe!(locale_code)

    with_inventory_lock(project_id, fn ->
      entries =
        for source <- runtime_sources(project_id) do
          source_to_entry(source, locale_code)
        end

      Reconcile.batch_upsert_texts(project_id, entries)
    end)
  end

  @doc false
  @spec lock_inventory!(integer()) :: :ok
  def lock_inventory!(project_id) do
    if Repo.in_transaction?() do
      lock_active_project!(project_id)
      Postgres.lock_exclusive!(@inventory_lock_namespace, project_id)
      :ok
    else
      raise ArgumentError,
            "localization inventory locks require an explicit database transaction"
    end
  end

  defp reconcile_current_inventory(project_id) do
    target_locales = get_target_locales(project_id)
    sources = runtime_sources(project_id)

    entries =
      for source <- sources, locale <- target_locales do
        source_to_entry(source, locale)
      end

    source_keys = MapSet.new(sources, &source_key/1)

    case Reconcile.reconcile_project_texts(project_id, entries, source_keys) do
      {:ok, count} -> count
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  @spec extract_flow_node(map() | struct()) :: :ok | {:error, term()}
  def extract_flow_node(%{id: node_id, flow_id: flow_id}) do
    case_result =
      case flow_project_id(flow_id) do
        nil ->
          :ok

        project_id ->
          with_source_lock(project_id, @flow_node_lock_namespace, node_id, fn ->
            reconcile_flow_node(project_id, node_id)
          end)
      end

    normalize_lock_result(case_result)
  end

  @doc false
  @spec flow_node_texts_current?(map() | struct(), integer()) :: boolean()
  def flow_node_texts_current?(%{id: _id} = node, project_id) when is_integer(project_id) do
    node.id in flow_node_texts_current_ids([node], project_id)
  end

  @doc false
  @spec flow_node_texts_current_ids([map() | struct()], integer()) :: MapSet.t(integer())
  def flow_node_texts_current_ids([], project_id) when is_integer(project_id), do: MapSet.new()

  def flow_node_texts_current_ids(nodes, project_id) when is_list(nodes) and is_integer(project_id) do
    target_locales = get_target_locales(project_id)
    node_ids = Enum.map(nodes, & &1.id)
    actual_by_node = flow_node_text_signatures(node_ids)

    Enum.reduce(nodes, MapSet.new(), fn node, current_ids ->
      expected = expected_flow_node_text_signatures(node, project_id, target_locales)
      actual = Map.get(actual_by_node, node.id, [])

      if Enum.sort(expected) == Enum.sort(actual),
        do: MapSet.put(current_ids, node.id),
        else: current_ids
    end)
  end

  defp expected_flow_node_text_signatures(node, project_id, target_locales) do
    for field <- flow_node_source_fields(node),
        locale_code <- target_locales do
      {
        project_id,
        field.field,
        locale_code,
        field.text,
        hash(field.text),
        word_count(field.text),
        field.speaker_sheet_id,
        field.content_role,
        field.vo_eligible
      }
    end
  end

  defp flow_node_text_signatures([]), do: %{}

  defp flow_node_text_signatures(node_ids) do
    from(text in LocalizedText,
      where:
        text.source_type == "flow_node" and
          text.source_id in ^node_ids and
          is_nil(text.archived_at),
      select: {
        text.source_id,
        text.project_id,
        text.source_field,
        text.locale_code,
        text.source_text,
        text.source_text_hash,
        text.word_count,
        text.speaker_sheet_id,
        text.content_role,
        text.vo_eligible
      }
    )
    |> Repo.all()
    |> Enum.group_by(
      fn {source_id, _project_id, _field, _locale, _text, _hash, _words, _speaker, _role, _vo} ->
        source_id
      end,
      fn {_source_id, project_id, field, locale, text, hash, words, speaker, role, vo} ->
        {project_id, field, locale, text, hash, words, speaker, role, vo}
      end
    )
  end

  @spec extract_block(%{required(:id) => integer(), required(:sheet_id) => integer()}) ::
          :ok | {:error, term()}
  def extract_block(%{id: block_id, sheet_id: sheet_id}) do
    case_result =
      case sheet_project_id(sheet_id) do
        nil ->
          :ok

        project_id ->
          with_source_lock(project_id, @block_lock_namespace, block_id, fn ->
            reconcile_block(project_id, block_id)
          end)
      end

    normalize_lock_result(case_result)
  end

  defp reconcile_flow_node(project_id, node_id) do
    case Repo.get(FlowNodeRecord, node_id) do
      %FlowNodeRecord{deleted_at: nil} = current ->
        upsert_source_fields(project_id, "flow_node", current.id, flow_node_source_fields(current))

      _missing_or_deleted ->
        Lifecycle.archive_texts_for_source("flow_node", node_id, "source_deleted")
        :ok
    end
  end

  defp reconcile_block(project_id, block_id) do
    current =
      Repo.one(
        from(block in BlockRecord,
          join: sheet in SheetRecord,
          on: sheet.id == block.sheet_id,
          where:
            block.id == ^block_id and sheet.project_id == ^project_id and
              is_nil(block.deleted_at) and is_nil(sheet.deleted_at),
          select: block
        )
      )

    case current do
      %BlockRecord{} = block -> reconcile_current_block(project_id, block)
      nil -> Lifecycle.archive_texts_for_source("block", block_id, "source_deleted")
    end

    :ok
  end

  defp reconcile_current_block(project_id, block) do
    if SourceContract.localizable_block?(block) do
      upsert_source_fields(project_id, "block", block.id, block_source_fields(block))
    else
      Lifecycle.archive_texts_for_source("block", block.id, "source_not_runtime")
    end
  end

  @doc "Synchronizes active sheet names because engine serializers emit sheets as runtime actors."
  @spec sync_sheet_names(integer()) :: :ok | {:error, term()}
  def sync_sheet_names(project_id) do
    project_id
    |> with_inventory_lock(fn ->
      sources = build_sources(runtime_sheets(project_id), "sheet", &speaker_source_fields/1)
      locales = get_target_locales(project_id)

      entries = for source <- sources, locale <- locales, do: source_to_entry(source, locale)
      Reconcile.batch_upsert_texts(project_id, entries)

      active_ids = MapSet.new(sources, & &1.source_id)

      project_id
      |> TextsQuery.list_texts(source_type: "sheet")
      |> Enum.map(& &1.source_id)
      |> Enum.uniq()
      |> Enum.reject(&MapSet.member?(active_ids, &1))
      |> Enum.each(&Lifecycle.archive_texts_for_source("sheet", &1, "source_not_runtime"))

      :ok
    end)
    |> normalize_lock_result()
  end

  @spec extract_flow_nodes(integer()) :: :ok | {:error, term()}
  def extract_flow_nodes(flow_id) do
    case flow_project_id(flow_id) do
      nil ->
        :ok

      project_id ->
        project_id
        |> with_inventory_lock(fn ->
          from(n in FlowNodeRecord, where: n.flow_id == ^flow_id)
          |> Repo.all()
          |> Enum.each(&reconcile_flow_node(project_id, &1.id))

          :ok
        end)
        |> normalize_lock_result()
    end
  end

  @spec extract_sheet_blocks(integer()) :: :ok | {:error, term()}
  def extract_sheet_blocks(sheet_id), do: extract_sheet_blocks_for_sheets([sheet_id])

  @spec extract_sheet_blocks_for_sheets([integer()]) :: :ok | {:error, term()}
  def extract_sheet_blocks_for_sheets([]), do: :ok

  def extract_sheet_blocks_for_sheets(sheet_ids) do
    case sheet_project_ids(sheet_ids) do
      [] ->
        :ok

      [project_id] ->
        project_id
        |> with_inventory_lock(fn ->
          from(block in BlockRecord, where: block.sheet_id in ^sheet_ids)
          |> Repo.all()
          |> Enum.each(&reconcile_block(project_id, &1.id))

          :ok
        end)
        |> normalize_lock_result()

      _mixed_project_ids ->
        {:error, :mixed_project_sheet_ids}
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
          from(b in BlockRecord, where: b.id == ^block_id or b.inherited_from_block_id == ^block_id)
          |> Repo.all()
          |> Enum.each(&reconcile_block(project_id, &1.id))

          :ok
        end)
        |> normalize_lock_result()
    end
  end

  @spec delete_flow_node_texts(integer()) :: :ok
  def delete_flow_node_texts(node_id) do
    with_source_project_lock(flow_node_project_id(node_id), fn ->
      Lifecycle.delete_texts_for_source("flow_node", node_id)
    end)

    :ok
  end

  @spec delete_flow_node_texts_for_flows([integer()]) :: :ok
  def delete_flow_node_texts_for_flows([]), do: :ok

  def delete_flow_node_texts_for_flows(flow_ids) do
    with_source_project_lock(flow_project_id(List.first(flow_ids)), fn ->
      node_ids = Repo.all(from(n in FlowNodeRecord, where: n.flow_id in ^flow_ids, select: n.id))
      Lifecycle.delete_texts_for_sources("flow_node", node_ids)
    end)

    :ok
  end

  @spec delete_block_texts(integer()) :: :ok
  def delete_block_texts(block_id) do
    with_source_project_lock(block_project_id(block_id), fn -> Lifecycle.delete_texts_for_source("block", block_id) end)
    :ok
  end

  @spec delete_block_tree_texts(integer()) :: :ok
  def delete_block_tree_texts(block_id) do
    with_source_project_lock(block_project_id(block_id), fn ->
      block_ids =
        Repo.all(
          from(b in BlockRecord,
            where: b.id == ^block_id or b.inherited_from_block_id == ^block_id,
            select: b.id
          )
        )

      Lifecycle.delete_texts_for_sources("block", block_ids)
    end)

    :ok
  end

  @spec delete_block_texts_for_sheets([integer()]) :: :ok
  def delete_block_texts_for_sheets([]), do: :ok

  def delete_block_texts_for_sheets(sheet_ids) do
    with_source_project_lock(sheet_project_id(List.first(sheet_ids)), fn ->
      block_ids = Repo.all(from(b in BlockRecord, where: b.sheet_id in ^sheet_ids, select: b.id))
      Lifecycle.delete_texts_for_sources("block", block_ids)
    end)

    :ok
  end

  # =============================================================================
  # Private — Runtime Source Contract
  # =============================================================================

  defp flow_node_source_fields(%{type: "dialogue", data: data}) do
    speaker_sheet_id = data["speaker_sheet_id"]

    optional_field("text", data["text"], "dialogue",
      vo_eligible: true,
      speaker_sheet_id: speaker_sheet_id
    ) ++
      optional_field("stage_directions", data["stage_directions"], "stage_direction") ++
      optional_field("menu_text", data["menu_text"], "menu") ++
      indexed_response_fields(list_value(data["responses"]), speaker_sheet_id)
  end

  defp flow_node_source_fields(%{type: "exit", data: data}) do
    optional_field("label", data["label"], "exit")
  end

  defp flow_node_source_fields(_node), do: []

  defp indexed_response_fields(responses, speaker_sheet_id) do
    Enum.flat_map(responses, fn
      %{"id" => response_id} = response when is_binary(response_id) ->
        optional_field("response.#{response_id}.text", response["text"], "response",
          vo_eligible: true,
          speaker_sheet_id: speaker_sheet_id
        )

      _response ->
        []
    end)
  end

  defp block_source_fields(%BlockRecord{value: value} = block) do
    if SourceContract.localizable_block?(block) do
      optional_field("value.content", value["content"], "runtime_value")
    else
      []
    end
  end

  defp speaker_source_fields(%SheetRecord{name: name}) do
    optional_field("name", name, "speaker_name")
  end

  defp runtime_sheets(project_id) do
    Repo.all(
      from(s in SheetRecord,
        where: s.project_id == ^project_id and is_nil(s.deleted_at),
        order_by: [asc: s.id]
      )
    )
  end

  # =============================================================================
  # Private — Extraction Helpers
  # =============================================================================

  defp upsert_source_fields(project_id, source_type, source_id, fields) do
    target_locales = get_target_locales(project_id)

    entries =
      for field <- fields, locale <- target_locales do
        field
        |> Map.merge(%{source_type: source_type, source_id: source_id})
        |> source_to_entry(locale)
      end

    Reconcile.batch_upsert_texts(project_id, entries)

    cleanup_removed_fields(source_type, source_id, fields)
  end

  defp build_sources(records, source_type, fields_fun) do
    for record <- records, field <- fields_fun.(record) do
      Map.merge(field, %{source_type: source_type, source_id: record.id})
    end
  end

  defp source_to_entry(source, locale) do
    %{
      "source_type" => source.source_type,
      "source_id" => source.source_id,
      "source_field" => source.field,
      "source_text" => source.text,
      "source_text_hash" => hash(source.text),
      "locale_code" => locale,
      "word_count" => word_count(source.text),
      "speaker_sheet_id" => source.speaker_sheet_id,
      "content_role" => source.content_role,
      "vo_eligible" => source.vo_eligible
    }
  end

  defp source_key(source), do: {source.source_type, source.source_id, source.field}

  defp with_inventory_lock(project_id, fun) when is_function(fun, 0) do
    Repo.transaction(fn ->
      lock_inventory!(project_id)
      fun.()
    end)
  end

  defp with_source_lock(project_id, source_namespace, source_id, fun) when is_function(fun, 0) do
    Repo.transaction(fn ->
      lock_active_project!(project_id)
      Postgres.lock_shared!(@inventory_lock_namespace, project_id)
      Postgres.lock_exclusive!(source_namespace, source_id)
      fun.()
    end)
  end

  defp lock_active_project!(project_id) do
    case ProjectAccess.lock_active_project(project_id, :update) do
      {:ok, _project} -> :ok
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp normalize_lock_result({:ok, {:error, reason}}), do: {:error, reason}
  defp normalize_lock_result({:ok, _result}), do: :ok
  defp normalize_lock_result({:error, reason}), do: {:error, reason}
  defp normalize_lock_result(:ok), do: :ok

  defp with_source_project_lock(nil, _fun), do: :ok
  defp with_source_project_lock(project_id, fun), do: with_inventory_lock(project_id, fun)

  defp cleanup_removed_fields(source_type, source_id, current_fields) do
    current_field_names = MapSet.new(current_fields, & &1.field)

    source_type
    |> TextsQuery.get_texts_for_source(source_id)
    |> Enum.map(& &1.source_field)
    |> Enum.uniq()
    |> Enum.each(fn field ->
      if field not in current_field_names do
        Lifecycle.delete_texts_for_source_field(source_type, source_id, field)
      end
    end)

    :ok
  end

  # =============================================================================
  # Private — Queries and Generic Helpers
  # =============================================================================

  defp project_flow_nodes(project_id) do
    Repo.all(
      from(n in FlowNodeRecord,
        join: f in FlowRecord,
        on: n.flow_id == f.id,
        where: f.project_id == ^project_id and is_nil(f.deleted_at) and is_nil(n.deleted_at),
        order_by: [asc: n.id]
      )
    )
  end

  defp runtime_sources(project_id) do
    build_sources(project_flow_nodes(project_id), "flow_node", &flow_node_source_fields/1) ++
      build_sources(load_project_blocks(project_id), "block", &block_source_fields/1) ++
      build_sources(runtime_sheets(project_id), "sheet", &speaker_source_fields/1)
  end

  defp load_project_blocks(project_id) do
    Repo.all(
      from(b in BlockRecord,
        join: s in SheetRecord,
        on: b.sheet_id == s.id,
        where: s.project_id == ^project_id and is_nil(s.deleted_at) and is_nil(b.deleted_at),
        order_by: [asc: b.id]
      )
    )
  end

  defp flow_project_id(flow_id) do
    Repo.one(from(f in FlowRecord, where: f.id == ^flow_id and is_nil(f.deleted_at), select: f.project_id))
  end

  defp flow_node_project_id(node_id) do
    Repo.one(
      from(n in FlowNodeRecord,
        join: f in FlowRecord,
        on: f.id == n.flow_id,
        where: n.id == ^node_id,
        select: f.project_id
      )
    )
  end

  defp sheet_project_id(sheet_id) do
    Repo.one(
      from(s in SheetRecord,
        where: s.id == ^sheet_id and is_nil(s.deleted_at),
        select: s.project_id
      )
    )
  end

  defp sheet_project_ids(sheet_ids) do
    Repo.all(
      from(sheet in SheetRecord,
        where: sheet.id in ^sheet_ids,
        distinct: true,
        order_by: [asc: sheet.project_id],
        select: sheet.project_id
      )
    )
  end

  defp block_project_id(block_id) do
    Repo.one(
      from(b in BlockRecord,
        join: s in SheetRecord,
        on: s.id == b.sheet_id,
        where: b.id == ^block_id,
        select: s.project_id
      )
    )
  end

  defp get_target_locales(project_id) do
    Repo.all(
      from(language in LanguageRecord,
        where:
          language.project_id == ^project_id and language.is_source == false and
            is_nil(language.archived_at),
        order_by: [asc: language.position, asc: language.name],
        select: language.locale_code
      )
    )
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

  defp list_value(values) when is_list(values), do: values
  defp list_value(_values), do: []

  defp hash(text) when is_binary(text) do
    :sha256 |> :crypto.hash(text) |> Base.encode16(case: :lower)
  end

  defp word_count(text), do: HtmlUtils.word_count(text)
end

defmodule Storyarn.Localization.LocalizableWords do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Localization.LanguageCrud
  alias Storyarn.Localization.SourceContract
  alias Storyarn.Localization.TextCrud
  alias Storyarn.Repo
  alias Storyarn.Shared.HtmlUtils
  alias Storyarn.Sheets.Block
  alias Storyarn.Sheets.Sheet

  @inventory_lock_namespace 4_716_000_000_000

  # =============================================================================
  # Public — Runtime Word Counts
  # =============================================================================

  @doc "Returns per-flow counts for player-facing runtime text."
  @spec flow_word_counts(integer()) :: %{integer() => non_neg_integer()}
  def flow_word_counts(project_id) do
    project_id
    |> project_flow_nodes()
    |> Enum.group_by(& &1.flow_id)
    |> Map.new(fn {flow_id, nodes} ->
      {flow_id, nodes |> Enum.flat_map(&flow_node_source_fields/1) |> count_fields()}
    end)
  end

  @doc "Returns per-sheet counts for exported sheet names and textual runtime variables."
  @spec sheet_word_counts(integer()) :: %{integer() => non_neg_integer()}
  def sheet_word_counts(project_id) do
    block_counts =
      project_id
      |> load_project_blocks()
      |> Enum.group_by(& &1.sheet_id)
      |> Map.new(fn {sheet_id, blocks} ->
        {sheet_id, blocks |> Enum.flat_map(&block_source_fields/1) |> count_fields()}
      end)

    project_id
    |> runtime_sheets()
    |> Map.new(fn sheet -> {sheet.id, sheet |> speaker_source_fields() |> count_fields()} end)
    |> Map.merge(block_counts, fn _sheet_id, name_words, block_words -> name_words + block_words end)
  end

  # =============================================================================
  # Public — Extraction
  # =============================================================================

  @doc """
  Reconciles the project's localization inventory with its current runtime
  export contract.

  Existing translations for live fields and archived locales are preserved.
  Rows for deleted fields, deleted entities, editor-only metadata, scenes, and
  screenplays are archived outside the active inventory.
  """
  @spec extract_all(integer()) :: {:ok, non_neg_integer()}
  def extract_all(project_id) do
    with_inventory_lock(project_id, fn -> reconcile_current_inventory(project_id) end)
  end

  defp reconcile_current_inventory(project_id) do
    target_locales = get_target_locales(project_id)
    flow_nodes = project_flow_nodes(project_id)

    sources =
      build_sources(flow_nodes, "flow_node", &flow_node_source_fields/1) ++
        build_sources(load_project_blocks(project_id), "block", &block_source_fields/1) ++
        build_sources(runtime_sheets(project_id), "sheet", &speaker_source_fields/1)

    entries =
      for source <- sources, locale <- target_locales do
        source_to_entry(source, locale)
      end

    source_keys = MapSet.new(sources, &source_key/1)

    case TextCrud.reconcile_project_texts(project_id, entries, source_keys) do
      {:ok, count} -> count
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  @spec extract_flow_node(FlowNode.t()) :: :ok
  def extract_flow_node(%FlowNode{} = node) do
    with project_id when not is_nil(project_id) <- flow_project_id(node.flow_id) do
      with_inventory_lock(project_id, fn -> reconcile_flow_node(project_id, node.id) end)
    end

    :ok
  end

  @spec extract_block(Block.t()) :: :ok
  def extract_block(%Block{} = block) do
    with project_id when not is_nil(project_id) <- sheet_project_id(block.sheet_id) do
      with_inventory_lock(project_id, fn -> reconcile_block(project_id, block.id) end)
    end

    :ok
  end

  defp reconcile_flow_node(project_id, node_id) do
    case Repo.get(FlowNode, node_id) do
      %FlowNode{deleted_at: nil} = current ->
        upsert_source_fields(project_id, "flow_node", current.id, flow_node_source_fields(current))

      _missing_or_deleted ->
        TextCrud.archive_texts_for_source("flow_node", node_id, "source_deleted")
        :ok
    end
  end

  defp reconcile_block(project_id, block_id) do
    case Repo.get(Block, block_id) do
      %Block{} = current when is_nil(current.deleted_at) -> reconcile_current_block(project_id, current)
      _missing_or_deleted -> TextCrud.archive_texts_for_source("block", block_id, "source_deleted")
    end

    :ok
  end

  defp reconcile_current_block(project_id, block) do
    if SourceContract.localizable_block?(block) do
      upsert_source_fields(project_id, "block", block.id, block_source_fields(block))
    else
      TextCrud.archive_texts_for_source("block", block.id, "source_not_runtime")
    end
  end

  @doc "Synchronizes active sheet names because engine serializers emit sheets as runtime actors."
  @spec sync_sheet_names(integer()) :: :ok
  def sync_sheet_names(project_id) do
    with_inventory_lock(project_id, fn ->
      sources = build_sources(runtime_sheets(project_id), "sheet", &speaker_source_fields/1)
      locales = get_target_locales(project_id)

      entries = for source <- sources, locale <- locales, do: source_to_entry(source, locale)
      TextCrud.batch_upsert_texts(project_id, entries)

      active_ids = MapSet.new(sources, & &1.source_id)

      project_id
      |> TextCrud.list_texts(source_type: "sheet")
      |> Enum.map(& &1.source_id)
      |> Enum.uniq()
      |> Enum.reject(&MapSet.member?(active_ids, &1))
      |> Enum.each(&TextCrud.archive_texts_for_source("sheet", &1, "source_not_runtime"))

      :ok
    end)

    :ok
  end

  @spec extract_flow_nodes(integer()) :: :ok
  def extract_flow_nodes(flow_id) do
    from(n in FlowNode, where: n.flow_id == ^flow_id and is_nil(n.deleted_at))
    |> Repo.all()
    |> Enum.each(&extract_flow_node/1)

    :ok
  end

  @spec extract_sheet_blocks(integer()) :: :ok
  def extract_sheet_blocks(sheet_id) do
    from(b in Block, where: b.sheet_id == ^sheet_id and is_nil(b.deleted_at))
    |> Repo.all()
    |> Enum.each(&extract_block/1)

    :ok
  end

  @spec extract_block_tree(integer()) :: :ok
  def extract_block_tree(block_id) do
    from(b in Block,
      where:
        (b.id == ^block_id or b.inherited_from_block_id == ^block_id) and
          is_nil(b.deleted_at)
    )
    |> Repo.all()
    |> Enum.each(&extract_block/1)

    :ok
  end

  @spec delete_flow_node_texts(integer()) :: :ok
  def delete_flow_node_texts(node_id) do
    with_source_project_lock(flow_node_project_id(node_id), fn ->
      TextCrud.delete_texts_for_source("flow_node", node_id)
    end)

    :ok
  end

  @spec delete_flow_node_texts_for_flows([integer()]) :: :ok
  def delete_flow_node_texts_for_flows([]), do: :ok

  def delete_flow_node_texts_for_flows(flow_ids) do
    with_source_project_lock(flow_project_id(List.first(flow_ids)), fn ->
      node_ids = Repo.all(from(n in FlowNode, where: n.flow_id in ^flow_ids, select: n.id))
      TextCrud.delete_texts_for_sources("flow_node", node_ids)
    end)

    :ok
  end

  @spec delete_block_texts(integer()) :: :ok
  def delete_block_texts(block_id) do
    with_source_project_lock(block_project_id(block_id), fn -> TextCrud.delete_texts_for_source("block", block_id) end)
    :ok
  end

  @spec delete_block_tree_texts(integer()) :: :ok
  def delete_block_tree_texts(block_id) do
    with_source_project_lock(block_project_id(block_id), fn ->
      block_ids =
        Repo.all(
          from(b in Block,
            where: b.id == ^block_id or b.inherited_from_block_id == ^block_id,
            select: b.id
          )
        )

      TextCrud.delete_texts_for_sources("block", block_ids)
    end)

    :ok
  end

  @spec delete_block_texts_for_sheets([integer()]) :: :ok
  def delete_block_texts_for_sheets([]), do: :ok

  def delete_block_texts_for_sheets(sheet_ids) do
    with_source_project_lock(sheet_project_id(List.first(sheet_ids)), fn ->
      block_ids = Repo.all(from(b in Block, where: b.sheet_id in ^sheet_ids, select: b.id))
      TextCrud.delete_texts_for_sources("block", block_ids)
    end)

    :ok
  end

  # =============================================================================
  # Private — Runtime Source Contract
  # =============================================================================

  defp flow_node_source_fields(%FlowNode{type: "dialogue", data: data}) do
    speaker_sheet_id = data["speaker_sheet_id"]

    optional_field("text", data["text"], "dialogue",
      vo_eligible: true,
      speaker_sheet_id: speaker_sheet_id
    ) ++
      optional_field("stage_directions", data["stage_directions"], "stage_direction") ++
      optional_field("menu_text", data["menu_text"], "menu") ++
      indexed_response_fields(list_value(data["responses"]), speaker_sheet_id)
  end

  defp flow_node_source_fields(%FlowNode{type: "exit", data: data}) do
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

  defp block_source_fields(%Block{value: value} = block) do
    if SourceContract.localizable_block?(block) do
      optional_field("value.content", value["content"], "runtime_value")
    else
      []
    end
  end

  defp speaker_source_fields(%Sheet{name: name}) do
    optional_field("name", name, "speaker_name")
  end

  defp runtime_sheets(project_id) do
    Repo.all(
      from(s in Sheet,
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

    TextCrud.batch_upsert_texts(project_id, entries)

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
      Repo.query!("SELECT pg_advisory_xact_lock($1::bigint)", [@inventory_lock_namespace + project_id])
      fun.()
    end)
  end

  defp with_source_project_lock(nil, _fun), do: :ok
  defp with_source_project_lock(project_id, fun), do: with_inventory_lock(project_id, fun)

  defp cleanup_removed_fields(source_type, source_id, current_fields) do
    current_field_names = MapSet.new(current_fields, & &1.field)

    source_type
    |> TextCrud.get_texts_for_source(source_id)
    |> Enum.map(& &1.source_field)
    |> Enum.uniq()
    |> Enum.each(fn field ->
      if field not in current_field_names do
        TextCrud.delete_texts_for_source_field(source_type, source_id, field)
      end
    end)

    :ok
  end

  # =============================================================================
  # Private — Queries and Generic Helpers
  # =============================================================================

  defp project_flow_nodes(project_id) do
    Repo.all(
      from(n in FlowNode,
        join: f in Flow,
        on: n.flow_id == f.id,
        where: f.project_id == ^project_id and is_nil(f.deleted_at) and is_nil(n.deleted_at),
        order_by: [asc: n.id]
      )
    )
  end

  defp load_project_blocks(project_id) do
    Repo.all(
      from(b in Block,
        join: s in Sheet,
        on: b.sheet_id == s.id,
        where: s.project_id == ^project_id and is_nil(s.deleted_at) and is_nil(b.deleted_at),
        order_by: [asc: b.id]
      )
    )
  end

  defp flow_project_id(flow_id) do
    Repo.one(from(f in Flow, where: f.id == ^flow_id and is_nil(f.deleted_at), select: f.project_id))
  end

  defp flow_node_project_id(node_id) do
    Repo.one(
      from(n in FlowNode,
        join: f in Flow,
        on: f.id == n.flow_id,
        where: n.id == ^node_id,
        select: f.project_id
      )
    )
  end

  defp sheet_project_id(sheet_id) do
    Repo.one(from(s in Sheet, where: s.id == ^sheet_id and is_nil(s.deleted_at), select: s.project_id))
  end

  defp block_project_id(block_id) do
    Repo.one(
      from(b in Block,
        join: s in Sheet,
        on: s.id == b.sheet_id,
        where: b.id == ^block_id,
        select: s.project_id
      )
    )
  end

  defp get_target_locales(project_id) do
    project_id
    |> LanguageCrud.get_target_languages()
    |> Enum.map(& &1.locale_code)
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

  defp count_fields(fields), do: Enum.sum(Enum.map(fields, &word_count(&1.text)))

  defp hash(text) when is_binary(text) do
    :sha256 |> :crypto.hash(text) |> Base.encode16(case: :lower)
  end

  defp word_count(text), do: HtmlUtils.word_count(text)
end

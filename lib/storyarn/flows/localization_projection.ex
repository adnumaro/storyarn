defmodule Storyarn.Flows.LocalizationProjection do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Flows.Persistence.LocalizedTextRecord
  alias Storyarn.Flows.Persistence.ProjectLanguageRecord
  alias Storyarn.Flows.ProjectReferenceIntegrity
  alias Storyarn.Repo
  alias Storyarn.Shared.HtmlUtils
  alias Storyarn.Shared.TimeHelpers

  @inventory_lock_namespace "storyarn:localization:inventory"
  @flow_node_lock_namespace "storyarn:localization:flow_node"

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

  @spec extract_flow_node(map() | struct()) :: :ok | {:error, term()}
  def extract_flow_node(%{id: node_id, flow_id: flow_id}) do
    case flow_project_id(flow_id) do
      nil ->
        :ok

      project_id ->
        project_id
        |> with_source_lock(node_id, fn -> reconcile_flow_node(project_id, node_id) end)
        |> normalize_lock_result()
    end
  end

  @spec extract_flow_nodes(integer()) :: :ok | {:error, term()}
  def extract_flow_nodes(flow_id) do
    case flow_project_id(flow_id) do
      nil ->
        :ok

      project_id ->
        project_id
        |> with_inventory_lock(fn ->
          FlowNode
          |> where([node], node.flow_id == ^flow_id)
          |> Repo.all()
          |> Enum.each(&reconcile_flow_node(project_id, &1.id))

          :ok
        end)
        |> normalize_lock_result()
    end
  end

  @spec flow_node_texts_current_ids([map() | struct()], integer()) :: MapSet.t(integer())
  def flow_node_texts_current_ids([], project_id) when is_integer(project_id), do: MapSet.new()

  def flow_node_texts_current_ids(nodes, project_id) when is_list(nodes) and is_integer(project_id) do
    target_locales = target_locales(project_id)
    actual_by_node = flow_node_text_signatures(Enum.map(nodes, & &1.id))

    Enum.reduce(nodes, MapSet.new(), fn node, current_ids ->
      expected = expected_signatures(node, project_id, target_locales)
      actual = Map.get(actual_by_node, node.id, [])

      if Enum.sort(expected) == Enum.sort(actual),
        do: MapSet.put(current_ids, node.id),
        else: current_ids
    end)
  end

  @spec delete_flow_node_texts(integer()) :: :ok
  def delete_flow_node_texts(node_id) do
    with_project_inventory_lock(flow_node_project_id(node_id), fn ->
      archive_texts_for_sources([node_id])
    end)

    :ok
  end

  @spec delete_flow_node_texts_for_flows([integer()]) :: :ok
  def delete_flow_node_texts_for_flows([]), do: :ok

  def delete_flow_node_texts_for_flows(flow_ids) do
    with_project_inventory_lock(flow_project_id(List.first(flow_ids)), fn ->
      node_ids =
        Repo.all(
          from(node in FlowNode,
            where: node.flow_id in ^flow_ids,
            select: node.id
          )
        )

      archive_texts_for_sources(node_ids)
    end)

    :ok
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

  defp reconcile_flow_node(project_id, node_id) do
    case Repo.get(FlowNode, node_id) do
      %FlowNode{deleted_at: nil} = node ->
        upsert_source_fields(project_id, node)

      _missing_or_deleted ->
        archive_texts_for_sources([node_id])
        :ok
    end
  end

  defp upsert_source_fields(project_id, node) do
    fields = flow_node_source_fields(node)
    locales = target_locales(project_id)

    entries =
      for field <- fields, locale <- locales do
        %{
          project_id: project_id,
          source_type: "flow_node",
          source_id: node.id,
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

    batch_upsert(entries)
    archive_removed_fields(node.id, MapSet.new(fields, & &1.field))
    :ok
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

  defp archive_removed_fields(node_id, current_fields) do
    node_id
    |> active_source_fields()
    |> Enum.reject(&MapSet.member?(current_fields, &1))
    |> Enum.each(fn field ->
      now = TimeHelpers.now()

      Repo.update_all(
        from(text in LocalizedTextRecord,
          where:
            text.source_type == "flow_node" and text.source_id == ^node_id and
              text.source_field == ^field and is_nil(text.archived_at)
        ),
        set: [archived_at: now, archive_reason: "source_field_removed", updated_at: now],
        inc: [lock_version: 1]
      )
    end)
  end

  defp active_source_fields(node_id) do
    Repo.all(
      from(text in LocalizedTextRecord,
        where:
          text.source_type == "flow_node" and text.source_id == ^node_id and
            is_nil(text.archived_at),
        distinct: true,
        select: text.source_field
      )
    )
  end

  defp archive_texts_for_sources([]), do: {0, nil}

  defp archive_texts_for_sources(node_ids) do
    now = TimeHelpers.now()

    Repo.update_all(
      from(text in LocalizedTextRecord,
        where:
          text.source_type == "flow_node" and text.source_id in ^node_ids and
            is_nil(text.archived_at)
      ),
      set: [archived_at: now, archive_reason: "source_deleted", updated_at: now],
      inc: [lock_version: 1]
    )
  end

  defp expected_signatures(node, project_id, locales) do
    for field <- flow_node_source_fields(node), locale <- locales do
      {
        project_id,
        field.field,
        locale,
        field.text,
        hash(field.text),
        HtmlUtils.word_count(field.text),
        field.speaker_sheet_id,
        field.content_role,
        field.vo_eligible
      }
    end
  end

  defp flow_node_text_signatures([]), do: %{}

  defp flow_node_text_signatures(node_ids) do
    from(text in LocalizedTextRecord,
      where:
        text.source_type == "flow_node" and text.source_id in ^node_ids and
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
      fn {_source_id, project_id, field, locale, text, source_hash, words, speaker, role, vo} ->
        {project_id, field, locale, text, source_hash, words, speaker, role, vo}
      end
    )
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
        order_by: [asc: language.position, asc: language.id],
        select: language.locale_code
      )
    )
  end

  defp flow_project_id(flow_id) do
    Repo.one(
      from(flow in Flow,
        where: flow.id == ^flow_id and is_nil(flow.deleted_at),
        select: flow.project_id
      )
    )
  end

  defp flow_node_project_id(node_id) do
    Repo.one(
      from(node in FlowNode,
        join: flow in Flow,
        on: flow.id == node.flow_id,
        where: node.id == ^node_id,
        select: flow.project_id
      )
    )
  end

  defp with_project_inventory_lock(nil, _callback), do: :ok
  defp with_project_inventory_lock(project_id, callback), do: with_inventory_lock(project_id, callback)

  defp with_inventory_lock(project_id, callback) do
    Repo.transaction(fn ->
      lock_active_project!(project_id)
      lock_exclusive!(@inventory_lock_namespace, project_id)
      callback.()
    end)
  end

  defp with_source_lock(project_id, node_id, callback) do
    Repo.transaction(fn ->
      lock_active_project!(project_id)
      lock_shared!(@inventory_lock_namespace, project_id)
      lock_exclusive!(@flow_node_lock_namespace, node_id)
      callback.()
    end)
  end

  defp lock_active_project!(project_id) do
    case ProjectReferenceIntegrity.lock_active_project(project_id, :update) do
      {:ok, _project} -> :ok
      {:error, reason} -> Repo.rollback(reason)
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

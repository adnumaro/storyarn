defmodule Storyarn.Flows.LocalizationProjection do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Flows.Localization.Adapters.AdvisoryLocks
  alias Storyarn.Flows.Localization.Adapters.LocalizedTextUpsert
  alias Storyarn.Flows.Localization.Data.LocalizedTextRecord
  alias Storyarn.Flows.Localization.Data.ProjectLanguageRecord
  alias Storyarn.Flows.References
  alias Storyarn.Platform.Shared.HtmlUtils
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Repo

  @inventory_lock_namespace "storyarn:localization:inventory"
  @flow_node_lock_namespace "storyarn:localization:flow_node"

  @doc false
  @spec lock_inventory!(integer()) :: :ok
  def lock_inventory!(project_id) when is_integer(project_id) do
    if Repo.in_transaction?() do
      AdvisoryLocks.lock_exclusive!(@inventory_lock_namespace, project_id)
      :ok
    else
      raise ArgumentError, "localization inventory locks require an explicit database transaction"
    end
  end

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

    LocalizedTextUpsert.upsert(entries)
    archive_removed_fields(node.id, MapSet.new(fields, & &1.field))
    :ok
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
    case References.lock_active_project(project_id, :update) do
      {:ok, _project} -> :ok
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp lock_exclusive!(namespace, id) do
    AdvisoryLocks.lock_exclusive!(namespace, id)
  end

  defp lock_shared!(namespace, id) do
    AdvisoryLocks.lock_shared!(namespace, id)
  end

  defp normalize_lock_result({:ok, {:error, reason}}), do: {:error, reason}
  defp normalize_lock_result({:ok, _result}), do: :ok
  defp normalize_lock_result({:error, reason}), do: {:error, reason}
  defp normalize_lock_result(:ok), do: :ok

  defp hash(text), do: :sha256 |> :crypto.hash(text) |> Base.encode16(case: :lower)
end

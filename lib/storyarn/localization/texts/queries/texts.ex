defmodule Storyarn.Localization.Texts.Queries.Texts do
  @moduledoc "Queries over the Texts-owned localized-text inventory."

  import Ecto.Query, warn: false

  alias Storyarn.Localization.LocalizedText
  alias Storyarn.Repo

  @doc """
  Lists localized texts for a project.

  Filters: `:locale_code`, `:status`, `:source_type`, `:speaker_sheet_id`,
  `:vo_status` (voice-over eligible rows only), `:stale` (translations written
  against an older source revision) and `:search`. `:preload` names the
  associations to load with the rows.
  """
  def list_texts(project_id, opts \\ []) do
    from(t in LocalizedText,
      where: t.project_id == ^project_id,
      order_by: [asc: t.source_type, asc: t.source_id, asc: t.source_field]
    )
    |> apply_filters(opts)
    |> maybe_paginate(opts[:limit], opts[:offset])
    |> maybe_preload(opts[:preload])
    |> Repo.all()
  end

  def count_texts(project_id, opts \\ []) do
    from(t in LocalizedText, where: t.project_id == ^project_id, select: count(t.id))
    |> apply_filters(opts)
    |> Repo.one!()
  end

  def get_text(project_id, id) do
    Repo.one(
      from(t in LocalizedText,
        where: t.id == ^id and t.project_id == ^project_id and is_nil(t.archived_at)
      )
    )
  end

  @doc "Gets a localized text with the associations named in `:preload` loaded."
  def get_text(project_id, id, opts) do
    project_id
    |> get_text(id)
    |> preload_struct(opts[:preload])
  end

  def get_text!(project_id, id) do
    Repo.one!(
      from(t in LocalizedText,
        where: t.id == ^id and t.project_id == ^project_id and is_nil(t.archived_at)
      )
    )
  end

  def get_text_by_source(source_type, source_id, source_field, locale_code) do
    get_text_by_source(source_type, source_id, source_field, locale_code, [])
  end

  def get_text_by_source(source_type, source_id, source_field, locale_code, opts) do
    from(t in LocalizedText,
      where:
        t.source_type == ^source_type and t.source_id == ^source_id and
          t.source_field == ^source_field and t.locale_code == ^locale_code
    )
    |> maybe_filter_archived(opts[:include_archived])
    |> Repo.one()
  end

  def get_texts_for_source(source_type, source_id) do
    Repo.all(
      from(t in LocalizedText,
        where: t.source_type == ^source_type and t.source_id == ^source_id and is_nil(t.archived_at),
        order_by: [asc: t.source_field, asc: t.locale_code]
      )
    )
  end

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
      from(t in LocalizedText,
        where: t.project_id == ^project_id and t.locale_code == ^locale_code and is_nil(t.archived_at),
        select: count(t.id)
      )
      |> where(^stale_condition())
      |> Repo.one!()

    total = counts |> Map.values() |> Enum.sum()

    %{
      total: total,
      pending: Map.get(counts, "pending", 0),
      draft: Map.get(counts, "draft", 0),
      in_progress: Map.get(counts, "in_progress", 0),
      review: Map.get(counts, "review", 0),
      final: Map.get(counts, "final", 0),
      stale: stale
    }
  end

  defp apply_filters(query, opts) do
    query
    |> maybe_filter_archived(opts[:include_archived])
    |> maybe_filter_locale(opts[:locale_code])
    |> maybe_filter_status(opts[:status])
    |> maybe_filter_source_type(opts[:source_type])
    |> maybe_filter_speaker(opts[:speaker_sheet_id])
    |> maybe_filter_vo_status(opts[:vo_status])
    |> maybe_filter_stale(opts[:stale])
    |> maybe_search(opts[:search])
  end

  defp maybe_filter_locale(query, nil), do: query
  defp maybe_filter_locale(query, locale_code), do: where(query, [t], t.locale_code == ^locale_code)
  defp maybe_filter_archived(query, true), do: query
  defp maybe_filter_archived(query, _include_archived), do: where(query, [t], is_nil(t.archived_at))
  defp maybe_filter_status(query, nil), do: query
  defp maybe_filter_status(query, status), do: where(query, [t], t.status == ^status)
  defp maybe_filter_source_type(query, nil), do: query
  defp maybe_filter_source_type(query, source_type), do: where(query, [t], t.source_type == ^source_type)
  defp maybe_filter_speaker(query, nil), do: query
  defp maybe_filter_speaker(query, speaker_sheet_id), do: where(query, [t], t.speaker_sheet_id == ^speaker_sheet_id)
  defp maybe_filter_vo_status(query, nil), do: query

  defp maybe_filter_vo_status(query, vo_status),
    do: where(query, [t], t.vo_eligible == true and t.vo_status == ^vo_status)

  defp maybe_filter_stale(query, true), do: where(query, ^stale_condition())
  defp maybe_filter_stale(query, _stale), do: query

  # One stale predicate for the progress count and the list it opens, matching
  # `LocalizedText.stale?/1` and the Reporting queries: a non-blank translation
  # written against an older source revision.
  defp stale_condition do
    dynamic(
      [t],
      not is_nil(t.translated_text) and fragment("btrim(?) <> ''", t.translated_text) and
        (is_nil(t.translated_source_hash) or t.translated_source_hash != t.source_text_hash)
    )
  end

  defp maybe_search(query, nil), do: query
  defp maybe_search(query, ""), do: query

  defp maybe_search(query, search) do
    sanitized = Storyarn.Platform.Shared.SearchHelpers.sanitize_like_query(search)
    pattern = "%#{sanitized}%"
    where(query, [t], ilike(t.source_text, ^pattern) or ilike(t.translated_text, ^pattern))
  end

  defp maybe_paginate(query, nil, _offset), do: query
  defp maybe_paginate(query, limit, offset), do: query |> limit(^limit) |> offset(^(offset || 0))
  defp maybe_preload(query, nil), do: query
  defp maybe_preload(query, preloads), do: preload(query, ^preloads)
  defp preload_struct(text, nil), do: text
  defp preload_struct(text, preloads), do: Repo.preload(text, preloads)
end

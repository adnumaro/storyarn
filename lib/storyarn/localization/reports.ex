defmodule Storyarn.Localization.Reports do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Localization.LocalizedText
  alias Storyarn.Localization.ProjectLanguage
  alias Storyarn.Repo
  alias Storyarn.Sheets.Sheet

  @doc """
  Returns progress per language for a project.
  Returns a list of `%{locale_code: String.t(), name: String.t(), total: integer(), final: integer(), percentage: float()}`.
  """
  def progress_by_language(project_id) do
    counts_by_locale = status_counts_by_locale(project_id)
    stale_by_locale = stale_counts_by_locale(project_id)

    project_id
    |> target_languages()
    |> Enum.map(&language_progress(&1, counts_by_locale, stale_by_locale))
  end

  defp target_languages(project_id) do
    Repo.all(
      from(l in ProjectLanguage,
        where: l.project_id == ^project_id and l.is_source == false and is_nil(l.archived_at),
        order_by: [asc: l.position, asc: l.name]
      )
    )
  end

  defp status_counts_by_locale(project_id) do
    from(t in LocalizedText,
      where: t.project_id == ^project_id and is_nil(t.archived_at),
      group_by: [t.locale_code, t.status],
      select: {t.locale_code, t.status, count(t.id)}
    )
    |> Repo.all()
    |> Enum.group_by(&elem(&1, 0), fn {_locale, status, count} -> {status, count} end)
    |> Map.new(fn {locale, pairs} -> {locale, Map.new(pairs)} end)
  end

  defp stale_counts_by_locale(project_id) do
    from(t in LocalizedText,
      where:
        t.project_id == ^project_id and is_nil(t.archived_at) and
          not is_nil(t.translated_text) and
          fragment("btrim(?) <> ''", t.translated_text) and
          (is_nil(t.translated_source_hash) or t.translated_source_hash != t.source_text_hash),
      group_by: t.locale_code,
      select: {t.locale_code, count(t.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp language_progress(language, counts_by_locale, stale_by_locale) do
    stats = Map.get(counts_by_locale, language.locale_code, %{})
    total = stats |> Map.values() |> Enum.sum()
    final = Map.get(stats, "final", 0)

    %{
      locale_code: language.locale_code,
      name: language.name,
      total: total,
      final: final,
      review: Map.get(stats, "review", 0),
      stale: Map.get(stale_by_locale, language.locale_code, 0),
      percentage: completion_percentage(final, total)
    }
  end

  defp completion_percentage(final, total) when total > 0, do: Float.round(final / total * 100, 1)
  defp completion_percentage(_final, _total), do: 0.0

  @doc """
  Returns word counts per speaker for a project and locale.
  Returns a list of `%{speaker_sheet_id: integer() | nil, word_count: integer(), line_count: integer()}`.
  """
  def word_counts_by_speaker(project_id, locale_code) do
    Repo.all(
      from(t in LocalizedText,
        left_join: s in Sheet,
        on: s.id == t.speaker_sheet_id and is_nil(s.deleted_at),
        where:
          t.project_id == ^project_id and t.locale_code == ^locale_code and
            is_nil(t.archived_at) and
            t.vo_eligible == true,
        group_by: [t.speaker_sheet_id, s.name],
        select: %{
          speaker_sheet_id: t.speaker_sheet_id,
          speaker_name: s.name,
          word_count: coalesce(sum(t.word_count), 0),
          line_count: count(t.id)
        },
        order_by: [desc: sum(t.word_count)]
      )
    )
  end

  @doc """
  Returns VO (voice-over) progress for a project and locale.
  Returns `%{none: integer(), needed: integer(), recorded: integer(), approved: integer()}`.
  """
  def vo_progress(project_id, locale_code) do
    from(t in LocalizedText,
      where:
        t.project_id == ^project_id and
          t.locale_code == ^locale_code and
          is_nil(t.archived_at) and
          t.vo_eligible == true,
      group_by: t.vo_status,
      select: {t.vo_status, count(t.id)}
    )
    |> Repo.all()
    |> Map.new()
    |> then(fn counts ->
      %{
        none: Map.get(counts, "none", 0),
        needed: Map.get(counts, "needed", 0),
        recorded: Map.get(counts, "recorded", 0),
        approved: Map.get(counts, "approved", 0)
      }
    end)
  end

  @doc """
  Returns count of texts by source type for a project and locale.
  """
  def counts_by_source_type(project_id, locale_code) do
    from(t in LocalizedText,
      where:
        t.project_id == ^project_id and t.locale_code == ^locale_code and
          is_nil(t.archived_at),
      group_by: t.source_type,
      select: {t.source_type, count(t.id)},
      order_by: [desc: count(t.id)]
    )
    |> Repo.all()
    |> Map.new()
  end
end

defmodule Storyarn.Localization.Reports do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Localization.{LocalizedText, ProjectLanguage}
  alias Storyarn.Repo

  @doc """
  Returns progress per language for a project.
  Returns a list of `%{locale_code: String.t(), name: String.t(), total: integer(), final: integer(), percentage: float()}`.
  """
  def progress_by_language(project_id) do
    languages =
      from(l in ProjectLanguage,
        where: l.project_id == ^project_id and l.is_source == false,
        order_by: [asc: l.position, asc: l.name]
      )
      |> Repo.all()

    Enum.map(languages, fn lang ->
      stats = status_counts(project_id, lang.locale_code)
      total = Enum.reduce(stats, 0, fn {_status, count}, acc -> acc + count end)
      final = Map.get(stats, "final", 0)

      %{
        locale_code: lang.locale_code,
        name: lang.name,
        total: total,
        final: final,
        percentage: if(total > 0, do: Float.round(final / total * 100, 1), else: 0.0)
      }
    end)
  end

  @doc """
  Returns word counts per speaker for a project and locale.
  Returns a list of `%{speaker_sheet_id: integer() | nil, word_count: integer(), line_count: integer()}`.
  """
  def word_counts_by_speaker(project_id, locale_code) do
    from(t in LocalizedText,
      where:
        t.project_id == ^project_id and
          t.locale_code == ^locale_code and
          t.source_type == "flow_node",
      group_by: t.speaker_sheet_id,
      select: %{
        speaker_sheet_id: t.speaker_sheet_id,
        word_count: coalesce(sum(t.word_count), 0),
        line_count: count(t.id)
      },
      order_by: [desc: sum(t.word_count)]
    )
    |> Repo.all()
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
          t.source_type == "flow_node",
      group_by: t.vo_status,
      select: {t.vo_status, count(t.id)}
    )
    |> Repo.all()
    |> Enum.into(%{})
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
      where: t.project_id == ^project_id and t.locale_code == ^locale_code,
      group_by: t.source_type,
      select: {t.source_type, count(t.id)},
      order_by: [desc: count(t.id)]
    )
    |> Repo.all()
    |> Enum.into(%{})
  end

  # =============================================================================
  # Private
  # =============================================================================

  defp status_counts(project_id, locale_code) do
    from(t in LocalizedText,
      where: t.project_id == ^project_id and t.locale_code == ^locale_code,
      group_by: t.status,
      select: {t.status, count(t.id)}
    )
    |> Repo.all()
    |> Enum.into(%{})
  end
end

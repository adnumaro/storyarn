defmodule Storyarn.Localization.Glossary.Queries.Entries do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Localization.GlossaryEntry
  alias Storyarn.Repo

  def list(project_id, opts \\ []) do
    from(entry in GlossaryEntry,
      where: entry.project_id == ^project_id,
      order_by: [asc: entry.source_term]
    )
    |> maybe_filter_locale_pair(opts[:source_locale], opts[:target_locale])
    |> maybe_search(opts[:search])
    |> Repo.all()
  end

  def get(project_id, id) do
    Repo.one(from(entry in GlossaryEntry, where: entry.id == ^id and entry.project_id == ^project_id))
  end

  def get!(project_id, id) do
    Repo.one!(from(entry in GlossaryEntry, where: entry.id == ^id and entry.project_id == ^project_id))
  end

  def for_pair(project_id, source_locale, target_locale) do
    Repo.all(
      from(entry in GlossaryEntry,
        where:
          entry.project_id == ^project_id and entry.source_locale == ^source_locale and
            entry.target_locale == ^target_locale,
        select: {entry.source_term, entry.target_term},
        order_by: [asc: entry.source_term]
      )
    )
  end

  def for_export(project_id) do
    Repo.all(
      from(entry in GlossaryEntry,
        where: entry.project_id == ^project_id,
        order_by: [asc: entry.source_term, asc: entry.target_locale]
      )
    )
  end

  defp maybe_filter_locale_pair(query, nil, _target), do: query
  defp maybe_filter_locale_pair(query, _source, nil), do: query

  defp maybe_filter_locale_pair(query, source, target) do
    where(query, [entry], entry.source_locale == ^source and entry.target_locale == ^target)
  end

  defp maybe_search(query, nil), do: query
  defp maybe_search(query, ""), do: query

  defp maybe_search(query, search) do
    sanitized = Storyarn.Platform.Shared.SearchHelpers.sanitize_like_query(search)
    pattern = "%#{sanitized}%"

    where(
      query,
      [entry],
      ilike(entry.source_term, ^pattern) or ilike(entry.target_term, ^pattern)
    )
  end
end

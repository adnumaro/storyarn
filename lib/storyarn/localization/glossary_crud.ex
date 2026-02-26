defmodule Storyarn.Localization.GlossaryCrud do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Localization.GlossaryEntry
  alias Storyarn.Projects.Project
  alias Storyarn.Repo
  alias Storyarn.Shared.MapUtils

  # =============================================================================
  # Queries
  # =============================================================================

  def list_entries(project_id, opts \\ []) do
    from(e in GlossaryEntry,
      where: e.project_id == ^project_id,
      order_by: [asc: e.source_term]
    )
    |> maybe_filter_locale_pair(opts[:source_locale], opts[:target_locale])
    |> maybe_search(opts[:search])
    |> Repo.all()
  end

  def get_entry(id) do
    Repo.get(GlossaryEntry, id)
  end

  def get_entry!(id) do
    Repo.get!(GlossaryEntry, id)
  end

  @doc """
  Gets all glossary entries for a language pair.
  Returns entries as tuples `{source_term, target_term}` for DeepL API.
  """
  def get_entries_for_pair(project_id, source_locale, target_locale) do
    from(e in GlossaryEntry,
      where:
        e.project_id == ^project_id and
          e.source_locale == ^source_locale and
          e.target_locale == ^target_locale,
      select: {e.source_term, e.target_term},
      order_by: [asc: e.source_term]
    )
    |> Repo.all()
  end

  # =============================================================================
  # Mutations
  # =============================================================================

  def create_entry(%Project{} = project, attrs) do
    attrs = MapUtils.stringify_keys(attrs)

    %GlossaryEntry{project_id: project.id}
    |> GlossaryEntry.create_changeset(attrs)
    |> Repo.insert()
  end

  def update_entry(%GlossaryEntry{} = entry, attrs) do
    attrs = MapUtils.stringify_keys(attrs)

    entry
    |> GlossaryEntry.update_changeset(attrs)
    |> Repo.update()
  end

  def delete_entry(%GlossaryEntry{} = entry) do
    Repo.delete(entry)
  end

  # =============================================================================
  # Private
  # =============================================================================

  defp maybe_filter_locale_pair(query, nil, _target), do: query
  defp maybe_filter_locale_pair(query, _source, nil), do: query

  defp maybe_filter_locale_pair(query, source, target) do
    where(query, [e], e.source_locale == ^source and e.target_locale == ^target)
  end

  defp maybe_search(query, nil), do: query
  defp maybe_search(query, ""), do: query

  defp maybe_search(query, search) do
    sanitized = Storyarn.Shared.SearchHelpers.sanitize_like_query(search)
    pattern = "%#{sanitized}%"

    where(
      query,
      [e],
      ilike(e.source_term, ^pattern) or ilike(e.target_term, ^pattern)
    )
  end

  # =============================================================================
  # Export / Import helpers
  # =============================================================================

  @doc """
  Lists all glossary entries for a project for export.
  """
  def list_entries_for_export(project_id) do
    from(g in GlossaryEntry,
      where: g.project_id == ^project_id,
      order_by: [asc: g.source_term, asc: g.target_locale]
    )
    |> Repo.all()
  end

  @doc """
  Bulk-inserts glossary entries from a list of attr maps.
  """
  def bulk_import_entries(attrs_list) do
    attrs_list
    |> Enum.chunk_every(500)
    |> Enum.each(fn chunk ->
      Repo.insert_all(GlossaryEntry, chunk)
    end)
  end
end

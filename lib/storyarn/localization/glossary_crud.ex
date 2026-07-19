defmodule Storyarn.Localization.GlossaryCrud do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Localization.GlossaryEntry
  alias Storyarn.Projects.Project
  alias Storyarn.References.ProjectReferenceIntegrity
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

  def get_entry(project_id, id) do
    Repo.one(from(e in GlossaryEntry, where: e.id == ^id and e.project_id == ^project_id))
  end

  def get_entry!(project_id, id) do
    Repo.one!(from(e in GlossaryEntry, where: e.id == ^id and e.project_id == ^project_id))
  end

  @doc """
  Gets all glossary entries for a language pair.
  Returns entries as tuples `{source_term, target_term}` for DeepL API.
  """
  def get_entries_for_pair(project_id, source_locale, target_locale) do
    Repo.all(
      from(e in GlossaryEntry,
        where: e.project_id == ^project_id and e.source_locale == ^source_locale and e.target_locale == ^target_locale,
        select: {e.source_term, e.target_term},
        order_by: [asc: e.source_term]
      )
    )
  end

  # =============================================================================
  # Mutations
  # =============================================================================

  def create_entry(%Project{} = project, attrs) do
    attrs = MapUtils.stringify_keys(attrs)

    Repo.transaction(fn ->
      with {:ok, locked_project} <-
             ProjectReferenceIntegrity.lock_active_project(project.id, :update),
           {:ok, entry} <-
             %GlossaryEntry{project_id: locked_project.id}
             |> GlossaryEntry.create_changeset(attrs)
             |> Repo.insert() do
        entry
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def update_entry(%GlossaryEntry{} = entry, attrs) do
    attrs = MapUtils.stringify_keys(attrs)

    Repo.transaction(fn ->
      with {:ok, locked_entry} <- lock_active_entry(entry.id, entry.project_id),
           {:ok, updated_entry} <-
             locked_entry
             |> GlossaryEntry.update_changeset(attrs)
             |> Repo.update() do
        updated_entry
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def delete_entry(%GlossaryEntry{} = entry) do
    Repo.transaction(fn ->
      with {:ok, locked_entry} <- lock_active_entry(entry.id, entry.project_id),
           {:ok, deleted_entry} <- Repo.delete(locked_entry) do
        deleted_entry
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  # =============================================================================
  # Private
  # =============================================================================

  defp lock_active_entry(entry_id, project_id) when is_integer(entry_id) and is_integer(project_id) do
    with {:ok, _project} <-
           ProjectReferenceIntegrity.lock_active_project(project_id, :update),
         %GlossaryEntry{} = entry <-
           Repo.one(
             from(entry in GlossaryEntry,
               where: entry.id == ^entry_id and entry.project_id == ^project_id,
               lock: "FOR UPDATE"
             )
           ) do
      {:ok, entry}
    else
      nil -> {:error, :glossary_entry_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp lock_active_entry(_entry_id, _project_id), do: {:error, :glossary_entry_not_found}

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
    Repo.all(
      from(g in GlossaryEntry, where: g.project_id == ^project_id, order_by: [asc: g.source_term, asc: g.target_locale])
    )
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

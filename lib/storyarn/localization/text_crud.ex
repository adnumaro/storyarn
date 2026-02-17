defmodule Storyarn.Localization.TextCrud do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Repo
  alias Storyarn.Shared.MapUtils
  alias Storyarn.Localization.LocalizedText

  # =============================================================================
  # Queries
  # =============================================================================

  @doc """
  Lists all localized texts for a project, optionally filtered.

  Options:
  - `:locale_code` - Filter by locale
  - `:status` - Filter by status
  - `:source_type` - Filter by source type
  - `:speaker_sheet_id` - Filter by speaker
  - `:search` - Search in source_text and translated_text
  - `:limit` - Max results
  - `:offset` - Offset for pagination
  """
  def list_texts(project_id, opts \\ []) do
    from(t in LocalizedText,
      where: t.project_id == ^project_id,
      order_by: [asc: t.source_type, asc: t.source_id, asc: t.source_field]
    )
    |> maybe_filter_locale(opts[:locale_code])
    |> maybe_filter_status(opts[:status])
    |> maybe_filter_source_type(opts[:source_type])
    |> maybe_filter_speaker(opts[:speaker_sheet_id])
    |> maybe_search(opts[:search])
    |> maybe_paginate(opts[:limit], opts[:offset])
    |> Repo.all()
  end

  @doc """
  Counts localized texts for a project, optionally filtered.
  Accepts the same filter options as `list_texts/2`.
  """
  def count_texts(project_id, opts \\ []) do
    from(t in LocalizedText,
      where: t.project_id == ^project_id,
      select: count(t.id)
    )
    |> maybe_filter_locale(opts[:locale_code])
    |> maybe_filter_status(opts[:status])
    |> maybe_filter_source_type(opts[:source_type])
    |> maybe_filter_speaker(opts[:speaker_sheet_id])
    |> maybe_search(opts[:search])
    |> Repo.one!()
  end

  def get_text(id) do
    Repo.get(LocalizedText, id)
  end

  def get_text!(id) do
    Repo.get!(LocalizedText, id)
  end

  @doc """
  Gets a specific localized text by its composite key.
  """
  def get_text_by_source(source_type, source_id, source_field, locale_code) do
    from(t in LocalizedText,
      where:
        t.source_type == ^source_type and
          t.source_id == ^source_id and
          t.source_field == ^source_field and
          t.locale_code == ^locale_code
    )
    |> Repo.one()
  end

  @doc """
  Gets all localized texts for a source entity across all locales.
  """
  def get_texts_for_source(source_type, source_id) do
    from(t in LocalizedText,
      where: t.source_type == ^source_type and t.source_id == ^source_id,
      order_by: [asc: t.source_field, asc: t.locale_code]
    )
    |> Repo.all()
  end

  @doc """
  Gets translation progress stats for a project and locale.
  Returns `%{total: integer, pending: integer, draft: integer, in_progress: integer, review: integer, final: integer}`.
  """
  def get_progress(project_id, locale_code) do
    from(t in LocalizedText,
      where: t.project_id == ^project_id and t.locale_code == ^locale_code,
      group_by: t.status,
      select: {t.status, count(t.id)}
    )
    |> Repo.all()
    |> Enum.into(%{})
    |> then(fn counts ->
      total =
        Map.values(counts) |> Enum.sum()

      %{
        total: total,
        pending: Map.get(counts, "pending", 0),
        draft: Map.get(counts, "draft", 0),
        in_progress: Map.get(counts, "in_progress", 0),
        review: Map.get(counts, "review", 0),
        final: Map.get(counts, "final", 0)
      }
    end)
  end

  # =============================================================================
  # Mutations
  # =============================================================================

  def create_text(project_id, attrs) do
    attrs = MapUtils.stringify_keys(attrs)

    %LocalizedText{project_id: project_id}
    |> LocalizedText.create_changeset(attrs)
    |> Repo.insert()
  end

  def update_text(%LocalizedText{} = text, attrs) do
    attrs = MapUtils.stringify_keys(attrs)

    text
    |> LocalizedText.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Upserts a localized text by its composite key.
  Creates if not exists, updates source_text if hash changed.
  Returns `{:ok, localized_text}` or `{:error, changeset}`.
  """
  def upsert_text(project_id, attrs) do
    attrs = MapUtils.stringify_keys(attrs)

    source_type = attrs["source_type"]
    source_id = attrs["source_id"]
    source_field = attrs["source_field"]
    locale_code = attrs["locale_code"]

    case get_text_by_source(source_type, source_id, source_field, locale_code) do
      nil ->
        create_text(project_id, attrs)

      existing ->
        update_source_text(existing, attrs)
    end
  end

  @doc """
  Deletes all localized texts for a given source entity.
  Used when the source entity is deleted.
  """
  def delete_texts_for_source(source_type, source_id) do
    from(t in LocalizedText,
      where: t.source_type == ^source_type and t.source_id == ^source_id
    )
    |> Repo.delete_all()
  end

  @doc """
  Deletes all localized texts for a given source field.
  Used when a specific field is removed (e.g., a response deleted from a dialogue node).
  """
  def delete_texts_for_source_field(source_type, source_id, source_field) do
    from(t in LocalizedText,
      where:
        t.source_type == ^source_type and
          t.source_id == ^source_id and
          t.source_field == ^source_field
    )
    |> Repo.delete_all()
  end

  # =============================================================================
  # Private
  # =============================================================================

  defp update_source_text(%LocalizedText{} = existing, attrs) do
    new_hash = attrs["source_text_hash"]

    if new_hash && new_hash != existing.source_text_hash do
      # Source text changed — update source and possibly downgrade status
      new_status = if existing.status == "final", do: "review", else: existing.status

      existing
      |> LocalizedText.source_update_changeset(%{
        "source_text" => attrs["source_text"],
        "source_text_hash" => new_hash,
        "word_count" => attrs["word_count"],
        "speaker_sheet_id" => attrs["speaker_sheet_id"],
        "status" => new_status
      })
      |> Repo.update()
    else
      # Hash unchanged — no update needed (but update speaker if changed)
      if attrs["speaker_sheet_id"] != existing.speaker_sheet_id do
        existing
        |> LocalizedText.source_update_changeset(%{
          "speaker_sheet_id" => attrs["speaker_sheet_id"]
        })
        |> Repo.update()
      else
        {:ok, existing}
      end
    end
  end

  defp maybe_filter_locale(query, nil), do: query

  defp maybe_filter_locale(query, locale_code) do
    where(query, [t], t.locale_code == ^locale_code)
  end

  defp maybe_filter_status(query, nil), do: query

  defp maybe_filter_status(query, status) do
    where(query, [t], t.status == ^status)
  end

  defp maybe_filter_source_type(query, nil), do: query

  defp maybe_filter_source_type(query, source_type) do
    where(query, [t], t.source_type == ^source_type)
  end

  defp maybe_filter_speaker(query, nil), do: query

  defp maybe_filter_speaker(query, speaker_sheet_id) do
    where(query, [t], t.speaker_sheet_id == ^speaker_sheet_id)
  end

  defp maybe_search(query, nil), do: query
  defp maybe_search(query, ""), do: query

  defp maybe_search(query, search) do
    pattern = "%#{search}%"

    where(
      query,
      [t],
      ilike(t.source_text, ^pattern) or ilike(t.translated_text, ^pattern)
    )
  end

  defp maybe_paginate(query, nil, _offset), do: query

  defp maybe_paginate(query, limit, offset) do
    query
    |> limit(^limit)
    |> offset(^(offset || 0))
  end
end

defmodule Storyarn.Localization.Texts.Commands.Lifecycle do
  @moduledoc "Archives or purges Texts rows when their runtime source lifecycle changes."

  import Ecto.Query, warn: false

  alias Storyarn.Localization.LocalizedText
  alias Storyarn.Localization.Texts.Projections.LanguageRecord
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Repo

  @doc """
  Archives all localized texts for a given source entity.
  Translation work remains recoverable when the source is restored.
  """
  def delete_texts_for_source(source_type, source_id) do
    archive_texts_for_source(source_type, source_id, "source_deleted")
  end

  @doc "Deletes localized texts for a collection of source entities."
  def delete_texts_for_sources(_source_type, []), do: {0, nil}

  def delete_texts_for_sources(source_type, source_ids) do
    archive_texts_for_sources(source_type, source_ids, "source_deleted")
  end

  @doc """
  Archives all localized texts for a source field removed from the runtime contract.
  """
  def delete_texts_for_source_field(source_type, source_id, source_field) do
    now = TimeHelpers.now()

    Repo.update_all(
      from(t in LocalizedText,
        where:
          t.source_type == ^source_type and t.source_id == ^source_id and
            t.source_field == ^source_field and is_nil(t.archived_at)
      ),
      set: [archived_at: now, archive_reason: "source_field_removed", updated_at: now],
      inc: [lock_version: 1]
    )
  end

  def archive_texts_for_source(source_type, source_id, reason \\ "source_deleted") do
    archive_texts_for_sources(source_type, [source_id], reason)
  end

  def archive_texts_for_sources(_source_type, [], _reason), do: {0, nil}

  def archive_texts_for_sources(source_type, source_ids, reason) do
    now = TimeHelpers.now()

    Repo.update_all(
      from(t in LocalizedText,
        where:
          t.source_type == ^source_type and t.source_id in ^source_ids and
            is_nil(t.archived_at)
      ),
      set: [archived_at: now, archive_reason: reason, updated_at: now],
      inc: [lock_version: 1]
    )
  end

  @doc """
  Archives active localized texts only for the project's active target locales.

  Version restore uses this narrower operation so translations retained under
  archived project languages are not mutated when the snapshot contract covers
  only active target languages.
  """
  def archive_texts_for_active_target_locales(_project_id, _source_type, [], _reason), do: {0, nil}

  def archive_texts_for_active_target_locales(project_id, source_type, source_ids, reason) do
    now = TimeHelpers.now()

    active_target_locales =
      from(language in LanguageRecord,
        where:
          language.project_id == ^project_id and language.is_source == false and
            is_nil(language.archived_at),
        select: language.locale_code
      )

    Repo.update_all(
      from(text in LocalizedText,
        where:
          text.project_id == ^project_id and text.source_type == ^source_type and
            text.source_id in ^source_ids and is_nil(text.archived_at) and
            text.locale_code in subquery(active_target_locales)
      ),
      set: [archived_at: now, archive_reason: reason, updated_at: now],
      inc: [lock_version: 1]
    )
  end

  def purge_texts_for_source(source_type, source_id) do
    purge_texts_for_sources(source_type, [source_id])
  end

  def purge_texts_for_sources(_source_type, []), do: {0, nil}

  def purge_texts_for_sources(source_type, source_ids) do
    Repo.delete_all(
      from(t in LocalizedText,
        where: t.source_type == ^source_type and t.source_id in ^source_ids
      )
    )
  end

  @doc "Physically deletes every active and archived localized text for a project."
  def reset_project_texts(project_id) do
    Repo.delete_all(from(text in LocalizedText, where: text.project_id == ^project_id))
  end
end

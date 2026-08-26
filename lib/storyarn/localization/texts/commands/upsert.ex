defmodule Storyarn.Localization.Texts.Commands.Upsert do
  @moduledoc "Concurrency-safe single-row upsert for extracted runtime text."

  alias Storyarn.Localization.LocalizedText
  alias Storyarn.Localization.Texts.Commands.Create
  alias Storyarn.Localization.Texts.Commands.TranslationAttributes
  alias Storyarn.Localization.Texts.Queries.Texts, as: TextsQuery
  alias Storyarn.Platform.Shared.MapUtils
  alias Storyarn.Repo

  @doc """
  Upserts a localized text by its composite key.
  Creates if not exists, updates source_text if hash changed.
  Returns `{:ok, localized_text}` or `{:error, changeset}`.
  """
  def upsert_text(project_id, attrs) do
    do_upsert_text(project_id, attrs, 3)
  end

  defp do_upsert_text(project_id, attrs, retries_left) do
    attrs = attrs |> MapUtils.stringify_keys() |> TranslationAttributes.apply_source_metadata()

    source_type = attrs["source_type"]
    source_id = attrs["source_id"]
    source_field = attrs["source_field"]
    locale_code = attrs["locale_code"]

    # Use insert with on_conflict to avoid TOCTOU race on concurrent extractions.
    # First try to insert; on conflict, fall back to update with status downgrade logic.
    changeset = LocalizedText.create_changeset(%LocalizedText{project_id: project_id}, attrs)

    case Repo.insert(changeset,
           on_conflict: :nothing,
           conflict_target: [:source_type, :source_id, :source_field, :locale_code]
         ) do
      {:ok, %{id: nil}} ->
        resolve_upsert_conflict(project_id, attrs, source_type, source_id, source_field, locale_code, retries_left)

      {:ok, text} ->
        {:ok, text}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp update_source_text(%LocalizedText{} = existing, attrs) do
    new_hash = attrs["source_text_hash"]

    if new_hash && new_hash != existing.source_text_hash do
      new_status = if TranslationAttributes.present?(existing.translated_text), do: "review", else: "pending"

      existing
      |> LocalizedText.source_update_changeset(%{
        "source_text" => attrs["source_text"],
        "source_text_hash" => new_hash,
        "word_count" => attrs["word_count"],
        "speaker_sheet_id" => attrs["speaker_sheet_id"],
        "content_role" => attrs["content_role"],
        "vo_eligible" => attrs["vo_eligible"],
        "vo_status" => TranslationAttributes.invalidated_vo_status(existing),
        "status" => new_status,
        "archived_at" => nil,
        "archive_reason" => nil
      })
      |> Repo.update(stale_error_field: :lock_version)
    else
      # Hash unchanged — keep the runtime classification in sync as well.
      if is_nil(existing.archived_at) and
           attrs["speaker_sheet_id"] == existing.speaker_sheet_id and
           attrs["content_role"] == existing.content_role and
           attrs["vo_eligible"] == existing.vo_eligible do
        {:ok, existing}
      else
        existing
        |> LocalizedText.source_update_changeset(%{
          "speaker_sheet_id" => attrs["speaker_sheet_id"],
          "content_role" => attrs["content_role"],
          "vo_eligible" => attrs["vo_eligible"],
          "archived_at" => nil,
          "archive_reason" => nil
        })
        |> Repo.update(stale_error_field: :lock_version)
      end
    end
  end

  defp stale_lock_error?(%Ecto.Changeset{errors: errors}), do: Keyword.has_key?(errors, :lock_version)
  defp stale_lock_error?(_changeset), do: false

  defp maybe_retry_upsert(error, changeset, project_id, attrs, retries_left) do
    if retries_left > 0 and stale_lock_error?(changeset),
      do: do_upsert_text(project_id, attrs, retries_left - 1),
      else: error
  end

  defp resolve_upsert_conflict(project_id, attrs, source_type, source_id, source_field, locale_code, retries_left) do
    existing = TextsQuery.get_text_by_source(source_type, source_id, source_field, locale_code, include_archived: true)

    case if(existing, do: update_source_text(existing, attrs), else: Create.create_text(project_id, attrs)) do
      {:error, changeset} = error -> maybe_retry_upsert(error, changeset, project_id, attrs, retries_left)
      result -> result
    end
  end
end

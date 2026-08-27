defmodule Storyarn.Localization.Texts.Commands.Update do
  @moduledoc "Updates translator-owned Texts state under project and reference locks."

  import Ecto.Query, warn: false

  alias Storyarn.Localization.LocalizedText
  alias Storyarn.Localization.ProjectAccess
  alias Storyarn.Localization.Texts.Commands.TranslationAttributes
  alias Storyarn.Localization.Texts.Projections.AssetRecord
  alias Storyarn.Platform.Kernel.MapAccess
  alias Storyarn.Repo

  def update_text(%LocalizedText{} = text, attrs) do
    attrs = MapAccess.stringify_keys(attrs)

    fn ->
      update_text_in_transaction(text, attrs)
    end
    |> Repo.transaction()
    |> normalize_update_text_result(text, attrs)
  end

  defp update_text_in_transaction(text, attrs) do
    # localized_texts activity triggers update the project row. Lock it for
    # update before touching localized_texts. Besides keeping normal writers
    # project-first, this prevents a DDL migration that already owns every
    # project row from deadlocking while it upgrades its localized_texts lock.
    # The caller's project_id is only an identity hint: the row is re-read and
    # ownership-checked below while locked.
    case ProjectAccess.lock_active_project(text.project_id, :update) do
      {:ok, _project} -> :ok
      {:error, reason} -> Repo.rollback(reason)
    end

    locked_text =
      Repo.one(
        from(current in LocalizedText,
          where:
            current.id == ^text.id and current.project_id == ^text.project_id and
              is_nil(current.archived_at),
          lock: "FOR UPDATE"
        )
      ) || Repo.rollback(:localized_text_not_active)

    attrs =
      attrs
      |> lock_and_normalize_translation_references!(locked_text)
      |> TranslationAttributes.prepare_translation_attrs(locked_text)

    # Build from the caller's struct so optimistic_lock/3 still detects a stale
    # editor. The locked row supplies the final-state reference validation.
    case text
         |> LocalizedText.update_changeset(attrs)
         |> Repo.update(stale_error_field: :lock_version) do
      {:ok, updated_text} -> updated_text
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp normalize_update_text_result({:ok, %LocalizedText{} = text}, _original, _attrs), do: {:ok, text}

  defp normalize_update_text_result({:error, %Ecto.Changeset{} = changeset}, _text, _attrs), do: {:error, changeset}

  defp normalize_update_text_result({:error, reason}, text, attrs) do
    {field, message} = update_text_error(reason)

    changeset =
      text
      |> LocalizedText.update_changeset(attrs)
      |> Ecto.Changeset.add_error(field, message, reason: reason)

    {:error, changeset}
  end

  defp update_text_error(:localized_text_not_found), do: {:base, "no longer exists"}

  defp update_text_error(:localized_text_not_active), do: {:base, "is archived and can no longer be edited"}

  defp update_text_error(:project_not_found), do: {:base, "belongs to a project that no longer exists"}

  defp update_text_error(:project_not_active), do: {:base, "belongs to a project in trash"}

  defp update_text_error({:invalid_project_id, _project_id}), do: {:base, "belongs to an invalid project"}

  defp update_text_error({:immutable_localization_reference, :speaker_sheet_id}),
    do: {:speaker_sheet_id, "cannot be changed manually"}

  defp update_text_error({:invalid_project_reference, :speaker_sheet_id, _value}),
    do: {:speaker_sheet_id, "must reference an active sheet in this project"}

  defp update_text_error({:invalid_project_reference, :vo_asset_id, _value}),
    do: {:vo_asset_id, "must reference an asset in this project"}

  defp update_text_error({:invalid_voiceover_asset_type, _asset_id}), do: {:vo_asset_id, "must reference an audio asset"}

  defp update_text_error(_reason), do: {:base, "could not be updated"}

  defp lock_and_normalize_translation_references!(attrs, text) do
    if Map.has_key?(attrs, "speaker_sheet_id") do
      Repo.rollback({:immutable_localization_reference, :speaker_sheet_id})
    end

    speaker_sheet_id =
      text.speaker_sheet_id

    vo_asset_id =
      if Map.has_key?(attrs, "vo_asset_id"),
        do: attrs["vo_asset_id"],
        else: text.vo_asset_id

    case ProjectAccess.lock_active_references(text.project_id, [
           {:sheet, :speaker_sheet_id, speaker_sheet_id},
           {:asset, :vo_asset_id, vo_asset_id}
         ]) do
      {:ok, [normalized_speaker_sheet_id, normalized_vo_asset_id]} ->
        validate_voiceover_asset_type!(normalized_vo_asset_id)

        attrs
        |> maybe_put_normalized_reference(
          "speaker_sheet_id",
          normalized_speaker_sheet_id
        )
        |> maybe_put_normalized_reference("vo_asset_id", normalized_vo_asset_id)

      {:error, reason} ->
        Repo.rollback(reason)
    end
  end

  defp maybe_put_normalized_reference(attrs, key, value) do
    if Map.has_key?(attrs, key), do: Map.put(attrs, key, value), else: attrs
  end

  defp validate_voiceover_asset_type!(nil), do: :ok

  defp validate_voiceover_asset_type!(asset_id) do
    case Repo.one(
           from(asset in AssetRecord,
             where:
               asset.id == ^asset_id and
                 is_nil(asset.deleted_at) and
                 like(asset.content_type, "audio/%"),
             select: asset.id
           )
         ) do
      ^asset_id -> :ok
      nil -> Repo.rollback({:invalid_voiceover_asset_type, asset_id})
    end
  end
end

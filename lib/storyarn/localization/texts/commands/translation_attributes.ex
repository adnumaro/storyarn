defmodule Storyarn.Localization.Texts.Commands.TranslationAttributes do
  @moduledoc """
  Command-side preparation of translation state and voice-over metadata.

  These transformations stamp lifecycle timestamps and therefore belong with
  state-changing use cases rather than in the pure `rules/` role.
  """

  alias Storyarn.Localization.SourceContract
  alias Storyarn.Platform.Shared.TimeHelpers

  def apply_source_metadata(attrs) do
    case SourceContract.field_metadata(attrs["source_type"], attrs["source_field"]) do
      nil ->
        attrs

      metadata ->
        attrs
        |> Map.put("content_role", metadata.content_role)
        |> Map.put("vo_eligible", metadata.vo_eligible)
    end
  end

  def prepare_translation_attrs(attrs, text) do
    attrs = Map.delete(attrs, "translated_source_hash")

    attrs =
      case Map.fetch(attrs, "translated_text") do
        :error ->
          maybe_mark_reviewed(attrs)

        {:ok, translated_text} when is_binary(translated_text) ->
          if present?(translated_text) do
            attrs
            |> Map.put("translated_source_hash", text.source_text_hash)
            |> promote_pending_to_draft()
            |> Map.put_new("machine_translated", false)
            |> Map.put("last_translated_at", TimeHelpers.now())
            |> maybe_mark_reviewed()
          else
            attrs
            |> Map.put("translated_text", nil)
            |> Map.put("translated_source_hash", nil)
            |> Map.put("status", "pending")
            |> Map.put("machine_translated", false)
          end

        {:ok, _translated_text} ->
          attrs
          |> Map.put("translated_text", nil)
          |> Map.put("translated_source_hash", nil)
          |> Map.put("status", "pending")
          |> Map.put("machine_translated", false)
      end

    maybe_invalidate_voiceover(attrs, text)
  end

  def prepare_create_translation_attrs(attrs) do
    attrs = Map.delete(attrs, "translated_source_hash")

    case Map.get(attrs, "translated_text") do
      translated_text when is_binary(translated_text) ->
        if present?(translated_text) do
          attrs
          |> Map.put("translated_source_hash", attrs["source_text_hash"])
          |> promote_pending_to_draft()
          |> Map.put_new("last_translated_at", TimeHelpers.now())
        else
          Map.put(attrs, "translated_text", nil)
        end

      _translated_text ->
        attrs
    end
  end

  def maybe_clear_ineligible_voice(attrs, %{vo_eligible: true}), do: attrs

  def maybe_clear_ineligible_voice(attrs, %{vo_eligible: false}) do
    attrs
    |> Map.put(:vo_status, "none")
    |> Map.put(:vo_asset_id, nil)
  end

  def invalidated_vo_status(%{vo_eligible: true, vo_status: status}) when status in ["recorded", "approved"], do: "needed"

  def invalidated_vo_status(%{vo_eligible: true, vo_asset_id: asset_id}) when not is_nil(asset_id), do: "needed"
  def invalidated_vo_status(text), do: text.vo_status

  def present?(value) when is_binary(value), do: String.trim(value) != ""
  def present?(_value), do: false

  defp maybe_mark_reviewed(%{"status" => "final"} = attrs) do
    Map.put_new(attrs, "last_reviewed_at", TimeHelpers.now())
  end

  defp maybe_mark_reviewed(attrs), do: attrs

  defp promote_pending_to_draft(%{"status" => "pending"} = attrs), do: Map.put(attrs, "status", "draft")
  defp promote_pending_to_draft(attrs), do: Map.put_new(attrs, "status", "draft")

  defp maybe_invalidate_voiceover(attrs, text) do
    translation_changed? =
      Map.has_key?(attrs, "translated_text") and attrs["translated_text"] != text.translated_text

    replacement_recording? =
      Map.has_key?(attrs, "vo_asset_id") and attrs["vo_asset_id"] != text.vo_asset_id and
        attrs["vo_status"] in ["recorded", "approved"]

    if translation_changed? and existing_voiceover?(text) and not replacement_recording? do
      Map.put(attrs, "vo_status", invalidated_vo_status(text))
    else
      attrs
    end
  end

  defp existing_voiceover?(%{vo_eligible: true, vo_status: status}) when status in ["recorded", "approved"], do: true
  defp existing_voiceover?(%{vo_eligible: true, vo_asset_id: asset_id}), do: not is_nil(asset_id)
  defp existing_voiceover?(_text), do: false
end

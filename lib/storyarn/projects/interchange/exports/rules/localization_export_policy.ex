defmodule Storyarn.Projects.LocalizationExportPolicy do
  @moduledoc false

  alias Storyarn.Platform.Kernel.MapAccess
  alias Storyarn.Projects.Exports.ExportOptions

  def text_eligible?(text, %ExportOptions{localization_policy: policy}), do: text_eligible?(text, policy)

  def text_eligible?(text, :release) do
    present?(attr(text, :translated_text)) and attr(text, :status) == "final" and
      not is_nil(attr(text, :source_text_hash)) and
      attr(text, :translated_source_hash) == attr(text, :source_text_hash) and
      is_nil(attr(text, :archived_at))
  end

  def text_eligible?(text, :preview) do
    present?(attr(text, :translated_text)) and is_nil(attr(text, :archived_at))
  end

  def text_eligible?(_text, policy), do: raise(ArgumentError, "unknown localization export policy: #{inspect(policy)}")

  def voiceover_eligible?(text, %ExportOptions{localization_policy: policy}), do: voiceover_eligible?(text, policy)

  def voiceover_eligible?(text, :release) do
    text_eligible?(text, :release) and attr(text, :vo_eligible) == true and attr(text, :vo_status) == "approved" and
      not is_nil(attr(text, :vo_asset_id)) and is_nil(attr(text, :archived_at))
  end

  def voiceover_eligible?(text, :preview) do
    text_eligible?(text, :preview) and attr(text, :vo_eligible) == true and
      attr(text, :vo_status) in ["recorded", "approved"] and not is_nil(attr(text, :vo_asset_id)) and
      is_nil(attr(text, :archived_at))
  end

  def voiceover_eligible?(_text, policy),
    do: raise(ArgumentError, "unknown localization export policy: #{inspect(policy)}")

  defp attr(record, field), do: MapAccess.get_flexible(record, field)
  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_value), do: false
end

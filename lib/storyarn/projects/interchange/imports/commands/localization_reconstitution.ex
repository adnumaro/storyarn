defmodule Storyarn.Projects.LocalizationReconstitution do
  @moduledoc """
  Exact Localization record writer for a Project import.

  This is the explicit reconstitution exception: it recreates imported language,
  localized-text and glossary state inside the enclosing Project import workflow.
  It is not an ordinary Localization writer and must not be called by editors or
  routine translation workflows.
  """

  alias Storyarn.Projects.LocalizationSourceContract
  alias Storyarn.Projects.Persistence.GlossaryEntryRecord
  alias Storyarn.Projects.Persistence.LocalizedTextRecord
  alias Storyarn.Projects.Persistence.ProjectLanguageRecord
  alias Storyarn.Repo

  def import_language(project_id, attrs) do
    %ProjectLanguageRecord{project_id: project_id}
    |> ProjectLanguageRecord.create_changeset(attrs)
    |> Repo.insert()
  end

  def bulk_import_texts(attrs_list) do
    attrs_list
    |> Enum.flat_map(fn attrs ->
      case LocalizationSourceContract.field_metadata(attrs[:source_type], attrs[:source_field]) do
        nil ->
          []

        metadata ->
          [
            attrs
            |> Map.put(:content_role, metadata.content_role)
            |> Map.put(:vo_eligible, metadata.vo_eligible)
            |> maybe_clear_ineligible_voice(metadata)
          ]
      end
    end)
    |> Enum.chunk_every(500)
    |> Enum.each(fn chunk ->
      Repo.insert_all(LocalizedTextRecord, chunk, on_conflict: :nothing)
    end)
  end

  def bulk_import_glossary_entries(attrs_list) do
    attrs_list
    |> Enum.chunk_every(500)
    |> Enum.each(&Repo.insert_all(GlossaryEntryRecord, &1))
  end

  defp maybe_clear_ineligible_voice(attrs, %{vo_eligible: true}), do: attrs

  defp maybe_clear_ineligible_voice(attrs, %{vo_eligible: false}) do
    attrs
    |> Map.put(:vo_status, "none")
    |> Map.put(:vo_asset_id, nil)
  end
end

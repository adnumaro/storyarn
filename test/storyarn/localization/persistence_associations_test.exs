defmodule Storyarn.Localization.PersistenceAssociationsTest do
  use ExUnit.Case, async: true

  alias Storyarn.Localization.GlossaryEntry
  alias Storyarn.Localization.LocalizedText
  alias Storyarn.Localization.Persistence.AssetRecord
  alias Storyarn.Localization.Persistence.BlockRecord
  alias Storyarn.Localization.Persistence.ProjectRecord
  alias Storyarn.Localization.Persistence.SheetRecord
  alias Storyarn.Localization.Persistence.UserRecord
  alias Storyarn.Localization.Persistence.WorkspaceRecord
  alias Storyarn.Localization.ProjectLanguage
  alias Storyarn.Localization.ProviderConfig
  alias Storyarn.Localization.TranslationRun

  test "localization schemas associate only to context-owned persistence records" do
    assert association(GlossaryEntry, :project) == ProjectRecord
    assert association(ProjectLanguage, :project) == ProjectRecord
    assert association(ProviderConfig, :project) == ProjectRecord

    assert association(LocalizedText, :project) == ProjectRecord
    assert association(LocalizedText, :vo_asset) == AssetRecord
    assert association(LocalizedText, :speaker_sheet) == SheetRecord
    assert association(LocalizedText, :translated_by) == UserRecord
    assert association(LocalizedText, :reviewed_by) == UserRecord

    assert association(TranslationRun, :project) == ProjectRecord
    assert association(TranslationRun, :requested_by) == UserRecord

    assert association(ProjectRecord, :workspace) == WorkspaceRecord
    assert association(BlockRecord, :sheet) == SheetRecord
  end

  defp association(schema, name), do: schema.__schema__(:association, name).related
end

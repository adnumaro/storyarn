defmodule Storyarn.Architecture.LocalizationProjectionAssociationsTest do
  use ExUnit.Case, async: true

  alias Storyarn.Localization.Glossary.Data.ProjectRecord, as: GlossaryProjectRecord
  alias Storyarn.Localization.GlossaryEntry
  alias Storyarn.Localization.Languages.Data.ProjectRecord, as: LanguagesProjectRecord
  alias Storyarn.Localization.LocalizedText
  alias Storyarn.Localization.ProjectLanguage
  alias Storyarn.Localization.ProviderConfig
  alias Storyarn.Localization.Providers.Data.ProjectRecord, as: ProvidersProjectRecord
  alias Storyarn.Localization.Texts.Data.AssetRecord, as: TextsAssetRecord
  alias Storyarn.Localization.Texts.Data.BlockRecord, as: TextsBlockRecord
  alias Storyarn.Localization.Texts.Data.ProjectRecord, as: TextsProjectRecord
  alias Storyarn.Localization.Texts.Data.SheetRecord, as: TextsSheetRecord
  alias Storyarn.Localization.Texts.Data.UserRecord, as: TextsUserRecord
  alias Storyarn.Localization.Translation.Data.ProjectRecord, as: TranslationProjectRecord
  alias Storyarn.Localization.Translation.Data.UserRecord, as: TranslationUserRecord
  alias Storyarn.Localization.TranslationRun

  test "owned schemas associate to the projection of their own capability" do
    assert association(GlossaryEntry, :project) == GlossaryProjectRecord
    assert association(ProjectLanguage, :project) == LanguagesProjectRecord
    assert association(ProviderConfig, :project) == ProvidersProjectRecord

    assert association(LocalizedText, :project) == TextsProjectRecord
    assert association(LocalizedText, :vo_asset) == TextsAssetRecord
    assert association(LocalizedText, :speaker_sheet) == TextsSheetRecord
    assert association(LocalizedText, :translated_by) == TextsUserRecord
    assert association(LocalizedText, :reviewed_by) == TextsUserRecord

    assert association(TranslationRun, :project) == TranslationProjectRecord
    assert association(TranslationRun, :requested_by) == TranslationUserRecord
    assert association(TextsBlockRecord, :sheet) == TextsSheetRecord
  end

  defp association(schema, name), do: schema.__schema__(:association, name).related
end

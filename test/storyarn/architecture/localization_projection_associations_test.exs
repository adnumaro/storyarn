defmodule Storyarn.Architecture.LocalizationProjectionAssociationsTest do
  use ExUnit.Case, async: true

  alias Storyarn.Localization.Glossary.Projections.ProjectRecord, as: GlossaryProjectRecord
  alias Storyarn.Localization.GlossaryEntry
  alias Storyarn.Localization.Languages.Projections.ProjectRecord, as: LanguagesProjectRecord
  alias Storyarn.Localization.LocalizedText
  alias Storyarn.Localization.ProjectLanguage
  alias Storyarn.Localization.ProviderConfig
  alias Storyarn.Localization.Providers.Projections.ProjectRecord, as: ProvidersProjectRecord
  alias Storyarn.Localization.Texts.Projections.AssetRecord, as: TextsAssetRecord
  alias Storyarn.Localization.Texts.Projections.BlockRecord, as: TextsBlockRecord
  alias Storyarn.Localization.Texts.Projections.ProjectRecord, as: TextsProjectRecord
  alias Storyarn.Localization.Texts.Projections.SheetRecord, as: TextsSheetRecord
  alias Storyarn.Localization.Texts.Projections.UserRecord, as: TextsUserRecord
  alias Storyarn.Localization.Translation.Projections.ProjectRecord, as: TranslationProjectRecord
  alias Storyarn.Localization.Translation.Projections.UserRecord, as: TranslationUserRecord
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

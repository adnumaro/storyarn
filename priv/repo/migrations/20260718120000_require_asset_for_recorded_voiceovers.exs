Code.require_file(
  Path.expand(
    "../migration_helpers/voiceover_reference_integrity.exs",
    __DIR__
  )
)

defmodule Storyarn.Repo.Migrations.RequireAssetForRecordedVoiceovers do
  use Ecto.Migration

  alias Storyarn.Repo.Migrations.VoiceoverReferenceIntegrity

  def up do
    Enum.each(VoiceoverReferenceIntegrity.lock_sql(), &execute/1)
    Enum.each(VoiceoverReferenceIntegrity.repair_sql(), &execute/1)
    execute(VoiceoverReferenceIntegrity.trigger_function_sql())
    Enum.each(VoiceoverReferenceIntegrity.trigger_sql(), &execute/1)

    create constraint(
             :localized_texts,
             :localized_texts_recorded_voiceover_requires_asset,
             check: "vo_status NOT IN ('recorded', 'approved') OR vo_asset_id IS NOT NULL"
           )
  end

  def down do
    execute(VoiceoverReferenceIntegrity.drop_trigger_sql())
    execute(VoiceoverReferenceIntegrity.drop_trigger_function_sql())

    drop constraint(
           :localized_texts,
           :localized_texts_recorded_voiceover_requires_asset
         )
  end
end

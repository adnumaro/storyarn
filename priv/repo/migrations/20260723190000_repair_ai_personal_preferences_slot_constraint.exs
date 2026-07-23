defmodule Storyarn.Repo.Migrations.RepairAiPersonalPreferencesSlotConstraint do
  use Ecto.Migration

  @constraint :ai_personal_preferences_slot_allowed

  def up do
    execute """
    ALTER TABLE ai_personal_preferences
    DROP CONSTRAINT IF EXISTS #{@constraint}
    """

    execute """
    ALTER TABLE ai_personal_preferences
    ADD CONSTRAINT #{@constraint}
    CHECK (slot IN ('general_assistant', 'writing_assistant', 'illustrator', 'voice'))
    """
  end

  # Restoring the legacy constraint would reject valid general-assistant rows.
  # This forward repair therefore has no safe data-preserving inverse.
  def down, do: :ok
end

defmodule Storyarn.Repo.Migrations.AddSpeechAiCapability do
  use Ecto.Migration

  def up do
    drop constraint(:ai_personal_consents, :ai_personal_consents_capability)

    create constraint(:ai_personal_consents, :ai_personal_consents_capability,
             check: "capability IN ('translation', 'suggestions', 'tasks', 'images', 'speech')"
           )
  end

  def down do
    execute "DELETE FROM ai_personal_consents WHERE capability = 'speech'"

    drop constraint(:ai_personal_consents, :ai_personal_consents_capability)

    create constraint(:ai_personal_consents, :ai_personal_consents_capability,
             check: "capability IN ('translation', 'suggestions', 'tasks', 'images')"
           )
  end
end

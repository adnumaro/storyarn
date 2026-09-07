defmodule Storyarn.Repo.Migrations.AddIdeationGenerationIdentities do
  use Ecto.Migration

  def up do
    alter table(:ideation_sessions), do: add(:recovery_identity, :uuid)

    execute "ALTER TABLE ideation_sessions ALTER COLUMN recovery_identity SET DEFAULT gen_random_uuid()"

    execute "UPDATE ideation_sessions SET recovery_identity = gen_random_uuid() WHERE recovery_identity IS NULL"

    alter table(:ideation_sessions), do: modify(:recovery_identity, :uuid, null: false)
    alter table(:ideation_session_revisions), do: add(:recovery_identity, :uuid)

    execute "ALTER TABLE ideation_session_revisions ALTER COLUMN recovery_identity SET DEFAULT gen_random_uuid()"

    execute "UPDATE ideation_session_revisions SET recovery_identity = gen_random_uuid() WHERE recovery_identity IS NULL"

    alter table(:ideation_session_revisions), do: modify(:recovery_identity, :uuid, null: false)
    alter table(:ideation_ideas), do: add(:recovery_identity, :uuid)

    execute "ALTER TABLE ideation_ideas ALTER COLUMN recovery_identity SET DEFAULT gen_random_uuid()"

    execute "UPDATE ideation_ideas SET recovery_identity = gen_random_uuid() WHERE recovery_identity IS NULL"

    alter table(:ideation_ideas), do: modify(:recovery_identity, :uuid, null: false)
    alter table(:ideation_idea_revisions), do: add(:recovery_identity, :uuid)

    execute "ALTER TABLE ideation_idea_revisions ALTER COLUMN recovery_identity SET DEFAULT gen_random_uuid()"

    execute "UPDATE ideation_idea_revisions SET recovery_identity = gen_random_uuid() WHERE recovery_identity IS NULL"

    alter table(:ideation_idea_revisions), do: modify(:recovery_identity, :uuid, null: false)
    alter table(:ideation_idea_edits), do: add(:recovery_identity, :uuid)

    execute "ALTER TABLE ideation_idea_edits ALTER COLUMN recovery_identity SET DEFAULT gen_random_uuid()"

    execute "UPDATE ideation_idea_edits SET recovery_identity = gen_random_uuid() WHERE recovery_identity IS NULL"

    alter table(:ideation_idea_edits), do: modify(:recovery_identity, :uuid, null: false)
    alter table(:ideation_reveal_operations), do: add(:recovery_identity, :uuid)

    execute "ALTER TABLE ideation_reveal_operations ALTER COLUMN recovery_identity SET DEFAULT gen_random_uuid()"

    execute "UPDATE ideation_reveal_operations SET recovery_identity = gen_random_uuid() WHERE recovery_identity IS NULL"

    alter table(:ideation_reveal_operations), do: modify(:recovery_identity, :uuid, null: false)
    alter table(:ideation_idea_publications), do: add(:recovery_identity, :uuid)

    execute "ALTER TABLE ideation_idea_publications ALTER COLUMN recovery_identity SET DEFAULT gen_random_uuid()"

    execute "UPDATE ideation_idea_publications SET recovery_identity = gen_random_uuid() WHERE recovery_identity IS NULL"

    alter table(:ideation_idea_publications), do: modify(:recovery_identity, :uuid, null: false)
  end

  def down do
    alter table(:ideation_sessions), do: remove(:recovery_identity)
    alter table(:ideation_session_revisions), do: remove(:recovery_identity)
    alter table(:ideation_ideas), do: remove(:recovery_identity)
    alter table(:ideation_idea_revisions), do: remove(:recovery_identity)
    alter table(:ideation_idea_edits), do: remove(:recovery_identity)
    alter table(:ideation_reveal_operations), do: remove(:recovery_identity)
    alter table(:ideation_idea_publications), do: remove(:recovery_identity)
  end
end
